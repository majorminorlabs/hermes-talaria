"""Exact queue-backed approval requests; legacy FIFO is never used."""
import asyncio
import json
import uuid
import pytest
from conftest import eventually

COMMIT = '4bb9e57bfde8a0affb5553eff13ed6e1f14147f1'

async def approval(h, choices=None, permanent=False):
    b = h.service.backends['default']
    b.cfg['installed_commit'] = 'unknown-newer-commit'
    generation = b.generation
    await h.fake.ws.close()
    await eventually(lambda: b.connected and b.generation > generation and b.approval_requests_supported)
    c, run, sid = await h.start_run()
    req = {'id': 'srq-test', 'method': 'approval', 'params': {
        'session_id': sid, 'request_id': 'queue-entry', 'command': 'rm fixture.txt',
        'description': 'Fixture deletion', 'choices': choices or ['once', 'session', 'deny'],
        'allow_permanent': permanent, 'on_timeout': 'Block this command'}}
    h.fake.sessions[sid].update(status='waiting', open_requests=[req])
    await h.fake.ws.send_json({'jsonrpc': '2.0', **req})
    await eventually(lambda: h.service.store.db.execute('SELECT COUNT(*) FROM attention').fetchone()[0] == 1)
    item = (await h.request('GET', '/attention'))['items'][0]
    assert item['can_respond'] and item['details']['command'] == 'rm fixture.txt'
    assert item['details']['on_timeout'] == 'Block this command'
    return item, req, sid

@pytest.mark.parametrize('choice', ['once', 'deny', 'session'])
async def test_exact_approval(harness, choice):
    h = harness
    item, req, sid = await approval(h)
    caps = (await h.request('GET', '/capabilities'))['profiles']['default']['features']['approvals']
    assert caps['respond'] and 'reason' not in caps
    await h.request('POST', f"/attention/{item['id']}/respond", {'choice': choice})
    assert h.fake.answer_calls == [{'id': req['id'], 'result': {'choice': choice}}]
    assert not h.fake.approval_calls
    assert h.service.store.get('attention', item['id'])['data']['state'] == 'responded'

@pytest.mark.parametrize("reason", ["resolved", "timeout"])
async def test_cancel_and_stale(harness, reason):
    h = harness
    item, req, sid = await approval(h)
    h.fake.sessions[sid]['open_requests'] = []
    await h.fake.emit(sid, 'request.cancel', {'id': req['id'], 'method': 'approval', 'reason': reason})
    await eventually(lambda: h.service.store.get('attention', item['id'])['data']['state'] == 'expired')
    out = await h.request('POST', f"/attention/{item['id']}/respond", {'choice': 'once'}, expected=409)
    assert out['error']['code'] == 'stale_attention'
    assert not h.fake.answer_calls
    await h.service.hydrate_requests('default', sid, {'open_requests': [req]})
    assert h.service.store.get('attention', item['id'])['data']['state'] == 'expired'

async def test_double_tap_and_reconnect_replay(harness):
    h = harness
    item, req, sid = await approval(h)
    results = await asyncio.gather(*(h.client.post(f'http://127.0.0.1:{h.port}/mobile/v1/attention/{item["id"]}/respond', json={'choice': 'once'}, headers={'Idempotency-Key': str(uuid.uuid4())}) for _ in range(2)))
    assert sorted(r.status for r in results) == [200, 409]
    for response in results:
        await response.read()
    assert len(h.fake.answer_calls) == 1
    # A delayed frame and even an upstream reconnect snapshot cannot resurrect it.
    await h.service.server_request('default', sid, req)
    h.fake.sessions[sid]['open_requests'] = [req]
    generation = h.service.backends['default'].generation
    await h.fake.ws.close()
    await eventually(lambda: h.service.backends['default'].connected and h.service.backends['default'].generation > generation)
    assert h.service.store.get('attention', item['id'])['data']['state'] == 'responded'
    out = await h.request('POST', f"/attention/{item['id']}/respond", {'choice': 'deny'}, expected=409)
    assert out['error']['code'] == 'stale_attention'
    assert len(h.fake.answer_calls) == 1

@pytest.mark.parametrize('body', [{'choice': 'bogus'}, {'choice': 'all'}, {'choice': 'once', 'all': True}, {'choice': 'always'}, {'answer': 'yes'}])
async def test_invalid_choices(harness, body):
    h = harness
    item, _, _ = await approval(h, ['once', 'deny', 'always'], permanent=False)
    await h.request('POST', f"/attention/{item['id']}/respond", body, expected=400)
    assert not h.fake.answer_calls

@pytest.mark.parametrize('condition', ['missing', 'generation', 'offline', 'expired', 'queue_changed', 'mac_race'])
async def test_stale_preconditions(harness, condition):
    h = harness
    item, req, sid = await approval(h)
    b = h.service.backends['default']
    if condition == 'missing': h.fake.sessions[sid]['open_requests'] = []
    if condition == 'generation': b.generation += 1
    if condition == 'offline': b.connected = False
    if condition == 'expired':
        raw = h.service.store.get('attention', item['id'])['data']; raw['expires_at'] = 0
        h.service.store.db.execute('UPDATE attention SET data=? WHERE id=?', (json.dumps(raw), item['id'])); h.service.store.db.commit()
    if condition == 'queue_changed': req['params']['request_id'] = 'another-entry'
    if condition == 'mac_race': h.fake.expire_on_answer = True
    out = await h.request('POST', f"/attention/{item['id']}/respond", {'choice': 'once'}, expected=409)
    assert out['error']['code'] == 'stale_attention'
    assert len(h.fake.answer_calls) == (1 if condition == 'mac_race' else 0)

async def test_legacy_event_stays_disabled_even_on_modern_backend(harness):
    h = harness
    b = h.service.backends['default']
    b.cfg['installed_commit'] = 'unknown-newer-commit'
    generation = b.generation
    await h.fake.ws.close()
    await eventually(lambda: b.connected and b.generation > generation and b.approval_requests_supported)
    _, _, sid = await h.start_run()
    await h.fake.emit(sid, 'approval.request', {'request_id': 'legacy-queue-id', 'command': 'rm fixture.txt', 'choices': ['once', 'deny']})
    await eventually(lambda: h.service.store.db.execute('SELECT COUNT(*) FROM attention').fetchone()[0] == 1)
    item = (await h.request('GET', '/attention'))['items'][0]
    assert not item['can_respond']
    out = await h.request('POST', f"/attention/{item['id']}/respond", {'choice': 'deny'}, expected=409)
    assert out['error']['code'] == 'exact_target_unavailable'
    assert not h.fake.answer_calls and not h.fake.approval_calls

@pytest.mark.parametrize('methods,error,clarify,respond', [
    (['approval'], None, False, True),
    (['clarify'], None, True, False),
    ([], -32601, False, False),
    (['clarify', 'approval'], -32000, False, False),
])
async def test_advertised_capabilities_not_commit(harness, methods, error, clarify, respond):
    h = harness
    b = h.service.backends['default']
    old_generation = b.generation
    h.fake.capability_methods, h.fake.capability_error = methods, error
    b.cfg['installed_commit'] = 'unknown-newer-commit'
    await h.fake.ws.close()
    await eventually(lambda: b.connected and b.generation > old_generation)
    caps = (await h.request('GET', '/capabilities'))['profiles']['default']['features']['approvals']
    assert caps['respond'] == respond
    assert caps['clarifications'] == clarify
    assert b.declines_not_shown == (error is None)
    assert ('reason' in caps) == (not respond)
    assert ('client.capabilities', {'server_requests': True}) in h.fake.requests
    if error:
        _, _, sid = await h.start_run()
        await h.fake.emit(sid, 'approval.request', {'request_id': 'legacy', 'command': 'rm fixture.txt'})
        await eventually(lambda: h.service.store.db.execute('SELECT COUNT(*) FROM attention').fetchone()[0] == 1)
        item = (await h.request('GET', '/attention'))['items'][0]
        assert not item['can_respond']
        out = await h.request('POST', f"/attention/{item['id']}/respond", {'choice': 'once'}, expected=409)
        assert out['error']['code'] == 'exact_target_unavailable'
        assert not h.fake.approval_calls

@pytest.mark.parametrize('permanent', [False, True])
async def test_always_rejected_even_when_offered(harness, permanent):
    item, _, _ = await approval(harness, ['once', 'always', 'deny'], permanent=permanent)
    out = await harness.request('POST', f"/attention/{item['id']}/respond", {'choice': 'always'}, expected=400)
    assert out['error']['code'] == 'invalid_choice'
    assert not harness.fake.answer_calls

async def test_null_expiry_remains_actionable_until_cancel(harness, monkeypatch):
    h = harness
    item, req, sid = await approval(h)
    assert item['expires_at'] is None
    # Advance past the old 290-second cutoff without waiting in real time.
    future = item['observed_at'] + 1000
    monkeypatch.setattr('hermes_mobile_bridge.service.now', lambda: future)
    monkeypatch.setattr('hermes_mobile_bridge.api.now', lambda: future)
    assert (await h.request('GET', '/attention'))['items'][0]['can_respond']
    h.fake.sessions[sid]['open_requests'] = []
    await h.fake.emit(sid, 'request.cancel', {'id': req['id'], 'method': 'approval', 'reason': 'timeout'})
    await eventually(lambda: h.service.store.get('attention', item['id'])['data']['state'] == 'expired')
    out = await h.request('POST', f"/attention/{item['id']}/respond", {'choice': 'once'}, expected=409)
    assert out['error']['code'] == 'stale_attention'

@pytest.mark.parametrize('timeout,fail', [(900, False), (None, False), (900, True)])
async def test_read_only_configured_expiry_or_null(harness, timeout, fail):
    h = harness
    h.fake.approval_timeout, h.fake.fail_config = timeout, fail
    # The fake intentionally omits config from OpenAPI for legacy/null tests.
    item, req, sid = await approval(h)
    b = h.service.backends['default']
    b.paths.add('/api/config')
    # New request, not a replay (which must preserve its original expiry).
    req['id'] = 'srq-config'
    req['params']['request_id'] = 'queue-config'
    h.fake.sessions[sid]['open_requests'] = [req]
    await h.service.server_request('default', sid, req)
    items = (await h.request('GET', '/attention'))['items']
    configured = next(i for i in items if i['id'] != item['id'])
    assert configured['expires_at'] == (configured['observed_at'] + timeout if timeout is not None and not fail else None)
    assert 'must-never-leak' not in json.dumps(items)
    await h.service.server_request('default', sid, req)
    replay = h.service.store.get('attention', configured['id'])['data']
    assert replay['expires_at'] == configured['expires_at']
