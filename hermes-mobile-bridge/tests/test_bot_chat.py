"""Writable canonical Bot Chat lifecycle regression coverage."""
import asyncio
import json
import uuid

import aiohttp
import pytest

from hermes_mobile_bridge.core import opaque
from conftest import eventually
from test_bots import studio_rows


pytestmark = pytest.mark.asyncio

AUDITED_COMMIT = "4bb9e57bfde8a0affb5553eff13ed6e1f14147f1"
BOT_PROFILE = "research-orchestrator"


def prepare_bot(h, *, canonical=False, control=True):
    h.fake.bot_roster = studio_rows()
    bot = next(row for row in h.fake.bot_roster if row["name"] == BOT_PROFILE)
    if not canonical:
        for row in h.fake.bot_roster:
            row["canonical_session"] = None
    backend = h.service.backends["default"]
    backend.cfg["bot_mode_roster"] = True
    backend.cfg["bot_chat_control"] = control
    backend.bot_mode_supported = True
    return bot, opaque("default", BOT_PROFILE)


def add_existing_chat(h, bot, *, root="desktop-root", tip="desktop-tip", runtime="desktop-runtime", messages=None):
    bot["canonical_session"] = {
        "id": root,
        "resolved_id": tip,
        "title": "Bot Chat",
        "last_active": 10,
    }
    h.fake.sessions[runtime] = {
        "stored": tip,
        "status": "idle",
        "title": "Bot Chat",
        "profile": BOT_PROFILE,
        "hidden": True,
        "follow_profile_config": True,
        "messages": messages or [],
    }
    return tip


def rpc_requests(h, method):
    return [params for called, params in h.fake.requests if called == method]


async def test_absent_bot_chat_is_hidden_adoptable_and_has_no_intro(harness):
    h = harness
    _, bid = prepare_bot(h)

    opened = await h.request("POST", f"/bots/{bid}/conversation", {})
    conv = opened["conversation"]
    creates = rpc_requests(h, "session.create")

    assert len(creates) == 1
    assert creates[0]["profile"] == BOT_PROFILE
    assert creates[0]["title"] == "Bot Chat"
    assert creates[0]["hidden"] is True
    assert creates[0]["follow_profile_config"] is True
    assert creates[0]["idempotency_key"] == f"mobile-botchat-{bid}"
    runtime_id = h.service.store.get("conversations", conv["id"])["live_id"]
    assert h.fake.sessions[runtime_id]["hidden"] is True
    assert h.fake.sessions[runtime_id]["follow_profile_config"] is True
    assert rpc_requests(h, "session.title") == [{"session_id": runtime_id, "title": "Bot Chat"}]
    assert h.fake.prompts == 0
    assert "prompt.submit" not in h.fake.methods

    # Reopening adopts the source row and reuses its stable identity key.
    reopened = await h.request("POST", f"/bots/{bid}/conversation", {})
    assert reopened["conversation"]["id"] == conv["id"]
    assert len(rpc_requests(h, "session.create")) == 1


async def test_existing_desktop_bot_chat_is_adopted_without_minting(harness):
    h = harness
    bot, bid = prepare_bot(h, canonical=True)
    tip = add_existing_chat(h, bot, messages=[{"id": "m1", "role": "user", "content": "Existing history"}])

    opened = await h.request("POST", f"/bots/{bid}/conversation", {})

    assert opened["conversation"]["id"] == "botchat." + bid
    assert opened["messages"][0]["content"] == "Existing history"
    assert not rpc_requests(h, "session.create")
    assert not rpc_requests(h, "session.title")
    assert rpc_requests(h, "session.list")[0] == {
        "profile": BOT_PROFILE,
        "title": "Bot Chat",
        "include_hidden": True,
    }
    resume = rpc_requests(h, "session.resume")
    assert resume and all(row["profile"] == BOT_PROFILE for row in resume)
    assert any(row["session_id"] == tip for row in resume)


async def test_concurrent_bot_chat_initialization_creates_one_session(harness):
    h = harness
    _, bid = prepare_bot(h)

    left, right = await asyncio.gather(
        h.request("POST", f"/bots/{bid}/conversation", {}),
        h.request("POST", f"/bots/{bid}/conversation", {}),
    )

    assert left["conversation"]["id"] == right["conversation"]["id"]
    assert len(rpc_requests(h, "session.create")) == 1
    assert len(h.fake.sessions) == 1
    assert h.fake.prompts == 0


async def test_lookup_failure_and_positive_roster_mismatch_never_mint(harness):
    h = harness
    bot, bid = prepare_bot(h)
    h.fake.fail_registry = True

    await h.request("POST", f"/bots/{bid}/conversation", {}, expected=502)
    assert not rpc_requests(h, "session.create")
    assert all(row["profile"] == BOT_PROFILE for row in rpc_requests(h, "session.list"))

    h.fake.fail_registry = False
    add_existing_chat(h, bot)
    h.fake.wrong_profile = True
    await h.request("POST", f"/bots/{bid}/conversation", {}, expected=502)
    assert not rpc_requests(h, "session.create")
    assert not rpc_requests(h, "prompt.submit")
    assert all(row.get("profile") == BOT_PROFILE for row in rpc_requests(h, "session.resume"))


async def test_title_persistence_failure_fails_closed_and_retry_reuses_key(harness):
    h = harness
    _, bid = prepare_bot(h)
    h.fake.fail_title = True

    await h.request("POST", f"/bots/{bid}/conversation", {}, expected=502)
    first_create = rpc_requests(h, "session.create")[0]
    assert first_create["hidden"] is True and first_create["follow_profile_config"] is True
    assert not rpc_requests(h, "prompt.submit")

    h.fake.fail_title = False
    opened = await h.request("POST", f"/bots/{bid}/conversation", {})
    assert opened["conversation"]["id"] == "botchat." + bid
    creates = rpc_requests(h, "session.create")
    assert len(creates) == 2
    assert creates[0]["idempotency_key"] == creates[1]["idempotency_key"] == f"mobile-botchat-{bid}"
    assert len(h.fake.sessions) == 1
    assert h.fake.prompts == 0


async def test_native_profile_send_and_main_list_share_one_conversation(harness):
    h = harness
    _, bid = prepare_bot(h)
    opened = await h.request("POST", f"/bots/{bid}/conversation", {})
    cid = opened["conversation"]["id"]

    run = await h.request("POST", f"/conversations/{cid}/runs", {"text": "Use this bot's configured context"}, expected=202)
    submit = rpc_requests(h, "prompt.submit")[-1]
    assert submit["profile"] == BOT_PROFILE
    assert submit["text"] == "Use this bot's configured context"
    assert "model" not in submit and "provider" not in submit
    assert run["profile"] == bid
    assert h.service.store.get("runs", run["id"])["profile"] == "default"

    bot_chat = await h.request("GET", f"/bots/{bid}/conversation")
    all_chats = await h.request("GET", "/conversations?profile=default")
    assert bot_chat["conversation"]["id"] == cid
    assert [row["id"] for row in all_chats["conversations"]].count(cid) == 1
    stored_conv = h.service.store.get("conversations", cid)
    assert not any(row["id"] == opaque("default", stored_conv["stored_id"]) for row in all_chats["conversations"])


async def test_hidden_or_removed_bot_becomes_inaccessible_without_deleting_history(harness):
    h = harness
    bot, bid = prepare_bot(h)
    opened = await h.request("POST", f"/bots/{bid}/conversation", {})
    sid = h.service.store.get("conversations", opened["conversation"]["id"])["live_id"]
    stored = h.fake.sessions[sid]["stored"]
    h.fake.sessions[sid]["messages"] = [{"id": "kept", "role": "user", "content": "Keep this history"}]

    bot["ui_meta"]["hermes-bots"]["hidden"] = True
    await h.request("GET", f"/bots/{bid}/conversation", expected=404)
    bot["ui_meta"]["hermes-bots"]["hidden"] = False
    h.fake.bot_roster.remove(bot)
    await h.request("GET", f"/bots/{bid}/conversation", expected=404)

    assert h.fake.sessions[sid]["stored"] == stored
    assert h.fake.sessions[sid]["messages"][0]["content"] == "Keep this history"
    assert not rpc_requests(h, "session.close")
    assert not rpc_requests(h, "session.delete")


async def test_bot_chat_control_setting_and_token_scope_are_both_required(harness):
    h = harness
    _, bid = prepare_bot(h, control=False)

    await h.request("POST", f"/bots/{bid}/conversation", {}, expected=403)
    assert not rpc_requests(h, "session.create")

    h.service.backends["default"].cfg["bot_chat_control"] = True
    _, read_token = h.service.store.token("reader", ["read"], ["default"])
    async with aiohttp.ClientSession(headers={"Authorization": "Bearer " + read_token}) as reader:
        async with reader.post(
            f"http://127.0.0.1:{h.port}/mobile/v1/bots/{bid}/conversation",
            json={},
            headers={"Idempotency-Key": str(uuid.uuid4())},
        ) as response:
            assert response.status == 403
    assert not rpc_requests(h, "session.create")


async def test_modern_clarify_questions_lock_by_request_and_question_id(harness):
    h = harness
    backend = h.service.backends["default"]
    bot, bid = prepare_bot(h)
    backend.cfg["installed_commit"] = AUDITED_COMMIT
    generation = backend.generation
    await backend.ws.close()
    await eventually(lambda: backend.generation > generation and backend.server_requests_supported and backend.declines_not_shown)
    assert ("client.capabilities", {"server_requests": True}) in h.fake.requests

    opened = await h.request("POST", f"/bots/{bid}/conversation", {})
    cid = opened["conversation"]["id"]
    run = await h.request("POST", f"/conversations/{cid}/runs", {"text": "Ask for two details"}, expected=202)
    sid = h.service.store.get("runs", run["id"])["live_id"]
    await h.fake.emit(sid, "message.start")
    await eventually(lambda: h.service.store.get("runs", run["id"])["state"] == "running")

    request_id = "srq-modern-batch"
    h.fake.questions[request_id] = {"q-1": None, "q-2": None}
    await h.fake.ws.send_json({
        "jsonrpc": "2.0",
        "id": request_id,
        "method": "clarify",
        "params": {
            "session_id": sid,
            "questions": [
                {"qid": "q-1", "question": "Which project?", "choices": ["A", "B"], "multi_select": False},
                {"qid": "q-2", "question": "Which timeframe?", "choices": None, "multi_select": False},
            ],
        },
    })
    await eventually(lambda: h.service.store.db.execute("SELECT COUNT(*) FROM attention WHERE run_id=?", (run["id"],)).fetchone()[0] == 2)

    rows = [json.loads(row[0]) for row in h.service.store.db.execute("SELECT data FROM attention WHERE run_id=?", (run["id"],)).fetchall()]
    by_qid = {row["question_id"]: row for row in rows}
    assert set(by_qid) == {"q-1", "q-2"}
    assert all(row["request_id"] == request_id and row["kind"] == "clarification" for row in rows)
    assert {row["details"]["question"] for row in rows} == {"Which project?", "Which timeframe?"}

    visible = await h.request("GET", "/attention")
    visible_rows = [item for item in visible["items"] if item["run_id"] == run["id"]]
    assert len(visible_rows) == 2 and all(item["can_respond"] for item in visible_rows)
    assert all("question_id" not in item and "request_id" not in item for item in visible_rows)

    await h.request("POST", f"/attention/{by_qid['q-1']['id']}/respond", {"answer": "Project A"})
    assert h.fake.questions[request_id] == {"q-2": None}
    assert h.service.store.get("runs", run["id"])["state"] == "waiting_for_input"
    await h.request("POST", f"/attention/{by_qid['q-2']['id']}/respond", {"answer": "This quarter"})
    assert request_id not in h.fake.questions
    assert h.service.store.get("runs", run["id"])["state"] == "running"
    locks = rpc_requests(h, "clarify.lock")
    assert locks == [
        {"request_id": request_id, "question_id": "q-1", "answer": "Project A"},
        {"request_id": request_id, "question_id": "q-2", "answer": "This quarter"},
    ]
    assert not rpc_requests(h, "clarify.respond")

    # A reconnect/resume snapshot carries still-open modern requests as well.
    snapshot_id = "srq-modern-snapshot"
    h.fake.questions[snapshot_id] = {"q-recovered": None}
    h.fake.sessions[sid]["open_requests"] = [{
        "id": snapshot_id,
        "method": "clarify",
        "params": {
            "session_id": sid,
            "questions": [{"qid": "q-recovered", "question": "Recovered question?", "choices": None}],
        },
    }]
    await h.request("POST", f"/conversations/{cid}/resume", {})
    await eventually(lambda: h.service.store.db.execute(
        "SELECT COUNT(*) FROM attention WHERE run_id=? AND json_extract(data,'$.request_id')=?",
        (run["id"], snapshot_id),
    ).fetchone()[0] == 1)
    recovered = json.loads(h.service.store.db.execute(
        "SELECT data FROM attention WHERE run_id=? AND json_extract(data,'$.request_id')=?",
        (run["id"], snapshot_id),
    ).fetchone()[0])
    assert recovered["question_id"] == "q-recovered"
    await h.request("POST", f"/attention/{recovered['id']}/respond", {"answer": "Recovered answer"})
    assert rpc_requests(h, "clarify.lock")[-1] == {
        "request_id": snapshot_id,
        "question_id": "q-recovered",
        "answer": "Recovered answer",
    }

    # Unsupported requests receive a wire error without blocking the RPC reader or approving anything.
    await h.fake.ws.send_json({
        "jsonrpc": "2.0",
        "id": "srq-approval-unsupported",
        "method": "approval",
        "params": {"session_id": sid, "command": "dangerous"},
    })
    expected_active = [{
        "id": sid,
        "session_key": h.service.store.get("conversations", cid)["stored_id"],
        "status": "working",
    }]
    assert await backend.rpc("session.active_list") == {"sessions": expected_active}
    assert backend.server_requests_supported
    assert h.fake.approval_calls == 0
    assert not rpc_requests(h, "approval.respond")


async def test_inconsistent_canonical_root_and_busy_native_turn_fail_closed(harness):
    h = harness
    bot, bid = prepare_bot(h)
    add_existing_chat(h, bot)
    backend = h.service.backends["default"]
    rpc = backend.rpc
    async def inconsistent(method, params=None):
        if method == "session.list":
            return {"sessions": [{"id": "different-root", "resolved_id": "different-tip", "title": "Bot Chat"}]}
        return await rpc(method, params)
    backend.rpc = inconsistent
    await h.request("POST", f"/bots/{bid}/conversation", {}, expected=502)
    assert not rpc_requests(h, "session.create")
    backend.rpc = rpc
    opened = await h.request("POST", f"/bots/{bid}/conversation", {})
    cid = opened["conversation"]["id"]
    h.fake.sessions["desktop-runtime"]["status"] = "working"
    await h.request("POST", f"/conversations/{cid}/runs", {"text": "Must not queue behind a Desktop turn"}, expected=409)
    assert h.fake.prompts == 0
    assert not h.service.store.runs(["default"])
