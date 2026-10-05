from pathlib import Path
import asyncio
import base64
import json
import time
import uuid
import aiohttp
import pytest
from hermes_mobile_bridge.core import load_config
from hermes_mobile_bridge.store import Store
from conftest import eventually


async def test_list_imports_preexisting_unowned_session(harness):
    h = harness
    h.fake.sessions['existing'] = {'stored': 'preexisting-history', 'status': 'idle', 'title': 'Existing history', 'messages': []}
    first = await h.request('GET', '/conversations')
    imported = next(c for c in first['conversations'] if c['title'] == 'Existing history')
    assert imported['owned'] is False
    second = await h.request('GET', '/conversations')
    assert next(c for c in second['conversations'] if c['title'] == 'Existing history')['id'] == imported['id']
    assert h.fake.prompts == 0


async def test_auth_scopes_and_revocation(harness):
    h = harness
    async with aiohttp.ClientSession() as client:
        res = await client.get(f'http://127.0.0.1:{h.port}/mobile/v1/home')
        assert res.status == 401
    cid, token = h.service.store.token('readonly', ['read'], ['default'])
    async with aiohttp.ClientSession(headers={'Authorization': 'Bearer ' + token}) as client:
        res = await client.post(f'http://127.0.0.1:{h.port}/mobile/v1/conversations', json={}, headers={'Idempotency-Key': str(uuid.uuid4())})
        assert res.status == 403
        h.service.store.revoke(cid)
        res = await client.get(f'http://127.0.0.1:{h.port}/mobile/v1/capabilities')
        assert res.status == 401


async def test_duplicate_prompt_and_command_conflict(harness):
    h = harness
    c = await h.request('POST', '/conversations', {}, expected=201)
    key, path = str(uuid.uuid4()), f"/conversations/{c['id']}/runs"
    first = await h.request('POST', path, {'text': 'hello'}, key, 202)
    again = await h.request('POST', path, {'text': 'hello'}, key, 202)
    assert first['id'] == again['id'] and h.fake.prompts == 1
    err = await h.request('POST', path, {'text': 'different'}, key, 409)
    assert err['error']['code'] == 'command_conflict'
    again = await h.request('POST', path, {'text': 'hello'}, key, 202)
    assert first['id'] == again['id']


async def test_replay_mobile_disconnect_multiple_consumers(harness):
    h = harness
    c, r, sid = await h.start_run()
    cursor = h.service.store.cursor()
    await h.client.close()
    for kind, data in [('message.delta', {'text': 'Hello'}), ('tool.start', {'tool_id': 'x', 'name': 'read_file'}), ('tool.complete', {'tool_id': 'x', 'name': 'read_file', 'result': {'ok': True}}), ('tool.complete', {'tool_id': 'x', 'name': 'read_file', 'result': {'ok': True}}), ('message.complete', {'text': 'Hello world', 'status': 'complete', 'usage': {'input': 10, 'total': 12}})]:
        await h.fake.emit(sid, kind, data)
    await eventually(lambda: h.service.store.get('runs', r['id'])['state'] == 'complete')
    h.client = aiohttp.ClientSession(headers={'Authorization': 'Bearer ' + h.token})
    path = f"/runs/{r['id']}/events?after={cursor}"
    a, b = await asyncio.gather(h.request('GET', path), h.request('GET', path))
    assert a == b
    seqs = [e['seq'] for e in a['events']]
    assert seqs == sorted(set(seqs))
    assert [e['type'] for e in a['events']].count('tool.completed') == 1
    assert (await h.request('GET', f"/runs/{r['id']}"))['assistant_text'] == 'Hello world'
    assert not (await h.request('GET', f"/runs/{r['id']}/events?after={a['cursor']}"))['events']


async def test_sse_replay(harness):
    h = harness
    _, r, sid = await h.start_run()
    cursor = h.service.store.cursor()
    await h.fake.emit(sid, 'message.delta', {'text': 'Live'})
    await eventually(lambda: h.service.store.get('runs', r['id'])['data']['assistant_text'] == 'Live')
    async with h.client.get(f'http://127.0.0.1:{h.port}/mobile/v1/events/stream?after={cursor}') as res:
        assert res.status == 200
        frame = b''
        while b'\n\n' not in frame:
            frame += await asyncio.wait_for(res.content.readline(), 2)
        assert b'assistant.delta' in frame and b'Live' in frame
    assert h.service.backends['default'].connected


async def test_bridge_restart_recovers_same_run_without_resubmit(harness):
    h = harness
    _, r, sid = await h.start_run()
    cursor = h.service.store.cursor()
    await h.client.close()
    await h.bridge_runner.cleanup()
    await h.start_bridge()
    recovered = await h.request('GET', f"/runs/{r['id']}")
    assert recovered['state'] == 'running' and recovered['coverage_gap']
    assert h.fake.prompts == 1
    await h.fake.emit(sid, 'message.complete', {'text': 'finished', 'status': 'complete'})
    await eventually(lambda: h.service.store.get('runs', r['id'])['state'] == 'complete')
    page = await h.request('GET', f"/runs/{r['id']}/events?after={cursor}")
    assert any(e['type'] == 'run.completed' for e in page['events'])


async def test_hermes_restart_missing_handle_keeps_durable_unknown(harness):
    h = harness
    _, r, sid = await h.start_run()
    await h.fake.ws.close()
    h.fake.sessions.clear()
    await eventually(lambda: h.service.store.get('runs', r['id'])['state'] == 'unknown')
    await eventually(lambda: h.service.backends['default'].generation >= 2)
    view = await h.request('GET', f"/runs/{r['id']}")
    assert view['state'] == 'unknown' and not view['controls']['stop']
    assert h.fake.prompts == 1
    await h.request('POST', f"/runs/{r['id']}/retry", {}, expected=409)


async def test_stop_tool_execution_steering_and_long_run(harness):
    h = harness
    _, r, sid = await h.start_run()
    h.service.store.db.execute('UPDATE runs SET created=? WHERE id=?', (time.time() - 1000, r['id']))
    h.service.store.db.commit()
    await h.fake.emit(sid, 'tool.start', {'tool_id': 'long', 'name': 'terminal'})
    steer = await h.request('POST', f"/runs/{r['id']}/steer", {'text': 'focus on the tests'})
    assert steer['status'] == 'queued' and steer['consumed'] is False
    stopped = await h.request('POST', f"/runs/{r['id']}/stop", {})
    assert stopped['run']['state'] == 'stop_requested' and stopped['termination_confirmed'] is False
    await h.fake.emit(sid, 'tool.complete', {'tool_id': 'long', 'name': 'terminal', 'result': 'stopped'})
    await h.fake.emit(sid, 'message.complete', {'status': 'interrupted', 'text': ''})
    await eventually(lambda: h.service.store.get('runs', r['id'])['state'] == 'cancelled')
    assert (await h.request('GET', f"/runs/{r['id']}"))['controls']['retry']


async def test_stale_fifo_approval_is_never_dispatched(harness):
    h = harness
    _, r, sid = await h.start_run()
    await h.fake.emit(sid, 'approval.request', {'command': 'dangerous command', 'description': 'context', 'pattern_key': 'x', 'allow_permanent': True})
    await eventually(lambda: h.service.store.db.execute('SELECT COUNT(*) FROM attention').fetchone()[0] == 1)
    item = (await h.request('GET', '/attention'))['items'][0]
    assert item['run_id'] == r['id'] and not item['can_respond']
    for choice in ['once', 'deny', 'always']:
        out = await h.request('POST', f"/attention/{item['id']}/respond", {'choice': choice}, expected=409)
        assert out['error']['code'] == 'exact_target_unavailable'
    assert h.fake.approval_calls == 0
    await h.fake.ws.close()
    await eventually(lambda: h.service.backends['default'].generation >= 2)
    await h.request('POST', f"/attention/{item['id']}/respond", {'choice': 'once'}, expected=409)
    assert h.fake.approval_calls == 0


async def test_clarification_exact_id(harness):
    h = harness
    _, r, sid = await h.start_run()
    await h.fake.emit(sid, 'clarify.request', {'request_id': 'unique', 'question': 'Which?', 'choices': ['a', 'b']})
    await eventually(lambda: h.service.store.db.execute('SELECT COUNT(*) FROM attention').fetchone()[0] == 1)
    item = (await h.request('GET', '/attention'))['items'][0]
    await h.request('POST', f"/attention/{item['id']}/respond", {'answer': 'a'})
    assert h.fake.methods.count('clarify.respond') == 1
    await h.request('POST', f"/attention/{item['id']}/respond", {'answer': 'b'}, expected=409)


async def test_artifact_upload_download_path_attack(harness, tmp_path):
    h = harness
    c = await h.request('POST', '/conversations', {}, expected=201)
    content = b'example data'
    out = await h.request('POST', '/attachments', {'conversation_id': c['id'], 'name': 'test.txt', 'content_type': 'text/plain', 'content_base64': base64.b64encode(content).decode()}, expected=201)
    aid = out['artifact']['id']
    async with h.client.get(f'http://127.0.0.1:{h.port}/mobile/v1/artifacts/{aid}/download') as res:
        assert res.status == 200 and await res.read() == content
    assert 'path' not in (await h.request('GET', f'/artifacts/{aid}'))
    await h.request('POST', '/attachments', {'conversation_id': c['id'], 'name': '../escape.txt', 'content_type': 'text/plain', 'content_base64': 'eA=='}, expected=400)
    outside = tmp_path / 'secret'
    outside.write_text('secret')
    link = h.fake.root / 'link'
    link.symlink_to(outside)
    assert h.service.register_artifact(c['id'], 'default', str(link)) is None
    assert h.service.register_artifact(c['id'], 'default', str(h.fake.root / '..' / 'secret')) is None
    target = Path(h.service.store.get('artifacts', aid)['data']['path'])
    target.unlink()
    target.symlink_to(outside)
    await h.request('GET', f'/artifacts/{aid}/download', expected=403)


async def test_sessions_inventory_cron_kanban_home(harness):
    h = harness
    capabilities = await h.request('GET', '/capabilities')
    assert capabilities['profiles']['default']['boards'] == h.service.backends['default'].cfg['boards']
    from hermes_mobile_bridge.api import task_targets
    assert task_targets({'status': 'running'}) == []
    assert 'blocked' not in task_targets({'status': 'triage'})
    assert set(task_targets({'status': 'blocked'})) == {'triage', 'todo', 'ready', 'archived', 'scheduled', 'done'}
    c = await h.request('POST', '/conversations', {'title': 'original'}, expected=201)
    assert (await h.request('GET', '/conversations?q=hello'))['conversations'][0]['id'] == c['id']
    await h.request('PATCH', f"/conversations/{c['id']}", {'title': 'renamed'})
    detail = await h.request('GET', f"/conversations/{c['id']}")
    assert detail['conversation']['title'] == 'renamed' and 'api_key' not in json.dumps(detail)
    for name in ['models', 'mcp', 'skills', 'tools', 'usage', 'host']:
        assert 'secret' not in json.dumps(await h.request('GET', '/inventory/' + name))
    job = await h.request('POST', '/cron', {'prompt': 'work', 'schedule': 'every 1h'}, expected=201)
    await h.request('POST', f"/cron/{job['id']}/disable", {})
    await h.request('PATCH', f"/cron/{job['id']}", {'name': 'updated'})
    triggered = await h.request('POST', f"/cron/{job['id']}/run-now", {})
    assert triggered['scheduler_required'] and not triggered['execution_started']
    card = await h.request('POST', '/kanban/tasks', {'title': 'work'}, expected=201)
    await h.request('PATCH', f"/kanban/tasks/{card['id']}", {'status': 'blocked', 'block_reason': 'dependency'})
    assert (await h.request('GET', f"/kanban/tasks/{card['id']}"))['task']['block_reason'] == 'dependency'
    assert (await h.request('GET', '/home'))['failed_or_blocked'][0]['kind'] == 'kanban'
    await h.request('DELETE', f"/kanban/tasks/{card['id']}", {})
    await h.request('DELETE', f"/cron/{job['id']}", {})
    await h.request('DELETE', f"/conversations/{c['id']}", {})


async def test_malformed_client_failed_upstream(harness):
    h = harness
    await h.request('POST', '/conversations', {'cwd': '/arbitrary'}, expected=400)
    await h.request('GET', '/conversations?limit=no', expected=400)
    async with h.client.post(f'http://127.0.0.1:{h.port}/mobile/v1/conversations', data='{', headers={'Content-Type': 'application/json', 'Idempotency-Key': str(uuid.uuid4())}) as res:
        assert res.status == 400
    _, r, sid = await h.start_run()
    await h.fake.ws.close()
    await eventually(lambda: not h.service.backends['default'].connected)
    await h.request('POST', f"/runs/{r['id']}/stop", {}, expected=409)
    await h.request('POST', '/conversations', {}, expected=503)


async def test_bounded_retention_epoch(harness):
    h = harness
    _, r, sid = await h.start_run()
    cursor = h.service.store.cursor()
    h.cfg['run_event_limit'] = 3
    for i in range(8):
        await h.fake.emit(sid, 'message.delta', {'text': str(i)})
    await eventually(lambda: h.service.store.get('runs', r['id'])['data']['assistant_text'] == '01234567')
    page = await h.request('GET', f"/runs/{r['id']}/events?after={cursor}", expected=409)
    assert page['error']['code'] == 'resync_required'
    assert h.service.store.db.execute('SELECT COUNT(*) FROM events WHERE run_id=?', (r['id'],)).fetchone()[0] <= 3
    await h.request('GET', '/events?after=wrong:1', expected=409)


async def test_duplicate_bridge_owner(harness):
    with pytest.raises(ValueError, match='already owns'):
        Store(harness.cfg)


async def test_external_session_not_stolen(harness):
    h = harness
    c = await h.request('POST', '/conversations', {}, expected=201)
    row = h.service.store.get('conversations', c['id'])
    h.fake.sessions['foreign'] = h.fake.sessions.pop(row['live_id'])
    await h.request('POST', f"/conversations/{c['id']}/resume", {}, expected=409)
    assert 'session.resume' not in h.fake.methods


def test_private_config_and_secret_permissions(tmp_path):
    token, config = tmp_path / 'token', tmp_path / 'config.json'
    token.write_text('u' * 32)
    token.chmod(0o600)
    config.write_text(json.dumps({'state_dir': str(tmp_path / 'state'), 'backends': {'default': {'url': 'http://127.0.0.1:9119', 'token_file': str(token)}}}))
    config.chmod(0o600)
    assert load_config(config)['backends']['default']['token'] == 'u' * 32
    token.chmod(0o644)
    with pytest.raises(ValueError):
        load_config(config)


async def test_lost_submit_reply_is_uncertain_and_not_replayed(harness):
    h = harness
    c = await h.request('POST', '/conversations', {}, expected=201)
    h.fake.drop_prompt_reply = True
    key = str(uuid.uuid4())
    path = f"/conversations/{c['id']}/runs"
    await h.request('POST', path, {'text': 'once'}, key, 503)
    await eventually(lambda: h.service.backends['default'].generation >= 2)
    await h.request('POST', path, {'text': 'once'}, key, 409)
    assert h.fake.prompts == 1
    assert len((await h.request('GET', '/runs'))['runs']) == 1


async def test_expired_clarification_and_replayed_request_id(harness):
    h = harness
    _, r, sid = await h.start_run()
    payload = {'request_id': 'same', 'question': 'Question?'}
    await h.fake.emit(sid, 'clarify.request', payload)
    await eventually(lambda: h.service.store.db.execute('SELECT COUNT(*) FROM attention').fetchone()[0] == 1)
    item = (await h.request('GET', '/attention'))['items'][0]
    raw = h.service.store.get('attention', item['id'])['data']
    raw['expires_at'] = time.time() - 1
    h.service.store.db.execute('UPDATE attention SET data=? WHERE id=?', (json.dumps(raw), item['id']))
    h.service.store.db.commit()
    await h.fake.emit(sid, 'clarify.request', payload)
    await h.request('POST', f"/attention/{item['id']}/respond", {'answer': 'late'}, expected=409)
    assert h.fake.methods.count('clarify.respond') == 0
    assert h.service.store.db.execute('SELECT COUNT(*) FROM attention').fetchone()[0] == 1


async def test_late_approval_after_stop_reasserts_interrupt(harness):
    h = harness
    _, r, sid = await h.start_run()
    await h.request('POST', f"/runs/{r['id']}/stop", {})
    await h.fake.emit(sid, 'approval.request', {'command': 'late'})
    await eventually(lambda: h.fake.methods.count('session.interrupt') == 2)
    assert h.fake.approval_calls == 0
    assert (await h.request('GET', f"/runs/{r['id']}"))['state'] == 'stop_requested'
    await h.fake.emit(sid, 'message.complete', {'text': None, 'status': 'interrupted'})
    await eventually(lambda: h.service.store.get('runs', r['id'])['state'] == 'cancelled')
    assert h.service.backends['default'].connected


async def test_scoped_events_and_private_database(harness):
    h = harness
    h.service.store.append('forbidden-profile', 'run.started', {'secret': 'hidden'})
    page = await h.request('GET', '/events')
    assert all(e['profile'] == 'default' for e in page['events'])
    await h.request('GET', '/conversations?profile=forbidden-profile', expected=403)
    from pathlib import Path
    for f in Path(h.cfg['state_dir']).glob('bridge.sqlite3*'):
        assert f.stat().st_mode & 0o077 == 0


async def test_byte_retention_and_paginated_replay(harness):
    h = harness
    _, r, sid = await h.start_run()
    cursor = h.service.store.cursor()
    for i in range(6):
        await h.service.emit('default', 'assistant.delta', {'text': str(i)}, h.service.store.get('runs', r['id']))
    page = await h.request('GET', f"/runs/{r['id']}/events?after={cursor}&limit=2")
    assert page['has_more'] and len(page['events']) == 2
    other = await h.request('GET', f"/runs/{r['id']}/events?after={page['cursor']}&limit=2")
    assert page['events'][-1]['seq'] < other['events'][0]['seq']
    h.cfg['event_bytes'] = 2000
    for i in range(6):
        await h.service.emit('default', 'tool.completed', {'result': 'x' * 1000}, h.service.store.get('runs', r['id']))
    size = h.service.store.db.execute('SELECT SUM(LENGTH(data)+COALESCE(LENGTH(raw),0)) FROM events').fetchone()[0]
    assert size <= 2000
    await h.request('GET', f"/runs/{r['id']}/events?after={cursor}", expected=409)


async def test_concurrent_start_one_execution(harness):
    h = harness
    c = await h.request('POST', '/conversations', {}, expected=201)
    async def start():
        async with h.client.post(f"http://127.0.0.1:{h.port}/mobile/v1/conversations/{c['id']}/runs", json={'text': 'work'}, headers={'Idempotency-Key': str(uuid.uuid4())}) as res:
            return res.status
    assert sorted(await asyncio.gather(start(), start())) == [202, 409]
    assert h.fake.prompts == 1


async def test_cli_store_open_does_not_invalidate_inflight_command(harness):
    h = harness
    key = str(uuid.uuid4())
    h.service.store.command_begin(key, h.credential, {'action': 'test'})
    other = Store(h.cfg, lock=False)
    try:
        assert other.db.execute('SELECT status FROM commands WHERE id=?', (key,)).fetchone()[0] == 'pending'
    finally:
        other.close()


async def test_late_duplicate_completion_cannot_revive_run(harness):
    h = harness
    _, r, sid = await h.start_run()
    done = {'text': 'Final', 'status': 'complete'}
    await h.fake.emit(sid, 'message.complete', done)
    await eventually(lambda: h.service.store.get('runs', r['id'])['state'] == 'complete')
    await h.fake.emit(sid, 'message.complete', done)
    await h.fake.emit(sid, 'message.delta', {'text': 'late'})
    await h.fake.emit(sid, 'approval.request', {'command': 'stale'})
    await asyncio.sleep(.05)
    view = await h.request('GET', f"/runs/{r['id']}")
    assert view['state'] == 'complete' and view['assistant_text'] == 'Final'
    page = await h.request('GET', f"/runs/{r['id']}/events")
    assert [e['type'] for e in page['events']].count('assistant.completed') == 1
    assert not (await h.request('GET', '/attention'))['items']


async def test_packaged_cli_provision_serve_revoke(harness, tmp_path):
    import subprocess
    import sys
    from pathlib import Path
    h = harness
    secret = tmp_path / 'upstream-token'
    secret.write_text('u' * 32)
    secret.chmod(0o600)
    import socket
    sock = socket.socket()
    sock.bind(('127.0.0.1', 0))
    port = sock.getsockname()[1]
    sock.close()
    cfg = tmp_path / 'cli.json'
    cfg.write_text(json.dumps({'state_dir': str(tmp_path / 'cli-state'), 'listen_port': port, 'backends': {'default': {'url': f'http://127.0.0.1:{h.upstream_port}', 'token_file': str(secret)}}}))
    cfg.chmod(0o600)
    executable = Path(sys.executable).parent / 'hermes-mobile-bridge'
    if not executable.exists():
        pytest.skip('Packaged entry point requires installing bridge in its own environment')
    command = [str(executable), '--config', str(cfg)]
    created = await asyncio.to_thread(subprocess.run, command + ['token-create', '--name', 'test-phone'], capture_output=True, text=True, timeout=10)
    assert created.returncode == 0
    credential = json.loads(created.stdout)  # never print provisioning secrets
    proc = subprocess.Popen(command + ['serve'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        async with aiohttp.ClientSession(headers={'Authorization': 'Bearer ' + credential['token']}) as client:
            async with asyncio.timeout(10):
                while True:
                    try:
                        async with client.get(f'http://127.0.0.1:{port}/mobile/v1/capabilities') as res:
                            if res.status == 200:
                                body = await res.json()
                                if body['profiles']['default']['health']['connected']:
                                    break
                    except aiohttp.ClientError:
                        pass
                    await asyncio.sleep(.05)
            revoked = await asyncio.to_thread(subprocess.run, command + ['token-revoke', credential['id']], capture_output=True, timeout=10)
            assert revoked.returncode == 0
            async with client.get(f'http://127.0.0.1:{port}/mobile/v1/capabilities') as res:
                assert res.status == 401
    finally:
        proc.terminate()
        try:
            await asyncio.to_thread(proc.wait, 5)
        except subprocess.TimeoutExpired:
            proc.kill()
            await asyncio.to_thread(proc.wait)
