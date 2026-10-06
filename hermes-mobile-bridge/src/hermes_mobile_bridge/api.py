"""Versioned HTTP/JSON contract and one authenticated SSE stream."""
import asyncio
import contextlib
import json
import uuid
from aiohttp import web
from . import __version__
from .core import ACTIVE, Problem, TERMINAL, cron, host_info, identifier, message, now, opaque, only, task, unopaque, usage
from .service import Service
from .bots import BotMode

PREFIX = "/mobile/v1"
SERVICE = web.AppKey("service", Service)
Key = getattr(web, "RequestKey", web.AppKey)
AUTH = Key("auth", dict)
BODY = Key("body", dict)


def shape(body, fields, required=(), list_limits=None):
    if not isinstance(body, dict) or set(body) - set(fields):
        raise Problem(400, "invalid_request", "Unknown fields or invalid JSON object")
    for key in required:
        if key not in body:
            raise Problem(400, "invalid_request", "Required field missing", field=key)
    for key, val in body.items():
        typ = fields[key]
        if not isinstance(val, typ) or (typ == int and isinstance(val, bool)):
            raise Problem(400, "invalid_request", "Invalid field type", field=key)
        if isinstance(val, str) and ((len(val) > 200000 and key != "content_base64") or "\x00" in val):
            raise Problem(400, "invalid_request", "Invalid field size/content", field=key)
        if typ == list and (len(val) > (list_limits or {}).get(key, 100) or any(not isinstance(v, str) or len(v) > 500 for v in val)):
            raise Problem(400, "invalid_request", "Invalid string list", field=key)
    return body


@web.middleware
async def contract(request, handler):
    service = request.app[SERVICE]
    command_id = None
    command_started = False
    try:
        header = request.headers.get("Authorization", "")
        if not header.startswith("Bearer ") or len(header) > 512:
            raise Problem(401, "unauthorized", "Application bearer credential required")
        request[AUTH] = service.store.auth(header[7:])
        if "read" not in request[AUTH]["scopes"]:
            raise Problem(403, "forbidden", "Read scope required")
        if request.method not in {"GET", "HEAD"}:
            raw = request.headers.get("Idempotency-Key", "")
            try:
                command_id = str(uuid.UUID(raw))
            except ValueError:
                raise Problem(400, "command_id_required", "Supply a UUID Idempotency-Key header") from None
            if request.content_type != "application/json":
                raise Problem(400, "invalid_request", "Use application/json, including {} for empty actions")
            try:
                request[BODY] = await request.json()
            except (ValueError, UnicodeError):
                raise Problem(400, "invalid_request", "Malformed JSON") from None
            if not isinstance(request[BODY], dict):
                raise Problem(400, "invalid_request", "JSON object required")
            # Scope check precedes command journal access; cached mutations also
            # respect revoked/reduced credentials.
            needed = "chat.control" if any(s in request.path for s in ("/conversations", "/runs", "/attachments", "/bots", "/captures")) else "approvals.respond" if "/attention" in request.path else "tasks.manage"
            if needed not in request[AUTH]["scopes"]:
                raise Problem(403, "forbidden", "Credential lacks action scope")
            old = service.store.command_begin(command_id, request[AUTH]["id"], {"method": request.method, "path": request.path, "query": list(request.query.items()), "body": request[BODY]}, replay_safe=request.path in {PREFIX + "/captures", PREFIX + "/captures/uploads"})
            if old is not None:
                return web.json_response(old["body"], status=old["status"])
        command_started = command_id is not None
        response = await handler(request)
        if command_id:
            service.store.command_finish(command_id, {"status": response.status, "body": json.loads(response.text)})
        return response
    except Problem as err:
        if command_started:
            if err.status == 503:
                service.store.db.execute("UPDATE commands SET status='uncertain' WHERE id=? AND status='pending'", (command_id,))
                service.store.db.commit()
            else:
                # Don't overwrite a prior command/conflict result.
                row = service.store.db.execute("SELECT status FROM commands WHERE id=?", (command_id,)).fetchone()
                if row and row[0] == "pending":
                    service.store.command_finish(command_id, {"status": err.status, "body": err.body()})
        return web.json_response(err.body(), status=err.status)
    except web.HTTPException as err:
        return web.json_response({"error": {"code": "request_rejected", "message": err.reason, "details": {}}}, status=err.status)
    except Exception:
        # Never reflect tracebacks (upstream URL may contain credentials).
        return web.json_response({"error": {"code": "internal_error", "message": "Bridge request failed; inspect state before retrying actions", "details": {}}}, status=500)


def svc(request):
    return request.app[SERVICE]


def profile(request, scope="read"):
    p = request.query.get("profile", "default")
    return p, svc(request).require(request[AUTH], p, scope)


def workspace(service, profile_name, body):
    if body.get("workspace") and body["workspace"] not in service.backends[profile_name].cfg["workspaces"]:
        raise Problem(400, "unknown_workspace", "Choose a configured Studio workspace")


async def capabilities(request):
    s = svc(request)
    result = {}
    for p in s.profiles(request[AUTH]):
        b = s.backends[p]
        paths = b.paths
        available = lambda route: b.connected and route in paths
        result[p] = {"health": b.health(), "features": {"sessions": b.connected, "runs": b.connected, "runReplay": True, "stop": b.connected, "steering": b.connected, "approvals": {"observe": b.connected, "respond": False, "reason": "upstream_fifo_without_exact_target", "clarifications": b.connected and (b.server_requests_supported or b.cfg.get("installed_commit") != "4bb9e57bfde8a0affb5553eff13ed6e1f14147f1")}, "profiles": True, "cron": available("/api/cron/jobs"), "kanban": bool(b.cfg["boards"]) and available("/api/plugins/kanban/board"), "usage": available("/api/analytics/usage"), "skills": available("/api/skills"), "tools": available("/api/tools/toolsets"), "mcp": available("/api/mcp/servers"), "artifacts": bool(b.cfg["artifact_roots"]), "botMode": b.connected and b.cfg.get("bot_mode_roster", False) and b.bot_mode_supported, "botChat": b.connected and b.cfg.get("bot_chat_control", False) and b.cfg.get("bot_mode_roster", False) and b.bot_mode_supported, "botThreads": b.connected and b.cfg.get("bot_chat_control", False) and b.cfg.get("bot_mode_roster", False) and b.bot_mode_supported, "captures": True, "botRooms": False, "attachments": b.connected and b.cfg.get("installed_commit") in {"2a4c9afd7bd", "4bb9e57bfde8a0affb5553eff13ed6e1f14147f1"}, "imageUpload": b.connected and b.cfg.get("installed_commit") == "4bb9e57bfde8a0affb5553eff13ed6e1f14147f1"}, "desktop_contract_audited": 2, "audited_commit": b.cfg.get("installed_commit") or "2a4c9afd7bd", "installed_commit": b.cfg.get("installed_commit"), "boards": b.cfg["boards"], "workspaces": [{"id": k, "name": k} for k in b.cfg["workspaces"]]}
        result[p]["features"].update(BotMode(s, request[AUTH]).capabilities(p))
    return web.json_response({"api_version": 1, "bridge_version": __version__, "journal_epoch": s.store.epoch, "cursor": s.store.cursor(), "scopes": request[AUTH]["scopes"], "profiles": result, "retention": {"global_events": s.cfg["event_limit"], "per_run_events": s.cfg["run_event_limit"], "days": s.cfg["event_days"]}, "coverage": "Controlled runs are bridge-owned desktop sessions; other-process activity is read-only and incomplete"})


async def bots(request):
    return web.json_response({"bots": await BotMode(svc(request), request[AUTH]).list()})


async def bot_inventory(request):
    return web.json_response(await BotMode(svc(request), request[AUTH]).inventory(request.query.get("profile", "default"), request.query.get("bot_id")))


async def bot_create(request):
    fields = {"name":str,"description":str,"soul":str,"model":str,"provider":str,"skills":list,"toolsets":list,"mcp_servers":list}
    body = shape(request[BODY], fields, ("name", "description"), {"skills":512,"toolsets":512,"mcp_servers":512})
    bot = await BotMode(svc(request), request[AUTH]).create(body, request.query.get("profile", "default"))
    return web.json_response({"bot":bot}, status=201)


async def bot_update(request):
    fields = {"name":str,"description":str,"soul":str,"model":str,"provider":str,"skills":list,"toolsets":list,"mcp_servers":list,"confirm_expensive_model":bool}
    bot = await BotMode(svc(request), request[AUTH]).update(request.match_info["bid"], shape(request[BODY], fields, list_limits={"skills":512,"toolsets":512,"mcp_servers":512}))
    return web.json_response({"bot":bot})


async def bot_duplicate(request):
    shape(request[BODY], {})
    bot = await BotMode(svc(request), request[AUTH]).duplicate(request.match_info["bid"])
    return web.json_response({"bot":bot},status=201)


async def bot_hide(request):
    body = shape(request[BODY], {"hidden":bool}, ("hidden",))
    return web.json_response(await BotMode(svc(request), request[AUTH]).hide(request.match_info["bid"], body["hidden"]))


async def bot_detail(request):
    return web.json_response(await BotMode(svc(request), request[AUTH]).detail(request.match_info["bid"]))


async def bot_conversation(request):
    adapter = BotMode(svc(request), request[AUTH])
    if request.method == "POST":
        shape(request[BODY], {})
        return web.json_response(await adapter.open(request.match_info["bid"]))
    return web.json_response(await adapter.conversation(request.match_info["bid"]))


async def command_status(request):
    s = svc(request)
    try: cid = str(uuid.UUID(request.match_info['cid']))
    except ValueError: raise Problem(400, 'invalid_id', 'Provide a command UUID') from None
    row = s.store.db.execute('SELECT credential,status,result FROM commands WHERE id=?', (cid,)).fetchone()
    if not row: return web.json_response({'state': 'not_received'})
    if row['credential'] != request[AUTH]['id']: raise Problem(403, 'forbidden', 'Command belongs to another credential')
    return web.json_response({'state': row['status'], 'result': json.loads(row['result']) if row['result'] else None})


async def capture_save(request):
    from .captures import Captures
    body = shape(request[BODY], {"client_capture_id": str, "created_at": str, "kind": str, "text": str, "attachment_ids": list, "context": dict},
                 ("client_capture_id", "created_at", "kind", "text"), list_limits={"attachment_ids": 4})
    return web.json_response(svc(request).captures.save(request[AUTH], body), status=201)


async def capture_upload(request):
    from .captures import Captures
    body = shape(request[BODY], {"name": str, "content_type": str, "content_base64": str}, ("name", "content_type", "content_base64"))
    return web.json_response(svc(request).captures.upload(request[AUTH], body, request.headers["Idempotency-Key"]), status=201)


async def bot_threads(request):
    fields = shape(request[BODY], {"title": str, "model": str, "provider": str, "reasoning_effort": str, "workspace": str})
    return web.json_response(await BotMode(svc(request), request[AUTH]).create_thread(
        request.match_info["bid"], fields, request.headers["Idempotency-Key"]), status=201)


async def conversations(request):
    s = svc(request)
    p, b = profile(request, "chat.control" if request.method == "POST" else "read")
    if request.method == "POST":
        body = shape(request[BODY], {"title": str, "model": str, "provider": str, "reasoning_effort": str, "workspace": str})
        workspace(s, p, body)
        if body.get("reasoning_effort") not in {None, "none", "minimal", "low", "medium", "high", "xhigh"}:
            raise Problem(400, "invalid_reasoning", "Unsupported reasoning effort")
        return web.json_response(await s.create(p, body), status=201)
    query = {"profile": p, "limit": integer_query(request, "limit", 50, 1, 100), "offset": integer_query(request, "offset", 0, 0, 100000)}
    if request.query.get("q"):
        raw = await b.rest("GET", "/api/sessions/search", query={"profile": p, "q": request.query["q"], "limit": query["limit"]})
        rows = raw.get("results", [])
    else:
        raw = await b.rest("GET", "/api/sessions", query=query)
        rows = raw.get("sessions", [])
    output = []
    for row in rows:
        sid = row.get("session_id") or row.get("id")
        if sid:
            item = s.observe_conversation(p, row)
            if "snippet" in row:
                item["snippet"] = row["snippet"]
            output.append(item)
    seen = {x["id"] for x in output}
    if not request.query.get("q") and query["offset"] == 0:
        for row in s.store.db.execute("SELECT id FROM conversations WHERE profile=? AND owned=1", (p,)).fetchall():
            c = s.store.get("conversations", row[0])
            if c["id"] not in seen and not c["data"].get("canonical") and not c["data"].get("deleted") and s.store.db.execute("SELECT COUNT(*) FROM runs WHERE conversation_id=?", (c["id"],)).fetchone()[0] == 0:
                output.append(s.conversation_view(c) | {"draft": True})
    if query["offset"] == 0 and b.cfg.get("bot_mode_roster") and b.bot_mode_supported:
        adapter = BotMode(s, request[AUTH])
        _, roster = await adapter.roster(p)
        for bot in roster:
            native = bot['name']
            if request.query.get('q'):
                found = await b.rest('GET', '/api/sessions/search', query={'profile': native, 'q': request.query['q'], 'limit': query['limit']})
                native_rows = found.get('results', [])
            else:
                raw_sessions = await b.rpc('session.list', {'profile': native, 'include_hidden': True})
                native_rows = raw_sessions.get('sessions', [])
            for row in native_rows:
                if row.get('title') == 'Bot Chat':
                    continue
                sid = row.get('resolved_id') or row.get('session_id') or row.get('id')
                if not sid:
                    continue
                cid = opaque(p, sid)
                previous = s.store.db.execute('SELECT id FROM conversations WHERE profile=? AND stored_id=?', (p, sid)).fetchone()
                cid = previous[0] if previous else cid
                old = s.store.get('conversations', cid) if previous else None
                s.store.save_conversation(cid, p, sid, old['live_id'] if old else None, old['owned'] if old else False,
                    only(row, 'title model provider archived started_at message_count last_active preview source') |
                    {'bot_id': opaque(p,native), 'bot_profile': native, 'canonical': False})
                output = [r for r in output if r['id'] != cid]
                output.append(s.conversation_view(s.store.get('conversations', cid)))
            if bot.get("canonical_session") and not request.query.get("q"):
                chat = (await adapter.conversation(opaque(p, bot['name'])))["conversation"]
                output = [r for r in output if r["id"] != chat["id"]]
                output.append(chat)
    return web.json_response({"conversations": output, "total": raw.get("total"), "offset": query["offset"]})


def integer_query(request, key, default, minimum, maximum):
    try:
        val = int(request.query.get(key, default))
        if not minimum <= val <= maximum:
            raise ValueError()
        return val
    except ValueError:
        raise Problem(400, "invalid_request", "Invalid integer query", field=key) from None


async def conversation_detail(request):
    s = svc(request)
    c = s.conversation(request[AUTH], request.match_info["cid"], "read" if request.method == "GET" else "chat.control")
    b, sid = s.backends[c["profile"]], c["stored_id"]
    if c["data"].get("canonical"):
        if request.method == "GET":
            return web.json_response(await BotMode(s, request[AUTH]).conversation(c["data"]["bot_id"]))
        # Canonical relationship identity is source-owned; generic rename/archive/delete may not break it.
        raise Problem(409, "canonical_chat_protected", "Bot Chat history is managed through the bot on the Studio")
    if request.method == "GET":
        snapshot_cursor = s.store.cursor()
        try:
            detail, history = await asyncio.gather(b.rest("GET", f"/api/sessions/{sid}", query={"profile": s.session_profile(c)}), b.rest("GET", f"/api/sessions/{sid}/messages", query={"profile": s.session_profile(c)}))
        except Problem as err:
            count = s.store.db.execute("SELECT COUNT(*) FROM runs WHERE conversation_id=?", (c["id"],)).fetchone()[0]
            if err.status == 404 and c["owned"] and count == 0:
                return web.json_response({"conversation": s.conversation_view(c) | {"draft": True}, "messages": [], "cursor": s.store.cursor()})
            raise
        s.observe_conversation(c["profile"], detail)
        return web.json_response({"conversation": s.conversation_view(s.store.get("conversations", c["id"])), "messages": [message(m) for m in history.get("messages", [])], "current_stored_id": history.get("session_id"), "cursor": snapshot_cursor, "observed_runs": [s.run_view(r) for r in s.store.runs([c["profile"]], limit=200) if r["conversation_id"] == c["id"]]})
    if request.method == "PATCH":
        body = shape(request[BODY], {"title": str, "archived": bool})
        if not body:
            raise Problem(400, "invalid_request", "Provide title or archived")
        if "title" in body and len(body["title"]) > 200:
            raise Problem(400, "invalid_request", "Title is too long")
        result = await b.rest("PATCH", f"/api/sessions/{sid}", body=body | {"profile": s.session_profile(c)})
        s.store.save_conversation(c["id"], c["profile"], sid, c["live_id"], c["owned"], body)
        return web.json_response(s.conversation_view(s.store.get("conversations", c["id"])))
    shape(request[BODY], {})
    if any(r["conversation_id"] == c["id"] and r["state"] not in TERMINAL for r in s.store.runs([c["profile"]])):
        raise Problem(409, "conversation_busy", "Cannot delete an active or uncertain conversation")
    active = (await b.rpc("session.active_list")).get("sessions", [])
    if any(a.get("session_key") == sid and a.get("status") != "idle" for a in active):
        raise Problem(409, "conversation_busy", "Hermes reports live work")
    owned_idle = next((a for a in active if a.get("session_key") == sid), None)
    if owned_idle:
        if not c["owned"] or owned_idle.get("id") != c["live_id"]:
            raise Problem(409, "ownership_conflict", "Cannot close another client session")
        await b.rpc("session.close", {"session_id": c["live_id"]})
    # RPC deletion has a live-process guard; REST alone lacks this guard.
    try:
        await b.rpc("session.delete", {"session_id": sid})
    except Problem as err:
        no_runs = s.store.db.execute("SELECT COUNT(*) FROM runs WHERE conversation_id=?", (c["id"],)).fetchone()[0] == 0
        if not (no_runs and c["owned"] and err.details.get("upstream_code") == 4007):
            raise
    s.store.save_conversation(c["id"], c["profile"], sid, None, c["owned"], {"deleted": True})
    return web.json_response({"deleted": True})


async def resume(request):
    shape(request[BODY], {})
    s = svc(request)
    c = s.conversation(request[AUTH], request.match_info["cid"], "chat.control")
    lock = s.locks.setdefault(c["id"], asyncio.Lock())
    async with lock:
        await s.ensure_live(c, allow_running=True)
    return web.json_response(s.conversation_view(s.store.get("conversations", c["id"])))


async def run_start(request):
    body = shape(request[BODY], {"text": str, "attachment_ids": list}, ("text",))
    if not body["text"].strip() or body["text"].lstrip().startswith("/"):
        raise Problem(400, "invalid_prompt", "Provide nonempty text; slash administration is outside the mobile contract")
    s = svc(request)
    c = s.conversation(request[AUTH], request.match_info["cid"], "chat.control")
    return web.json_response(await s.start_run(c, body["text"], attachment_ids=body.get("attachment_ids", [])), status=202)


async def run_list(request):
    s = svc(request)
    state = request.query.get("state")
    if state and state not in ACTIVE | TERMINAL:
        raise Problem(400, "invalid_state", "Unknown run state")
    rows = s.store.runs(s.profiles(request[AUTH]), [state] if state else None, integer_query(request, "limit", 50, 1, 100), integer_query(request, "offset", 0, 0, 100000))
    return web.json_response({"runs": [s.run_view(r) for r in rows], "cursor": s.store.cursor()})


async def run_detail(request):
    return web.json_response(svc(request).run_view(svc(request).run(request[AUTH], request.match_info["rid"])))


async def run_control(request):
    s = svc(request)
    r = s.run(request[AUTH], request.match_info["rid"], "chat.control")
    action = request.match_info["action"]
    if action not in {"stop", "steer", "retry"}:
        raise Problem(404, "not_found", "Unknown action")
    body = shape(request[BODY], {"text": str} if action == "steer" else {}, ("text",) if action == "steer" else ())
    if action == "retry":
        if r["state"] not in {"failed", "cancelled"} or not r["data"].get("prompt"):
            raise Problem(409, "retry_unavailable", "Only a failed/cancelled submitted prompt can be retried")
        c = s.conversation(request[AUTH], r["conversation_id"], "chat.control")
        return web.json_response(await s.start_run(c, r["data"]["prompt"], r["id"]), status=202)
    if action == "steer" and not body["text"].strip():
        raise Problem(400, "invalid_request", "Steering text cannot be empty")
    return web.json_response(await s.control(r, action, body.get("text")))


async def event_poll(request):
    s = svc(request)
    rid = request.match_info.get("rid")
    if rid:
        s.run(request[AUTH], rid)
    result = s.store.replay(request.query.get("after"), s.profiles(request[AUTH]), rid, integer_query(request, "limit", 500, 1, 500))
    return web.json_response(result)


async def event_stream(request):
    s = svc(request)
    cursor = request.query.get("after") or request.headers.get("Last-Event-ID") or s.store.cursor()
    # Validate before committing the streaming HTTP status.
    s.store.replay(cursor, s.profiles(request[AUTH]))
    response = web.StreamResponse(headers={"Content-Type": "text/event-stream", "Cache-Control": "no-cache", "X-Accel-Buffering": "no"})
    await response.prepare(request)
    try:
        while True:
            auth = s.store.auth(request.headers["Authorization"][7:])
            try:
                async with s.changed:
                    page = s.store.replay(cursor, s.profiles(auth))
                    if not page["events"] and not page["has_more"]:
                        # Lock prevents a notify between the query and wait.
                        try:
                            await asyncio.wait_for(s.changed.wait(), 10)
                        except asyncio.TimeoutError:
                            pass
                for event in page["events"]:
                    await response.write(f"id: {event['cursor']}\nevent: {event['type']}\ndata: {json.dumps(event, separators=(',', ':'))}\n\n".encode())
                cursor = page["cursor"]
                await response.write(f"event: stream.checkpoint\ndata: {json.dumps({'cursor': cursor})}\n\n".encode())
            except Problem as err:
                await response.write(f"event: stream.resync_required\ndata: {json.dumps(err.body())}\n\n".encode())
                break
    except (ConnectionError, asyncio.CancelledError, Problem):
        pass
    return response


async def attention(request):
    s = svc(request)
    items = []
    for row in s.store.db.execute("SELECT data FROM attention ORDER BY rowid DESC LIMIT 200").fetchall():
        item = json.loads(row[0])
        if item["profile"] in s.profiles(request[AUTH]):
            if item["state"] == "pending" and item["expires_at"] < now():
                await s.invalidate_attention(item["run_id"], "expired")
                item = s.store.get("attention", item["id"])["data"]
            items.append(s.attention_view(item))
    return web.json_response({"items": items})


async def attention_respond(request):
    s = svc(request)
    aid = identifier(request.match_info["aid"])
    async with s.locks.setdefault("attention." + aid, asyncio.Lock()):
        return await _attention_respond(request)


async def _attention_respond(request):
    s = svc(request)
    item = s.store.get("attention", identifier(request.match_info["aid"]))["data"]
    b = s.require(request[AUTH], item["profile"], "approvals.respond")
    body = shape(request[BODY], {"answer": str, "choice": str})
    if not item["can_respond"] or item["kind"] != "clarification":
        raise Problem(409, "exact_target_unavailable", "Remote dangerous approval is disabled; Hermes resolves a FIFO without exact IDs", limitation=item["limitation"])
    if item["state"] != "pending" or now() >= item["expires_at"] or b.generation != item["generation"] or not b.connected:
        raise Problem(409, "stale_attention", "Prompt is expired or its connection changed")
    if "answer" not in body or "choice" in body:
        raise Problem(400, "invalid_request", "Clarification requires answer")
    run = s.run(request[AUTH], item["run_id"])
    if run["state"] != "waiting_for_input":
        raise Problem(409, "stale_attention", "Run is no longer waiting")
    if item.get("question_id"):
        conv = s.store.get("conversations", run["conversation_id"])
        if conv["data"].get("canonical"):
            conv = await s.refresh_bot_binding(conv, control=True)
        snapshot = await b.rpc("session.resume", {"session_id": conv["stored_id"], "profile": s.session_profile(conv), "omit_messages": True, "close_on_disconnect": False})
        pending = next((r for r in snapshot.get("open_requests", []) if r.get("id") == item["request_id"]), None)
        if snapshot.get("session_id") != run["live_id"] or (pending and item["question_id"] in (pending.get("params", {}).get("answers") or {})):
            raise Problem(409, "stale_attention", "This question has already been answered or the run changed")
        result = await b.rpc("clarify.lock", {"request_id": item["request_id"], "question_id": item["question_id"], "answer": body["answer"]})
        if result.get("status") != "ok":
            raise Problem(409, "stale_attention", "Hermes no longer has this question open")
        remaining = result.get("remaining", [])
    else:
        await b.rpc("clarify.respond", {"session_id": run["live_id"], "request_id": item["request_id"], "answer": body["answer"]})
        remaining = []
    item.update(state="responded", can_respond=False)
    s.store.db.execute("UPDATE attention SET data=? WHERE id=?", (json.dumps(item), item["id"]))
    s.store.db.commit()
    latest = s.store.get("runs", run["id"])
    if latest["state"] not in TERMINAL and not latest["data"].get("stop_intent"):
        s.store.update_run(run["id"], "waiting_for_input" if remaining else "running")
    await s.emit(item["profile"], "approval.resolved", {"id": item["id"], "state": "responded", "kind": "clarification"}, run)
    return web.json_response({"acknowledged": True})


async def profiles(request):
    s = svc(request)
    async def one(p):
        b = s.backends[p]
        try:
            model = await b.rest("GET", "/api/model/info", query={"profile": p})
        except Problem:
            model = {}
        try:
            roster = await b.rest("GET", "/api/profiles")
            metadata = next((x for x in roster.get("profiles", []) if x.get("name") == p), {})
        except Problem:
            metadata = {}
        active = [s.run_view(r) for r in s.store.runs([p]) if r["state"] not in TERMINAL]
        return {"id": p, "name": p, **only(metadata, "description skill_count is_default gateway_running"), "health": b.health(), "model": model.get("model"), "provider": model.get("provider"), "model_capabilities": model.get("capabilities", {}), "activity": active, "backend_activity": await s.activity(p) if b.connected else [], "activity_coverage": "bridge_owned_plus_this_backend_observations", "sessions_url": PREFIX + "/conversations?profile=" + p}
    return web.json_response({"profiles": await asyncio.gather(*(one(p) for p in s.profiles(request[AUTH])))})


async def profile_detail(request):
    s = svc(request)
    p = identifier(request.match_info["pid"])
    b = s.require(request[AUTH], p)
    model, roster, soul = await asyncio.gather(b.rest("GET", "/api/model/info", query={"profile": p}), b.rest("GET", "/api/profiles"), b.rest("GET", f"/api/profiles/{p}/soul"))
    metadata = next((x for x in roster.get("profiles", []) if x.get("name") == p), {})
    return web.json_response({"id": p, **only(metadata, "name description skill_count is_default gateway_running"), "model": only(model, "model provider effective_context_length capabilities"), "soul": only(soul, "exists content"), "health": b.health(), "sessions_url": PREFIX + "/conversations?profile=" + p})


async def inventory(request):
    p, b = profile(request)
    resource = request.match_info["resource"]
    paths = {"skills": "/api/skills", "tools": "/api/tools/toolsets", "mcp": "/api/mcp/servers", "models": "/api/model/options", "usage": "/api/analytics/usage", "host": "/api/system/stats", "memory": "/api/memory"}
    if resource not in paths:
        raise Problem(404, "not_found", "Unknown inventory resource")
    query = {"profile": p}
    if resource == "usage":
        query["days"] = integer_query(request, "days", 30, 1, 365)
    raw = await b.rest("GET", paths[resource], query=query)
    if resource == "skills":
        out = {"skills": [only(x, "name description category enabled source tags") for x in raw]}
    elif resource == "tools":
        out = {"toolsets": [only(x, "name label description enabled available configured tools") for x in raw], "scope": "configured_cli_defaults"}
    elif resource == "mcp":
        out = {"servers": [only(x, "name enabled configured connected status tool_count transport") for x in raw.get("servers", [])], "scope": "configured_not_health_probed"}
    elif resource == "models":
        out = {"providers": []}
        # Explicit metadata only. Never send provider keys/base URLs/config.
        for x in raw.get("providers", []):
            item = only(x, "id name label available configured default_model slug authenticated")
            item["id"] = x.get("slug") or x.get("id")
            item["model_capabilities"] = {model: only(caps, "fast reasoning") for model, caps in x.get("capabilities", {}).items()}
            item["models"] = [only(m, "id name label context_length context_window supports_vision supports_reasoning supports_tools reasoning") if isinstance(m, dict) else {"id": m} for m in x.get("models", [])]
            out["providers"].append(item)
    elif resource == "usage":
        out = only(raw, "daily by_model totals period_days skills") | {"source": "hermes_analytics", "cost_source": "hermes_reported_or_estimated"}
    elif resource == "memory":
        out = {"active": raw.get("active"), "providers": [only(x, "name description configured") for x in raw.get("providers", [])], "builtin_files": raw.get("builtin_files", {}), "contents_available": False}
    else:
        out = host_info(raw)
    return web.json_response({"profile": p, **out})


async def conversation_usage(request):
    s = svc(request)
    c = s.conversation(request[AUTH], request.match_info["cid"])
    if not c["live_id"] or not c["owned"]:
        raise Problem(409, "live_usage_unavailable", "Use persisted profile analytics for this conversation")
    raw = await s.backends[c["profile"]].rpc("session.usage", {"session_id": c["live_id"]})
    return web.json_response(usage(raw.get("usage", raw)))


async def cron_jobs(request):
    s = svc(request)
    p, b = profile(request, "read" if request.method == "GET" else "tasks.manage")
    if request.method == "GET":
        rows = await b.rest("GET", "/api/cron/jobs", query={"profile": p})
        return web.json_response({"jobs": [cron(row, p) for row in rows]})
    body = shape(request[BODY], {"prompt": str, "schedule": str, "name": str, "deliver": str, "skills": list}, ("prompt", "schedule"))
    row = await b.rest("POST", "/api/cron/jobs", body, {"profile": p})
    return web.json_response(cron(row, p), status=201)


async def cron_detail(request):
    s = svc(request)
    p, jid = unopaque(request.match_info["jid"])
    b = s.require(request[AUTH], p, "read" if request.method == "GET" else "tasks.manage")
    path = "/api/cron/jobs/" + jid
    if request.method == "GET":
        row, recent = await asyncio.gather(b.rest("GET", path, query={"profile": p}), b.rest("GET", path + "/runs", query={"profile": p}))
        return web.json_response({"job": cron(row, p), "recent_conversations": [s.observe_conversation(p, r) for r in recent.get("runs", [])], "execution_evidence": "cron_session_and_job_last_status"})
    body = request[BODY]
    if request.method == "PATCH":
        shape(body, {"prompt": str, "schedule": str, "name": str, "skills": list, "model": str, "provider": str, "enabled": bool})
        if "enabled" in body:
            raise Problem(400, "use_enable_action", "Use enable/disable actions so Hermes updates scheduling state")
        row = await b.rest("PUT", path, {"updates": body}, {"profile": p})
        return web.json_response(cron(row, p))
    shape(body, {})
    if request.method == "DELETE":
        await b.rest("DELETE", path, query={"profile": p})
        return web.json_response({"deleted": True})
    action = request.match_info["action"]
    mapped = {"enable": "resume", "disable": "pause", "run-now": "trigger"}
    if action not in mapped:
        raise Problem(404, "not_found", "Unknown scheduled job action")
    row = await b.rest("POST", path + "/" + mapped[action], query={"profile": p})
    return web.json_response({"job": cron(row, p), "acknowledged": True, "execution_started": False if action == "run-now" else None, "scheduler_required": action == "run-now"})


def board(request, scope="read"):
    p, b = profile(request, scope)
    slug = request.query.get("board", "default")
    if slug not in b.cfg["boards"]:
        raise Problem(403, "board_forbidden", "Board is not configured for this profile")
    return p, b, slug


def task_row(service, raw, source, slug):
    row = task(raw, source, slug)
    assigned = raw.get('assignee')
    if assigned and assigned not in service.backends and service.backends[source].cfg.get('bot_mode_roster'):
        row['assignee'] = opaque(source, assigned)
    return row


async def task_assignee(service, auth, source, value):
    if value in service.backends:
        service.require(auth, value, 'tasks.manage')
        return value
    actual, name, _, _ = await BotMode(service, auth).resolve(value)
    if actual != source:
        raise Problem(403, 'profile_forbidden', 'Assign a native Agent from this board host')
    service.require(auth, actual, 'tasks.manage')
    return name


async def kanban_list(request):
    s = svc(request)
    p, b, slug = board(request, "read" if request.method == "GET" else "tasks.manage")
    if request.method == "GET":
        raw, workers = await asyncio.gather(b.rest("GET", "/api/plugins/kanban/board", query={"board": slug}), b.rest("GET", "/api/plugins/kanban/workers/active", query={"board": slug}))
        rows = [r for col in raw.get("columns", []) for r in col.get("tasks", [])]
        return web.json_response({"board": slug, "tasks": [task_row(s, r, p, slug) | {"supported_targets": task_targets(r)} | only(r, "progress link_counts comment_count diagnostics warnings") for r in rows], "workers": [only(w, "run_id task_title profile started_at last_heartbeat_at max_runtime_seconds") | {"status": w.get("task_status", w.get("status")), "assignee": w.get("task_assignee", w.get("assignee"))} | {"task_id": opaque(p, slug + "." + w["task_id"]) if w.get("task_id") else None} for w in workers.get("workers", [])], "workers_checked_at": workers.get("checked_at")})
    body = shape(request[BODY], {"title": str, "body": str, "assignee": str, "priority": int, "parents": list, "triage": bool, "skills": list, "max_runtime_seconds": int, "workspace": str}, ("title",))
    workspace(s, p, body)
    if body.get("assignee"):
        body["assignee"] = await task_assignee(s, request[AUTH], p, body["assignee"])
    payload = {k: v for k, v in body.items() if k != "workspace"}
    if payload.get("parents"):
        normalized = []
        for parent in payload["parents"]:
            parent_profile, parent_compound = unopaque(parent)
            if "." not in parent_compound:
                raise Problem(400, "invalid_id", "Invalid dependency task")
            parent_board, parent_id = parent_compound.rsplit(".", 1)
            if (parent_profile, parent_board) != (p, slug):
                raise Problem(400, "invalid_dependency", "Dependencies must belong to the same configured board/profile")
            normalized.append(parent_id)
        payload["parents"] = normalized
    if body.get("workspace"):
        payload.update(workspace_kind="dir", workspace_path=b.cfg["workspaces"][body["workspace"]])
    raw = await b.rest("POST", "/api/plugins/kanban/tasks", payload, {"board": slug})
    row = raw.get("task", raw)
    return web.json_response(task_row(s, row, p, slug), status=201)


def task_targets(row):
    # Source guards: block ready; complete ready/blocked; schedule todo/ready/blocked.
    # Running changes require reclaim; ready still depends on canonical dependencies.
    state = row.get("status")
    if state == "running":
        return []
    targets = ["triage", "todo", "ready", "archived"]
    if state in {"todo", "ready", "blocked"}:
        targets.append("scheduled")
    if state == "ready":
        targets.append("blocked")
    if state in {"ready", "blocked", "review"}:
        targets.append("done")
    return [x for x in targets if x != state]


async def kanban_detail(request):
    s = svc(request)
    p, compound = unopaque(request.match_info["tid"])
    if "." not in compound:
        raise Problem(400, "invalid_id", "Invalid task ID")
    slug, tid = compound.rsplit(".", 1)
    b = s.require(request[AUTH], p, "read" if request.method == "GET" else "tasks.manage")
    if slug not in b.cfg["boards"]:
        raise Problem(403, "board_forbidden", "Board is not configured")
    path = "/api/plugins/kanban/tasks/" + identifier(tid)
    if request.method == "GET":
        raw = await b.rest("GET", path, query={"board": slug})
        return web.json_response({"task": task_row(s, raw["task"], p, slug), "links": {kind: [opaque(p, slug + "." + str(x)) for x in raw.get("links", {}).get(kind, [])] for kind in ("parents", "children")}, "diagnostics": raw["task"].get("diagnostics", []), "comments": [only(x, "id author body created_at") for x in raw.get("comments", [])], "attempts": [only(x, "id task_id profile status started_at ended_at outcome summary error last_heartbeat_at max_runtime_seconds") for x in raw.get("runs", [])], "attachments": [only(x, "id filename content_type size created_at") for x in raw.get("attachments", [])], "recent_activity": [only(x, "id kind created_at run_id") | {"details": only(x.get("payload") or {}, "status from to reason summary assignee")} for x in raw.get("events", [])], "supported_targets": task_targets(raw["task"]), "artifact_downloads": "kanban task-scoped endpoint"})
    if request.method == "PATCH":
        current = await b.rest("GET", path, query={"board": slug})
        if current["task"].get("status") == "running" and request[BODY].get("status"):
            raise Problem(409, "use_reclaim_action", "Use the reclaim action to stop a running worker safely")
        body = shape(request[BODY], {"status": str, "assignee": str, "priority": int, "title": str, "body": str, "result": str, "block_reason": str, "summary": str})
        if body.get("status") not in {None, "triage", "todo", "scheduled", "ready", "blocked", "done", "archived"}:
            raise Problem(400, "invalid_state", "Use an existing Hermes task state")
        if "assignee" in body and len(body) != 1:
            raise Problem(400, "separate_assignment", "Change assignment separately; upstream compound updates are not atomic")
        if body.get("assignee"):
            body["assignee"] = await task_assignee(s, request[AUTH], p, body["assignee"])
        # Hermes preserves a completion summary. Other transitions ignore it;
        # retain the note as an existing canonical comment before the transition.
        # This is not atomic; the command receipt forbids replay if interrupted.
        if body.get("summary") and body.get("status") != "done":
            await b.rest("POST", path + "/comments", {"body": body.pop("summary"), "author": "Talaria"}, {"board": slug})
        raw = await b.rest("PATCH", path, body, {"board": slug})
        return web.json_response({"acknowledged": True, "task_id": request.match_info["tid"], "refresh_required": True})
    shape(request[BODY], {})
    await b.rest("DELETE", path, query={"board": slug})
    return web.json_response({"deleted": True})


async def kanban_action(request):
    s = svc(request)
    p, compound = unopaque(request.match_info["tid"])
    if "." not in compound:
        raise Problem(400, "invalid_id", "Invalid task ID")
    slug, tid = compound.rsplit(".", 1)
    b = s.require(request[AUTH], p, "tasks.manage")
    if slug not in b.cfg["boards"]:
        raise Problem(403, "board_forbidden", "Board is not configured")
    action = request.match_info["action"]
    if action == "reclaim":
        body = shape(request[BODY], {"reason": str})
    elif action == "reassign":
        body = shape(request[BODY], {"profile": str, "reclaim_first": bool, "reason": str}, ("profile",))
        if body["profile"]:
            s.require(request[AUTH], body["profile"], "tasks.manage")
    else:
        raise Problem(404, "not_found", "Unknown task action")
    await b.rest("POST", f"/api/plugins/kanban/tasks/{identifier(tid)}/{action}", body, {"board": slug})
    return web.json_response({"acknowledged": True, "task_id": request.match_info["tid"], "refresh_required": True})


async def attachment_upload(request):
    s = svc(request)
    body = shape(request[BODY], {"conversation_id": str, "name": str, "content_type": str, "content_base64": str}, ("conversation_id", "name", "content_type", "content_base64"))
    c = s.conversation(request[AUTH], body["conversation_id"], "chat.control")
    if c["data"].get("canonical"):
        await s.refresh_bot_binding(c, control=True)
    return web.json_response(s.uploads.stage(c, body), status=201)


async def artifact_list(request):
    s = svc(request)
    c = s.conversation(request[AUTH], request.match_info["cid"])
    rows = s.store.db.execute("SELECT data FROM artifacts WHERE conversation_id=?", (c["id"],)).fetchall()
    return web.json_response({"artifacts": [s.artifact_view(json.loads(r[0])) for r in rows]})


async def artifact_download(request):
    s = svc(request)
    item = s.store.get("artifacts", identifier(request.match_info["aid"]))["data"]
    s.require(request[AUTH], item["profile"])
    if request.match_info.get("download") is None:
        return web.json_response(s.artifact_view(item))
    f, st = s.artifact_open(item["profile"], item["path"])
    if (st.st_dev, st.st_ino, st.st_size, st.st_mtime_ns) != (item["device"], item["inode"], item["size"], item["mtime_ns"]):
        f.close()
        raise Problem(409, "artifact_changed", "Artifact identity or size changed after registration")
    # Serve the already validated descriptor; FileResponse would reopen a path.
    response = web.StreamResponse(headers={"Content-Type": "application/octet-stream", "Content-Length": str(st.st_size), "Content-Disposition": "attachment", "X-Content-Type-Options": "nosniff"})
    try:
        await response.prepare(request)
        while chunk := f.read(65536):
            await response.write(chunk)
    finally:
        f.close()
    return response


async def kanban_attachment(request):
    s = svc(request)
    p, compound = unopaque(request.match_info["tid"])
    if "." not in compound:
        raise Problem(400, "invalid_id", "Invalid task ID")
    slug, tid = compound.rsplit(".", 1)
    b = s.require(request[AUTH], p)
    if slug not in b.cfg["boards"]:
        raise Problem(403, "board_forbidden", "Board is not configured")
    aid = integer_query(request, "id", 0, 1, 2**63 - 1)
    raw = await b.rest("GET", f"/api/plugins/kanban/tasks/{identifier(tid)}", query={"board": slug})
    entry = next((x for x in raw.get("attachments", []) if x.get("id") == aid), None)
    if not entry:
        raise Problem(404, "not_found", "Attachment does not belong to this task")
    try:
        async with b.http.get(b.cfg["url"].rstrip("/") + f"/api/plugins/kanban/attachments/{aid}", params={"board": slug}, allow_redirects=False) as upstream:
            if upstream.status != 200 or int(entry["size"]) > s.cfg["artifact_limit"]:
                raise Problem(502, "artifact_unavailable", "Hermes attachment unavailable or oversized")
            response = web.StreamResponse(headers={"Content-Type": "application/octet-stream", "Content-Disposition": "attachment", "X-Content-Type-Options": "nosniff"})
            await response.prepare(request)
            size = 0
            async for chunk in upstream.content.iter_chunked(65536):
                size += len(chunk)
                if size > s.cfg["artifact_limit"]:
                    break
                await response.write(chunk)
            return response
    except (ConnectionError, asyncio.TimeoutError):
        raise Problem(503, "artifact_unavailable", "Attachment transfer failed") from None


async def home(request):
    s = svc(request)
    profiles_allowed = s.profiles(request[AUTH])
    snapshot_cursor = s.store.cursor()
    coverage_errors = []
    jobs, cards, hosts, activity = [], [], [], []
    async def gather_one(p):
        b = s.backends[p]
        async def read(path, query):
            try:
                return await asyncio.wait_for(b.rest("GET", path, query=query), 4)
            except asyncio.TimeoutError:
                coverage_errors.append({"profile": p, "resource": path, "error": "upstream_timeout"})
                return None
            except Problem as err:
                coverage_errors.append({"profile": p, "resource": path, "error": err.code})
                return None
        status, cronrows, host = await asyncio.gather(read("/api/status", {"profile": p}), read("/api/cron/jobs", {"profile": p}), read("/api/system/stats", {}))
        if cronrows:
            jobs.extend(cron(r, p) for r in cronrows)
        hosts.append({"profile": p, "connection": b.health(), "hermes": only(status or {}, "version hermes_version gateway_running gateway_state gateway_exit_reason"), "host": host_info(host or {})})
        try:
            activity.extend(await asyncio.wait_for(s.activity(p), 4))
        except (Problem, asyncio.TimeoutError):
            coverage_errors.append({"profile": p, "resource": "desktop_activity", "error": "unavailable"})
        for slug in b.cfg["boards"]:
            raw = await read("/api/plugins/kanban/board", {"board": slug})
            if raw:
                cards.extend(task(r, p, slug) for col in raw.get("columns", []) for r in col.get("tasks", []))
    await asyncio.gather(*(gather_one(p) for p in profiles_allowed))
    runs = [s.run_view(r) for r in [*s.store.runs(profiles_allowed, ACTIVE, limit=200), *s.store.runs(profiles_allowed, TERMINAL, limit=20)]]
    items = json.loads((await attention(request)).text)["items"]
    return web.json_response({"bridge": {"version": __version__, "uptime_seconds": now() - s.started}, "studios": hosts, "backend_activity": activity, "active_runs": [r for r in runs if r["state"] not in TERMINAL], "attention": [a for a in items if a["state"] == "pending"], "failed_or_blocked": [r for r in runs if r["state"] in {"failed", "unknown"}] + [t for t in cards if t["raw_state"] == "blocked"] + [j for j in jobs if j.get("last_status") == "error"], "recent_completions": [r for r in runs if r["state"] in TERMINAL][:20] + [t for t in cards if t["raw_state"] == "done"][:20], "recent_scheduled_results": [j for j in jobs if j.get("last_run_at")][:20], "upcoming_jobs": sorted([j for j in jobs if j.get("enabled") and j.get("next_run_at")], key=lambda j: str(j["next_run_at"]))[:20], "kanban": cards, "coverage_errors": coverage_errors, "snapshot_cursor": snapshot_cursor, "observed_at": now(), "coverage": "Bridge-owned runs plus canonical configured-profile cron and Kanban; not all Studio processes"})


def create_app(cfg):
    s = Service(cfg)
    app = web.Application(middlewares=[contract], client_max_size=cfg["upload_limit"] * 2 + 4096)
    app[SERVICE] = s
    routes = [
        web.get(PREFIX + "/bots/inventory", bot_inventory), web.post(PREFIX + "/bots", bot_create), web.patch(PREFIX + "/bots/{bid}", bot_update), web.post(PREFIX + "/bots/{bid}/hide", bot_hide), web.post(PREFIX + "/bots/{bid}/duplicate", bot_duplicate), web.get(PREFIX + "/bots", bots), web.get(PREFIX + "/bots/{bid}", bot_detail), web.get(PREFIX + "/bots/{bid}/conversation", bot_conversation), web.post(PREFIX + "/bots/{bid}/conversations", bot_threads), web.post(PREFIX + "/bots/{bid}/conversation", bot_conversation),
        web.get(PREFIX + "/capabilities", capabilities), web.get(PREFIX + "/home", home), web.get(PREFIX + "/profiles", profiles), web.get(PREFIX + "/profiles/{pid}", profile_detail),
        web.get(PREFIX + "/conversations", conversations), web.post(PREFIX + "/conversations", conversations),
        web.get(PREFIX + "/conversations/{cid}", conversation_detail), web.patch(PREFIX + "/conversations/{cid}", conversation_detail), web.delete(PREFIX + "/conversations/{cid}", conversation_detail),
        web.post(PREFIX + "/conversations/{cid}/resume", resume), web.post(PREFIX + "/conversations/{cid}/runs", run_start), web.get(PREFIX + "/conversations/{cid}/usage", conversation_usage),
        web.get(PREFIX + "/runs", run_list), web.get(PREFIX + "/runs/{rid}", run_detail), web.post(PREFIX + "/runs/{rid}/{action}", run_control), web.get(PREFIX + "/runs/{rid}/events", event_poll),
        web.get(PREFIX + "/events", event_poll), web.get(PREFIX + "/events/stream", event_stream), web.get(PREFIX + "/attention", attention), web.post(PREFIX + "/attention/{aid}/respond", attention_respond),
        web.get(PREFIX + "/inventory/{resource}", inventory), web.get(PREFIX + "/cron", cron_jobs), web.post(PREFIX + "/cron", cron_jobs),
        web.get(PREFIX + "/cron/{jid}", cron_detail), web.patch(PREFIX + "/cron/{jid}", cron_detail), web.delete(PREFIX + "/cron/{jid}", cron_detail), web.post(PREFIX + "/cron/{jid}/{action}", cron_detail),
        web.get(PREFIX + "/kanban/tasks", kanban_list), web.post(PREFIX + "/kanban/tasks", kanban_list), web.get(PREFIX + "/kanban/tasks/{tid}", kanban_detail), web.patch(PREFIX + "/kanban/tasks/{tid}", kanban_detail), web.delete(PREFIX + "/kanban/tasks/{tid}", kanban_detail), web.get(PREFIX + "/kanban/tasks/{tid}/attachment", kanban_attachment), web.post(PREFIX + "/kanban/tasks/{tid}/{action}", kanban_action),
        web.get(PREFIX + "/commands/{cid}", command_status), web.post(PREFIX + "/captures", capture_save), web.post(PREFIX + "/captures/uploads", capture_upload), web.post(PREFIX + "/attachments", attachment_upload), web.get(PREFIX + "/conversations/{cid}/artifacts", artifact_list), web.get(PREFIX + "/artifacts/{aid}", artifact_download), web.get(PREFIX + "/artifacts/{aid}/{download:download}", artifact_download),
    ]
    app.add_routes(routes)
    async def lifecycle(app):
        await s.start()
        try:
            yield
        finally:
            await s.close()
    app.cleanup_ctx.append(lifecycle)
    return app
