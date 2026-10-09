"""Exercise the actual local CLI against a live bridge and isolated fake Hermes."""
import asyncio
import importlib.util
import json
import os
import pwd
import sys
from pathlib import Path

import pytest

from hermes_mobile_bridge.operator import reconcile_run
from hermes_mobile_bridge.store import Store


def private_json(path, value):
    path.write_text(json.dumps(value))
    path.chmod(0o600)


def cli_config(h, tmp):
    token = tmp / 'upstream-token'
    token.write_text('u' * 32)
    token.chmod(0o600)
    cfg = json.loads(json.dumps(h.cfg))
    cfg['backends']['default'].pop('token')
    cfg['backends']['default']['token_file'] = str(token)
    path = tmp / 'config.json'
    private_json(path, cfg)
    return path


async def command(h, tmp, run_id, reason='orphaned validation'):
    process = await asyncio.create_subprocess_exec(
        sys.executable, '-c', 'from hermes_mobile_bridge.cli import main; main()',
        '--config', str(cli_config(h, tmp)), 'reconcile-run', run_id, '--reason', reason,
        stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE)
    out, err = await asyncio.wait_for(process.communicate(), 15)
    return process.returncode, json.loads(out or err)


def events(store, rid):
    return [json.loads(row[0]) for row in store.db.execute('SELECT data FROM events WHERE run_id=? ORDER BY seq', (rid,))]


def attention(store, rid, aid, state='pending'):
    item = {'id': aid, 'run_id': rid, 'profile': 'default', 'state': state, 'can_respond': True}
    store.db.execute('INSERT INTO attention VALUES (?,?,?,?)', (aid, rid, 'default', json.dumps(item)))
    store.db.commit()


def updater():
    path = Path(__file__).resolve().parents[2] / 'scripts' / 'bridge-service.py'
    spec = importlib.util.spec_from_file_location('reconcile_test_updater', path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


async def test_cli_refuses_live_handle_even_when_idle(harness, tmp_path):
    h = harness
    _, run, sid = await h.start_run()
    h.service.store.update_run(run['id'], 'unknown')
    h.fake.sessions[sid]['status'] = 'idle'
    before = events(h.service.store, run['id'])
    code, result = await command(h, tmp_path, run['id'])
    assert code == 1 and result['error']['code'] == 'run_still_live'
    assert h.service.store.get('runs', run['id'])['state'] == 'unknown'
    assert events(h.service.store, run['id']) == before


@pytest.mark.parametrize('state', ['starting', 'running', 'waiting_for_input', 'stop_requested', 'complete', 'failed', 'cancelled'])
async def test_cli_refuses_other_states(harness, tmp_path, state):
    h = harness
    _, run, sid = await h.start_run()
    h.service.store.update_run(run['id'], state)
    h.fake.sessions.pop(sid)
    code, result = await command(h, tmp_path, run['id'])
    assert code == 1 and result['error']['code'] == 'reconciliation_unavailable'
    assert h.service.store.get('runs', run['id'])['state'] == state
    assert not any(e['type'] == 'run.reconciled' for e in events(h.service.store, run['id']))


@pytest.mark.parametrize('state', ['unknown', 'uncertain'])
async def test_cli_reconciles_audits_and_expires_attention(harness, tmp_path, state):
    h = harness
    _, run, sid = await h.start_run()
    store = h.service.store
    store.update_run(run['id'], state, reason='upstream_disconnected', coverage_gap=True)
    h.fake.sessions.pop(sid)
    attention(store, run['id'], 'pending')
    attention(store, run['id'], 'uncertain', 'uncertain')
    attention(store, run['id'], 'answered', 'responded')
    before = events(store, run['id'])
    code, result = await command(h, tmp_path, run['id'], 'explicit orphan reason')
    assert code == 0 and result['state'] == 'failed'
    assert result['prior_state'] == state and result['reason'] == 'explicit orphan reason'
    assert set(result['expired_attention']) == {'pending', 'uncertain'}
    updated = store.get('runs', run['id'])
    assert updated['state'] == 'failed'
    assert updated['data']['coverage_gap'] is True
    assert updated['data']['reason'] == 'operator_reconciled'
    assert updated['data']['reconciliation']['prior_reason'] == 'upstream_disconnected'
    for aid in ['pending', 'uncertain']:
        item = store.get('attention', aid)['data']
        assert item['state'] == 'expired' and item['can_respond'] is False
    assert store.get('attention', 'answered')['data']['state'] == 'responded'
    appended = events(store, run['id'])[len(before):]
    audit = next(e for e in appended if e['type'] == 'run.reconciled')['payload']
    assert audit['operator'] == pwd.getpwuid(os.getuid()).pw_name
    assert audit['time'] > run['created_at'] and audit['prior_state'] == state
    assert audit['reason'] == 'explicit orphan reason'
    assert appended[-1]['type'] == 'run.failed'
    assert len([e for e in appended if e['type'] == 'approval.resolved']) == 2
    # The still-running bridge sees the external transaction without a restart.
    view = await h.request('GET', '/runs/' + run['id'])
    assert view['state'] == 'failed' and view['coverage_gap'] is True
    # The real updater gate rejects the orphan first, then accepts the repair.
    root = tmp_path / 'runtime'
    root.mkdir(mode=0o700)
    private_json(root / 'config.json', {'state_dir': h.cfg['state_dir']})
    private_json(root / 'installation.json', {'bridge_port': h.port})
    private_json(root / 'operator.json', {'token': h.token})
    await asyncio.to_thread(updater().ensure_idle, root)
    code, second = await command(h, tmp_path, run['id'])
    assert code == 1 and second['error']['code'] == 'reconciliation_unavailable'
    assert events(store, run['id'])[len(before):] == appended


async def test_ensure_idle_blocks_before_reconciliation(harness, tmp_path):
    h = harness
    _, run, sid = await h.start_run()
    h.service.store.update_run(run['id'], 'unknown')
    h.fake.sessions.pop(sid)
    root = tmp_path / 'runtime'
    root.mkdir(mode=0o700)
    private_json(root / 'config.json', {'state_dir': h.cfg['state_dir']})
    private_json(root / 'installation.json', {'bridge_port': h.port})
    private_json(root / 'operator.json', {'token': h.token})
    gate = updater()
    with pytest.raises(ValueError, match='Active/unknown work exists'):
        await asyncio.to_thread(gate.ensure_idle, root)
    code, _ = await command(h, tmp_path, run['id'])
    assert code == 0
    await asyncio.to_thread(gate.ensure_idle, root)


async def test_invalid_inventory_fails_closed(harness, tmp_path):
    h = harness
    _, run, sid = await h.start_run()
    h.service.store.update_run(run['id'], 'unknown')
    session = h.fake.sessions.pop(sid)
    h.fake.sessions[123] = session  # Invalid id in the upstream inventory.
    code, result = await command(h, tmp_path, run['id'])
    assert code == 1 and result['error']['code'] == 'reconciliation_unverified'
    assert h.service.store.get('runs', run['id'])['state'] == 'unknown'


async def test_atomic_rollback_on_event_failure(harness, monkeypatch):
    h = harness
    _, run, sid = await h.start_run()
    store = h.service.store
    store.update_run(run['id'], 'unknown')
    h.fake.sessions.pop(sid)
    attention(store, run['id'], 'pending')
    before = events(store, run['id'])
    original = Store.append
    def failing_append(self, profile, kind, *args, **kwargs):
        if kind == 'run.failed':
            raise RuntimeError('simulated journal write failure')
        return original(self, profile, kind, *args, **kwargs)
    monkeypatch.setattr(Store, 'append', failing_append)
    with pytest.raises(RuntimeError, match='simulated journal'):
        await reconcile_run(h.cfg, run['id'], 'operator reason')
    assert store.get('runs', run['id'])['state'] == 'unknown'
    assert store.get('attention', 'pending')['data']['state'] == 'pending'
    assert events(store, run['id']) == before
