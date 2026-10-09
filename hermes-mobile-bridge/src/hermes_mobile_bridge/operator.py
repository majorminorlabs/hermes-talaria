"""Local-only, explicit operator reconciliation. Never resumes or controls Hermes."""
import asyncio
import os
import pwd
from pathlib import Path

import aiohttp

from .core import Problem, identifier
from .store import Store


async def active_sessions(backend):
    """One authenticated read on a separate socket; no ownership or subscriptions."""
    try:
        async with asyncio.timeout(8), aiohttp.ClientSession(timeout=aiohttp.ClientTimeout(total=8), trust_env=False) as http:
            async with http.ws_connect(backend["url"].rstrip("/") + "/api/ws", params={"token": backend["token"]},
                                       max_msg_size=16 * 1024 * 1024) as ws:
                rid = "operator-active-check"
                await ws.send_json({"jsonrpc": "2.0", "id": rid, "method": "session.active_list", "params": {}})
                async for message in ws:
                    if message.type != aiohttp.WSMsgType.TEXT:
                        continue
                    reply = message.json()
                    if reply.get("id") != rid:
                        continue
                    sessions = reply.get("result", {}).get("sessions")
                    if "error" in reply or not isinstance(sessions, list) or any(
                            not isinstance(s, dict) or not isinstance(s.get("id"), str) for s in sessions):
                        break
                    return sessions
    except (aiohttp.ClientError, asyncio.TimeoutError, ValueError, TypeError, AttributeError):
        pass
    # Never include credentials, backend exception text, or a partial inventory.
    raise Problem(503, "reconciliation_unverified", "Cannot verify Hermes active sessions; no run was changed")


async def reconcile_run(cfg, run_id, reason):
    run_id = identifier(run_id)
    reason = reason.strip()
    if not reason or len(reason) > 4096:
        raise Problem(400, "invalid_reason", "Provide a nonempty reconciliation reason of at most 4096 characters")
    journal = Path(cfg["state_dir"]).expanduser() / "bridge.sqlite3"
    if not journal.is_file() or journal.is_symlink():
        raise ValueError("An existing private bridge journal is required")
    # Do not acquire the daemon lock or recover unrelated pending commands.
    store = Store(cfg, lock=False)
    try:
        # Exclude competing bridge writes while checking this exact stored handle
        # and committing its terminal status, attention withdrawals and audit.
        store.db.execute("BEGIN IMMEDIATE")
        run = store.get("runs", run_id)
        if run["state"] not in {"unknown", "uncertain"}:
            raise Problem(409, "reconciliation_unavailable", "Only unknown/uncertain runs may be reconciled")
        sessions = await active_sessions(cfg["backends"][run["profile"]])
        if any(session["id"] == run["live_id"] for session in sessions):
            raise Problem(409, "run_still_live", "Hermes still has this live handle; no run was changed")
        operator = pwd.getpwuid(os.getuid()).pw_name
        result = store.reconcile_run(run, operator, reason)
        store.db.commit()
        return result
    except BaseException:
        store.db.rollback()
        raise
    finally:
        store.close()
