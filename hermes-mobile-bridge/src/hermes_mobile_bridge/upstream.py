"""Long-lived loopback desktop RPC transport, independent of phone connections."""
import asyncio
import contextlib
import uuid
import aiohttp
from .core import Problem, now


class Backend:
    def __init__(self, name, cfg, on_event, on_health):
        self.name, self.cfg = name, cfg
        self.on_event, self.on_health = on_event, on_health
        self.ws = None
        self.pending = {}
        self.connected = False
        self.bot_mode_supported = False
        self.server_requests_supported = False
        self.declines_not_shown = False
        self.last_seen = None
        self.generation = 0
        self.paths = set()
        self.http = None
        self.task = None
        self.closing = False

    async def start(self):
        self.http = aiohttp.ClientSession(timeout=aiohttp.ClientTimeout(total=15), headers={"Authorization": "Bearer " + self.cfg["token"]}, trust_env=False)
        self.task = asyncio.create_task(self._loop())

    async def close(self):
        self.closing = True
        if self.task:
            self.task.cancel()
            with contextlib.suppress(asyncio.CancelledError):
                await self.task
        if self.http:
            await self.http.close()

    async def rest(self, method, path, body=None, query=None):
        try:
            async with self.http.request(method, self.cfg["url"].rstrip("/") + path, json=body, params=query, allow_redirects=False) as res:
                if res.status >= 400 or res.status < 200 or res.status >= 300:
                    # Never return backend exception text, config, or credentials.
                    raise Problem(res.status if res.status in {400, 404, 409, 413, 422} else 502, "upstream_rejected", "Hermes rejected the request", upstream_status=res.status)
                return await res.json()
        except (aiohttp.ClientError, asyncio.TimeoutError, ValueError):
            raise Problem(503, "upstream_unavailable", "Hermes request failed; mutation outcome may be uncertain") from None

    async def rpc(self, method, params=None):
        if not self.ws or self.ws.closed:
            raise Problem(503, "upstream_unavailable", "Hermes connection is unavailable")
        rid = uuid.uuid4().hex
        fut = asyncio.get_running_loop().create_future()
        self.pending[rid] = fut
        try:
            await self.ws.send_json({"jsonrpc": "2.0", "id": rid, "method": method, "params": params or {}})
            # Native creation clones the default profile before publishing its
            # identity. A timeout must not strand a successfully created bot
            # before the management layer can configure and read it back.
            return await asyncio.wait_for(fut, 60 if method == "profiles.create" else 30)
        except (aiohttp.ClientError, asyncio.TimeoutError, ConnectionError):
            raise Problem(503, "upstream_uncertain", "Hermes reply was lost; do not automatically repeat the action") from None
        finally:
            self.pending.pop(rid, None)

    async def _read(self):
        async for msg in self.ws:
            if msg.type != aiohttp.WSMsgType.TEXT:
                continue
            try:
                data = msg.json()
            except ValueError:
                continue
            self.last_seen = now()
            if "id" in data and "method" in data:
                params = data.get("params") or {}
                method = data.get("method")
                if method == "clarify":
                    await self.on_event(self.name, {"type": "bridge.server_request", "session_id": params.get("session_id"),
                                                   "payload": {"id": data["id"], "method": method, "params": params}})
                else:
                    # Never grant approval or invent credentials. Window declines allow a shown Desktop peer to answer.
                    window = method in {"terminal.read", "preview.read", "preview.act", "window.read", "tour"}
                    code = 4404 if window and self.declines_not_shown else -32601
                    await self.ws.send_json({"jsonrpc": "2.0", "id": data["id"], "error": {"code": code, "message": "No Desktop window is showing this chat" if code == 4404 else "Mobile cannot handle this request"}})
            elif "id" in data:
                fut = self.pending.get(data["id"])
                if fut and not fut.done():
                    if "error" in data:
                        code = data["error"].get("code")
                        fut.set_exception(Problem(409 if code in {4009, 4090} else 502, "upstream_rpc_rejected", "Hermes rejected the operation", upstream_code=code))
                    else:
                        fut.set_result(data.get("result", {}))
            elif data.get("method") == "event":
                await self.on_event(self.name, data.get("params", {}))

    async def _loop(self):
        delay = 0.5
        while not self.closing:
            reader = None
            try:
                # Query token is confined to the audited loopback endpoint and
                # never exposed to clients or logged by this process.
                self.ws = await self.http.ws_connect(self.cfg["url"].rstrip("/") + "/api/ws", params={"token": self.cfg["token"]}, heartbeat=15, max_msg_size=16 * 1024 * 1024)
                reader = asyncio.create_task(self._read())
                await self.rpc("session.active_list")
                try:
                    spec = await self.rest("GET", "/openapi.json")
                    self.paths = set(spec.get("paths", {}))
                except Problem:
                    self.paths = set()
                self.bot_mode_supported = False
                if self.cfg.get("bot_mode_roster"):
                    try:
                        roster = await self.rpc("profiles.list", {"include_sessions": False})
                        self.bot_mode_supported = roster.get("bot_mode_protocol") is True
                    except Problem:
                        pass
                self.server_requests_supported = False
                if self.cfg.get("installed_commit") == "4bb9e57bfde8a0affb5553eff13ed6e1f14147f1":
                    capability = await self.rpc("client.capabilities", {"server_requests": True})
                    self.server_requests_supported = "clarify" in capability.get("server_requests", [])
                    self.declines_not_shown = capability.get("declines_not_shown") is True
                self.connected = True
                self.generation += 1
                delay = 0.5
                await self.on_health(self.name, True)
                await reader
            except asyncio.CancelledError:
                raise
            except Exception:
                # No exception logging: aiohttp errors can include token URLs.
                pass
            finally:
                self.connected = False
                for fut in self.pending.values():
                    if not fut.done():
                        fut.set_exception(ConnectionError("Upstream disconnected"))
                if reader:
                    reader.cancel()
                    with contextlib.suppress(asyncio.CancelledError, Exception):
                        await reader
                if self.ws:
                    await self.ws.close()
                await self.on_health(self.name, False)
            await asyncio.sleep(delay)
            delay = min(delay * 2, 15)

    def health(self):
        return {"connected": self.connected, "generation": self.generation, "last_event_at": self.last_seen, "transport": "desktop_json_rpc", "coverage": "bridge_owned_sessions"}
