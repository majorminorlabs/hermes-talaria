"""Opt-in E2E: installed upstream, isolated HERMES_HOME, local-only model."""
import asyncio
import json
import os
import socket
import subprocess
import sys
import uuid
from pathlib import Path
import aiohttp
from aiohttp import web
import pytest
from hermes_mobile_bridge.api import create_app, SERVICE
from conftest import eventually, serve

SOURCE = Path(os.environ.get('HERMES_SOURCE', str(Path.home()/'.hermes/hermes-agent')))
pytestmark = pytest.mark.skipif(os.environ.get('HERMES_BRIDGE_E2E') != '1', reason='Set HERMES_BRIDGE_E2E=1 for isolated installed-Hermes integration')


class LocalModel:
    def __init__(self):
        self.calls = []
        self.app = web.Application()
        self.app.router.add_post('/v1/chat/completions', self.complete)
        self.app.router.add_get('/v1/models', self.models)

    async def models(self, request):
        return web.json_response({'data': [{'id': 'bridge-local-test'}]})

    async def complete(self, request):
        body = await request.json()
        self.calls.append(body)
        messages = body['messages']
        last_user = max((i for i, m in enumerate(messages) if m.get('role') == 'user'), default=-1)
        tool_done = any(m.get('role') == 'tool' for m in messages[last_user + 1:])
        user = next((m.get('content', '') for m in reversed(messages) if m.get('role') == 'user'), '')
        wants_tool = ('exercise-tool' in str(user) or 'exercise-safe-tool' in str(user)) and not tool_done
        command = 'sleep 2' if 'exercise-safe-tool' in str(user) else "python3 -c 'import time; time.sleep(2); print(\"LOCAL_TOOL_OK\")'"
        payload = {'role': 'assistant', 'content': 'Reply from isolated local model.'}
        if wants_tool:
            payload = {'role': 'assistant', 'content': None, 'tool_calls': [{'id': 'call_local', 'type': 'function', 'function': {'name': 'terminal', 'arguments': json.dumps({'command': command, 'timeout': 10})}}]}
        if 'exercise-clarify' in str(user) and not tool_done:
            wants_tool = True
            payload = {'role': 'assistant', 'content': None, 'tool_calls': [{'id': 'call_clarify', 'type': 'function', 'function': {'name': 'clarify', 'arguments': json.dumps({'questions': [{'question': 'Fixture question one?', 'choices': ['Proceed', 'Wait']}, {'question': 'Fixture question two?'}]})}}]}
        finish = 'tool_calls' if wants_tool else 'stop'
        if body.get('stream'):
            response = web.StreamResponse(headers={'Content-Type': 'text/event-stream'})
            await response.prepare(request)
            delta = payload.copy()
            delta.pop('role', None)
            if 'tool_calls' in delta:
                delta['tool_calls'][0]['index'] = 0
            for chunk in [{'choices': [{'index': 0, 'delta': delta, 'finish_reason': None}]}, {'choices': [{'index': 0, 'delta': {}, 'finish_reason': finish}], 'usage': {'prompt_tokens': 20, 'completion_tokens': 8, 'total_tokens': 28}}]:
                await response.write(('data: ' + json.dumps({'id': 'chatcmpl-local', 'object': 'chat.completion.chunk', 'model': 'bridge-local-test', **chunk}) + '\n\n').encode())
            await response.write(b'data: [DONE]\n\n')
            return response
        return web.json_response({'id': 'chatcmpl-local', 'object': 'chat.completion', 'created': 1, 'model': 'bridge-local-test', 'choices': [{'index': 0, 'message': payload, 'finish_reason': finish}], 'usage': {'prompt_tokens': 20, 'completion_tokens': 8, 'total_tokens': 28}})


async def test_installed_source_end_to_end(tmp_path):
    commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=SOURCE, text=True).strip()
    from hermes_mobile_bridge.bots import AUDITED_COMMITS
    assert any(commit.startswith(c) for c in AUDITED_COMMITS)
    model = LocalModel()
    model_runner, model_port = await serve(model.app)
    sock = socket.socket()
    sock.bind(('127.0.0.1', 0))
    port = sock.getsockname()[1]
    sock.close()
    home, work = tmp_path / 'hermes-home', tmp_path / 'work'
    home.mkdir(mode=0o700)
    work.mkdir()
    (home / 'config.yaml').write_text(f'''model:
  default: bridge-local-test
  provider: custom
  base_url: http://127.0.0.1:{model_port}/v1
  api_key: local-test-only
  api_mode: chat_completions
agent:
  max_turns: 4
  reasoning_effort: none
toolsets: [terminal, file, skills, clarify]
display:
  tool_progress: all
terminal:
  backend: local
  cwd: {work}
memory:
  memory_enabled: false
  user_profile_enabled: false
''')
    if commit == '4bb9e57bfde8a0affb5553eff13ed6e1f14147f1':
        from test_bots import SKILLS
        for name, title in [('research-orchestrator', 'Research Orchestrator'), ('research-worker', 'Research Worker')]:
            profile = home / 'profiles' / name
            profile.mkdir(parents=True)
            (profile / 'config.yaml').write_text((home / 'config.yaml').read_text().replace('default: bridge-local-test', 'default: bridge-' + name + '-test'))
            (profile / 'profile.yaml').write_text('display_name: ' + title + '\nui_meta:\n  hermes-bots:\n    title: ' + title + '\n')
            (profile / 'SOUL.md').write_text('ISOLATED_' + name.upper().replace('-', '_') + '_CONTEXT_MARKER')
            for skill in SKILLS:
                folder = profile / 'skills' / skill
                folder.mkdir(parents=True)
                (folder / 'SKILL.md').write_text('---\nname: ' + skill + '\ndescription: Safe fixture\n---\n')
    # No host provider credentials are inherited. Upstream receives a dummy
    # local-model key in its isolated config, not the production .env.
    env = {k: v for k, v in os.environ.items() if not any(x in k.upper() for x in ('API_KEY', 'TOKEN', 'SECRET', 'HERMES_', 'ANTHROPIC_', 'OPENAI_', 'OPENROUTER_', 'NOUS_')) and k not in {'PYTHONPATH', 'PYTHONHOME'}}
    env.update(HERMES_DISABLE_LAZY_INSTALLS='1', HERMES_HOME=str(home), HERMES_DASHBOARD_SESSION_TOKEN='u' * 32, HERMES_TUI_TOOLSETS='terminal,file,skills,clarify', PYTHONUNBUFFERED='1')
    if commit == '4bb9e57bfde8a0affb5553eff13ed6e1f14147f1':
        # Reuse installed code dependencies, never production config/provider credentials.
        env['HERMES_RUNTIME_DIR'] = str(SOURCE.parent / 'tools')
    log = open(tmp_path / 'hermes-local.log', 'w')
    python = SOURCE / 'venv/bin/python'
    proc = None
    bridge_runner = None
    client = None
    try:
        args = [str(python), '-c', f'from hermes_cli.web_server import start_server; start_server(port={port}, open_browser=False)']
        if commit == '4bb9e57bfde8a0affb5553eff13ed6e1f14147f1':
            resolver = 'import sys,json; from pathlib import Path; sys.path.insert(0,sys.argv[1]); from hermes_cli._launchers import runtime_command; from pm.environments import project_python; print(json.dumps(runtime_command(Path(sys.argv[1]),code=sys.argv[2],python=project_python(Path(sys.argv[1])))))'
            args = json.loads(subprocess.check_output([str(python), '-I', '-c', resolver, str(SOURCE), args[2]], env=dict(env, HERMES_HOME=str(SOURCE.parent)), text=True))
        proc = subprocess.Popen(args, cwd=SOURCE, env=env, stdout=log, stderr=log)
        async with aiohttp.ClientSession() as probe:
            async with asyncio.timeout(40):
                while True:
                    if proc.poll() is not None:
                        raise AssertionError('Isolated Hermes exited; inspect local test log')
                    try:
                        async with probe.get(f'http://127.0.0.1:{port}/api/status') as res:
                            if res.status == 200:
                                break
                    except aiohttp.ClientError:
                        pass
                    await asyncio.sleep(.2)
        cfg = {'state_dir': str(tmp_path / 'bridge-state'), 'event_limit': 1000, 'run_event_limit': 500, 'event_days': 7, 'upload_limit': 1024 * 1024, 'artifact_limit': 2 * 1024 * 1024, 'backends': {'default': {'url': f'http://127.0.0.1:{port}', 'token': 'u' * 32, 'boards': ['default'], 'workspaces': {'test': str(work)}, 'artifact_roots': [str(work / '.hermes/desktop-attachments'), str(home / 'attachments')], 'bot_chat_control': True, 'bot_mode_management': True, 'bot_mode_roster': commit == '4bb9e57bfde8a0affb5553eff13ed6e1f14147f1', 'installed_commit': commit}}}
        app = create_app(cfg)
        service = app[SERVICE]
        _, token = service.store.token('integration', ['read', 'chat.control', 'tasks.manage', 'approvals.respond'], ['default'])
        bridge_runner, bp = await serve(app)
        client = aiohttp.ClientSession(headers={'Authorization': 'Bearer ' + token})
        await eventually(lambda: service.backends['default'].connected, timeout=20)
        async def request(method, path, body=None, expected=200):
            async with client.request(method, f'http://127.0.0.1:{bp}/mobile/v1' + path, json=body, headers={'Idempotency-Key': str(uuid.uuid4())}) as res:
                out = await res.json()
                assert res.status == expected, out
                return out
        # B2 is independent of Hermes and preserves the exact input bytes.
        capture_id = str(uuid.uuid4())
        capture_text = "  verbatim *capture*\n\nNo rewriting.\n"
        capture = await request('POST', '/captures', {'client_capture_id': capture_id, 'created_at': '2026-10-05T15:00:00Z', 'kind': 'note', 'text': capture_text}, 201)
        repeated = await request('POST', '/captures', {'client_capture_id': capture_id, 'created_at': '2026-10-05T15:00:00Z', 'kind': 'note', 'text': capture_text}, 201)
        assert capture == repeated
        assert next((tmp_path / 'bridge-state' / 'captures').rglob('*.md')).read_bytes() == capture_text.encode()
        if cfg['backends']['default']['bot_mode_roster']:
            bots = (await request('GET', '/bots'))['bots']
            assert {b['name'] for b in bots} == {'Hermes', 'Research Orchestrator', 'Research Worker'}
            created = (await request('POST', '/bots', {'name':'Mobile fixture bot','description':'Read-only integration fixture','soul':'Reply briefly. Do not run tools.'}, 201))['bot']
            assert created['name'] == 'Mobile fixture bot'
            assert sum(b['id'] == created['id'] for b in (await request('GET','/bots'))['bots']) == 1
            edited = (await request('PATCH','/bots/'+created['id'], {'name':'Edited fixture bot','description':'Edited fixture role','soul':'Keep this fixture isolated.'}))['bot']
            assert edited['id'] == created['id'] and edited['name'] == 'Edited fixture bot'
            assert edited['description'] == 'Edited fixture role' and edited['soul'] == 'Keep this fixture isolated.'
            new_chat = (await request('POST','/bots/'+created['id']+'/conversation',{}))['conversation']
            assert new_chat['read_only'] is False and new_chat['bot_profile'] == created['profile_id']
            assert (await request('POST','/bots/'+created['id']+'/conversation',{}))['conversation']['id'] == new_chat['id']
            await request('POST','/bots/'+created['id']+'/hide',{'hidden':True})
            assert not any(b['id'] == created['id'] for b in (await request('GET','/bots'))['bots'])
            assert service.store.get('conversations',new_chat['id'])['stored_id']
            await request('POST','/bots/'+created['id']+'/hide',{'hidden':False})
            assert (await request('GET','/bots/'+created['id']))['name'] == 'Edited fixture bot'
            # B1: two independent, persisted native-profile sessions, streamed
            # against the isolated real Hermes backend and local model fixture.
            for_thread = next(b for b in bots if b['name'] == 'Research Worker')
            first = await request('POST', '/bots/' + for_thread['id'] + '/conversations', {}, 201)
            second = await request('POST', '/bots/' + for_thread['id'] + '/conversations', {}, 201)
            assert first['id'] != second['id'] and first['is_bot_chat'] is False
            assert first['bot_id'] == second['bot_id'] == for_thread['id']
            listing = (await request('GET', '/conversations'))['conversations']
            assert {first['id'], second['id']} <= {c['id'] for c in listing}
            for independent in [first, second]:
                turn = await request('POST', '/conversations/' + independent['id'] + '/runs', {'text': 'Reply with a short safe greeting.'}, 202)
                await eventually(lambda: service.store.get('runs', turn['id'])['state'] in {'complete','failed'}, timeout=30)
                assert service.store.get('runs', turn['id'])['state'] == 'complete'
                assert (await request('GET', '/conversations/' + independent['id']))['messages']
            bot = next(b for b in bots if b['name'] == 'Research Orchestrator')
            detail = await request('GET', '/bots/' + bot['id'])
            assert {v['name'] for v in detail['skills']} == set(SKILLS)
            # Real Desktop lifecycle: absent -> hidden eager-title -> native-profile resume.
            canonical = {}
            for bot in bots:
                chat, concurrent = await asyncio.gather(request('POST', '/bots/' + bot['id'] + '/conversation', {}), request('POST', '/bots/' + bot['id'] + '/conversation', {}))
                assert concurrent['conversation']['id'] == chat['conversation']['id']
                assert chat['messages'] == []
                conv = chat['conversation']
                assert conv['read_only'] is False and conv['canonical'] is True
                assert conv['bot_profile'] == bot['profile_id'] and conv['profile'] == bot['id']
                again = await request('POST', '/bots/' + bot['id'] + '/conversation', {})
                assert again['conversation']['id'] == conv['id']
                canonical[bot['profile_id']] = conv
            for name, expected_model in [('default', 'bridge-local-test'), ('research-worker', 'bridge-research-worker-test')]:
                start = len(model.calls)
                bc = canonical[name]
                test_run = await request('POST', f"/conversations/{bc['id']}/runs", {'text': 'Safely identify the configured fixture bot.'}, 202)
                await eventually(lambda: service.store.get('runs', test_run['id'])['state'] in {'complete', 'failed'}, timeout=30)
                assert service.store.get('runs', test_run['id'])['state'] == 'complete'
                assert model.calls[start]['model'] == expected_model
                if name == 'research-worker':
                    assert 'ISOLATED_RESEARCH_WORKER_CONTEXT_MARKER' in json.dumps(model.calls[start]['messages'])
            oc = canonical['research-orchestrator']
            before = len(model.calls)
            br = await request('POST', f"/conversations/{oc['id']}/runs", {'text': 'Safely identify the configured fixture profile.'}, 202)
            await eventually(lambda: service.store.get('runs', br['id'])['state'] in {'complete', 'failed'}, timeout=40)
            assert (await request('GET', '/runs/' + br['id']))['state'] == 'complete'
            call = model.calls[before]
            assert call['model'] == 'bridge-research-orchestrator-test'
            context = json.dumps(call['messages'])
            assert 'ISOLATED_RESEARCH_ORCHESTRATOR_CONTEXT_MARKER' in context
            assert 'ISOLATED_RESEARCH_WORKER_CONTEXT_MARKER' not in context
            assert 'research-terminal' in context
            native = service.store.get('conversations', oc['id'])
            resumed = await service.backends['default'].rpc('session.resume', {'session_id': native['stored_id'], 'profile': 'research-orchestrator', 'omit_messages': True})
            assert resumed['info']['profile_name'] == 'research-orchestrator'
            assert resumed['info']['model'] == 'bridge-research-orchestrator-test'
            assert resumed['info']['provider'] == 'custom'
            listed = (await request('GET', '/conversations'))['conversations']
            assert len([x for x in listed if x['id'] == oc['id']]) == 1
            history = await request('GET', '/conversations/' + oc['id'])
            assert any(m['role'] == 'assistant' for m in history['messages'])
            qr = await request('POST', f"/conversations/{oc['id']}/runs", {'text': 'exercise-clarify'}, 202)
            await eventually(lambda: service.store.get('runs', qr['id'])['state'] == 'waiting_for_input', timeout=30)
            # Drop/reconnect transport while both exact questions remain open.
            generation = service.backends['default'].generation
            await service.backends['default'].ws.close()
            await eventually(lambda: service.backends['default'].connected and service.backends['default'].generation > generation, timeout=20)
            await eventually(lambda: service.store.get('runs', qr['id'])['state'] == 'waiting_for_input', timeout=10)
            prompts = [x for x in (await request('GET', '/attention'))['items'] if x['run_id'] == qr['id'] and x['can_respond']]
            assert len(prompts) == 2, {'run': service.store.get('runs', qr['id']), 'attention': (await request('GET', '/attention')), 'active': await service.backends['default'].rpc('session.active_list')}
            for prompt in prompts:
                await request('POST', '/attention/' + prompt['id'] + '/respond', {'answer': 'Proceed'})
            await eventually(lambda: service.store.get('runs', qr['id'])['state'] in {'complete', 'failed'}, timeout=30)
            assert service.store.get('runs', qr['id'])['state'] == 'complete'
            # The same bot conversation exercises ordinary stream/tool/stop/steer paths.
            bt = await request('POST', f"/conversations/{oc['id']}/runs", {'text': 'exercise-safe-tool'}, 202)
            await eventually(lambda: service.store.db.execute("SELECT COUNT(*) FROM events WHERE run_id=? AND type='tool.started'", (bt['id'],)).fetchone()[0] > 0, timeout=40)
            assert (await request('POST', '/runs/' + bt['id'] + '/steer', {'text': 'bot-steer-evidence'}))['status'] == 'queued'
            assert (await request('POST', '/runs/' + bt['id'] + '/stop', {}))['acknowledged']
            await eventually(lambda: service.store.get('runs', bt['id'])['state'] in {'cancelled', 'failed'}, timeout=30)
            assert service.store.get('runs', bt['id'])['state'] == 'cancelled'
        c = await request('POST', '/conversations', {'title': 'Local integration', 'workspace': 'test'}, 201)
        r = await request('POST', f"/conversations/{c['id']}/runs", {'text': 'Say hello using the local model.'}, 202)
        await eventually(lambda: service.store.get('runs', r['id'])['state'] in {'complete', 'failed'}, timeout=40)
        finished = await request('GET', f"/runs/{r['id']}")
        assert finished['state'] == 'complete', finished
        assert finished['assistant_text'] == 'Reply from isolated local model.'
        transcript = await request('GET', f"/conversations/{c['id']}")
        assert any(m.get('role') == 'assistant' for m in transcript['messages'])
        await request('PATCH', f"/conversations/{c['id']}", {'title': 'Renamed integration'})
        assert (await request('GET', '/conversations?q=local'))['conversations']
        assert (await request('GET', f"/conversations/{c['id']}/usage"))['tokens']['total'] > 0
        uploaded = await request('POST', '/attachments', {'conversation_id': c['id'], 'name': 'evidence.txt', 'content_type': 'text/plain', 'content_base64': 'TG9jYWwgZXZpZGVuY2U='}, 201)
        assert uploaded['staged'] and uploaded['artifact']
        attached_run = await request('POST', f"/conversations/{c['id']}/runs", {'text':'Inspect the local evidence file.', 'attachment_ids':[uploaded['upload_id']]}, 202)
        await eventually(lambda: service.store.get('runs', attached_run['id'])['state'] in {'complete','failed'}, timeout=40)
        assert service.store.get('runs', attached_run['id'])['state'] == 'complete'
        job = await request('POST', '/cron', {'prompt': 'Local future work', 'schedule': 'every 1h', 'name': 'isolated-job'}, 201)
        await request('POST', f"/cron/{job['id']}/disable", {})
        await request('PATCH', f"/cron/{job['id']}", {'name': 'edited-job'})
        assert not (await request('GET', f"/cron/{job['id']}"))['job']['enabled']
        await request('POST', f"/cron/{job['id']}/enable", {})
        trigger = await request('POST', f"/cron/{job['id']}/run-now", {})
        assert trigger['scheduler_required'] and not trigger['execution_started']
        await request('DELETE', f"/cron/{job['id']}", {})
        caps = await request('GET', '/capabilities')
        if caps['profiles']['default']['features']['kanban']:
            card = await request('POST', '/kanban/tasks', {'title': 'Local card', 'triage': True}, 201)
            await request('PATCH', f"/kanban/tasks/{card['id']}", {'status': 'todo', 'body': 'Test dependency'})
            assert (await request('GET', f"/kanban/tasks/{card['id']}"))['task']['body'] == 'Test dependency'
            child = await request('POST', '/kanban/tasks', {'title': 'Dependent card', 'parents': [card['id']], 'workspace': 'test'}, 201)
            child_detail = await request('GET', f"/kanban/tasks/{child['id']}")
            assert child_detail['links']['parents'] == [card['id']]
            await request('PATCH', f"/kanban/tasks/{card['id']}", {'assignee': 'default'})
            await request('PATCH', f"/kanban/tasks/{card['id']}", {'status': 'ready'})
            # Seed an actual canonical claim/heartbeat through upstream helpers,
            # without running a dispatcher or spawning a Kanban agent worker.
            script = "from hermes_cli import kanban_db as kb; c=kb.connect(board='default'); assert kb.claim_task(c," + repr(card['upstream_id']) + ",claimer='bridge-integration'); assert kb.heartbeat_worker(c," + repr(card['upstream_id']) + ",note='integration'); c.close()"
            seed_args = [str(python), '-c', script]
            if cfg['backends']['default']['bot_mode_roster']:
                script = script.replace('from hermes_cli import kanban_db as kb;', 'from hermes_cli import kanban_db as kb; from hermes_cli.kanban_db_connect import connect; from hermes_cli.kanban_db_dispatch import heartbeat_worker;').replace('kb.connect(', 'connect(').replace('kb.heartbeat_worker(', 'heartbeat_worker(')
                seed_args = json.loads(subprocess.check_output([str(python), '-I', '-c', resolver, str(SOURCE), script], env=dict(env, HERMES_HOME=str(SOURCE.parent)), text=True))
            seeded = await asyncio.to_thread(subprocess.run, seed_args, cwd=SOURCE, env=env, capture_output=True, timeout=30)
            assert seeded.returncode == 0, 'Canonical claim/heartbeat setup failed'
            claimed = await request('GET', f"/kanban/tasks/{card['id']}")
            assert claimed['task']['raw_state'] == 'running'
            assert claimed['attempts'][0]['last_heartbeat_at']
            await request('POST', f"/kanban/tasks/{card['id']}/reclaim", {'reason': 'isolated integration'})
            reclaimed = await request('GET', f"/kanban/tasks/{card['id']}")
            assert reclaimed['task']['raw_state'] == 'ready'
            assert reclaimed['attempts'][0]['outcome'] == 'reclaimed'
            if cfg['backends']['default']['bot_mode_roster']:
                review_code = "from hermes_cli import kanban_db as kb; from hermes_cli.kanban_db_connect import connect; c=connect(board='default'); assert kb.request_review(c," + repr(card['upstream_id']) + ",summary='Review local evidence',force=True); c.close()"
                review_args = json.loads(subprocess.check_output([str(python), '-I', '-c', resolver, str(SOURCE), review_code], env=dict(env, HERMES_HOME=str(SOURCE.parent)), text=True))
                seeded_review = await asyncio.to_thread(subprocess.run, review_args, cwd=SOURCE, env=env, capture_output=True, timeout=30)
                assert seeded_review.returncode == 0, 'Canonical review setup failed'
                review_detail = await request('GET', f"/kanban/tasks/{card['id']}")
                assert {'done','ready','todo'} <= set(review_detail['supported_targets'])
                listed = await request('GET', '/kanban/tasks')
                assert 'done' in next(x for x in listed['tasks'] if x['id'] == card['id'])['supported_targets']
                await request('PATCH', f"/kanban/tasks/{card['id']}", {'status':'ready','summary':'Revise local evidence'})
                assert any(x['body'] == 'Revise local evidence' for x in (await request('GET', f"/kanban/tasks/{card['id']}"))['comments'])
                seeded_review = await asyncio.to_thread(subprocess.run, review_args, cwd=SOURCE, env=env, capture_output=True, timeout=30)
                assert seeded_review.returncode == 0
                await request('PATCH', f"/kanban/tasks/{card['id']}", {'status':'done','summary':'Evidence checked on Talaria'})
                assert (await request('GET', f"/kanban/tasks/{card['id']}"))['task']['raw_state'] == 'done'
            await request('POST', f"/kanban/tasks/{card['id']}/reassign", {'profile': ''})
            await request('DELETE', f"/kanban/tasks/{child['id']}", {})
            await request('DELETE', f"/kanban/tasks/{card['id']}", {})
        # Fresh conversation ensures this request actually executes a tool.
        tc = await request('POST', '/conversations', {'title': 'Tool integration', 'workspace': 'test'}, 201)
        tr = await request('POST', f"/conversations/{tc['id']}/runs", {'text': 'exercise-tool'}, 202)
        def tool_started():
            return service.store.db.execute("SELECT COUNT(*) FROM events WHERE run_id=? AND type='tool.started'", (tr['id'],)).fetchone()[0] > 0
        await eventually(tool_started, timeout=40)
        ack = await request('POST', f"/runs/{tr['id']}/steer", {'text': 'change direction after the tool'})
        assert ack['status'] == 'queued'
        stop = await request('POST', f"/runs/{tr['id']}/stop", {})
        assert stop['acknowledged'] and not stop['termination_confirmed']
        await eventually(lambda: service.store.get('runs', tr['id'])['state'] in {'cancelled', 'failed'}, timeout=30)
        assert (await request('GET', f"/runs/{tr['id']}"))['state'] == 'cancelled'
        sc = await request('POST', '/conversations', {'title': 'Steering integration', 'workspace': 'test'}, 201)
        sr = await request('POST', f"/conversations/{sc['id']}/runs", {'text': 'exercise-safe-tool'}, 202)
        await eventually(lambda: service.store.db.execute("SELECT COUNT(*) FROM events WHERE run_id=? AND type='tool.started'", (sr['id'],)).fetchone()[0] > 0, timeout=40)
        await request('POST', f"/runs/{sr['id']}/steer", {'text': 'steering-consumption-evidence'})
        await eventually(lambda: service.store.get('runs', sr['id'])['state'] in {'complete', 'failed'}, timeout=30)
        assert service.store.get('runs', sr['id'])['state'] == 'complete'
        assert any('steering-consumption-evidence' in json.dumps(call['messages']) for call in model.calls)
        # Restart the bridge against the still-live installed backend and the
        # same journal. Phone bearer and completed run IDs remain valid.
        await client.close()
        await bridge_runner.cleanup()
        app = create_app(cfg)
        service = app[SERVICE]
        bridge_runner, bp = await serve(app)
        client = aiohttp.ClientSession(headers={'Authorization': 'Bearer ' + token})
        await eventually(lambda: service.backends['default'].connected, timeout=20)
        assert (await request('GET', f"/runs/{r['id']}"))['state'] == 'complete'
        if cfg['backends']['default']['bot_mode_roster']:
            restored = await request('POST', '/bots/' + next(b['id'] for b in bots if b['profile_id'] == 'research-orchestrator') + '/conversation', {})
            assert restored['conversation']['id'] == oc['id']
            assert any(m['role'] == 'assistant' for m in restored['messages'])
        # Real Hermes process restart during a controlled tool execution.
        rc = await request('POST', '/conversations', {'title': 'Restart integration', 'workspace': 'test'}, 201)
        rr = await request('POST', f"/conversations/{rc['id']}/runs", {'text': 'exercise-safe-tool'}, 202)
        await eventually(lambda: service.store.db.execute("SELECT COUNT(*) FROM events WHERE run_id=? AND type='tool.started'", (rr['id'],)).fetchone()[0] > 0, timeout=40)
        before_restart = len(model.calls)
        generation = service.backends['default'].generation
        proc.kill()  # simulate abrupt Hermes loss, rather than waiting for uvicorn drain
        await asyncio.to_thread(proc.wait, 5)
        await eventually(lambda: service.store.get('runs', rr['id'])['state'] == 'unknown')
        args = [str(python), '-c', f'from hermes_cli.web_server import start_server; start_server(port={port}, open_browser=False)']
        if commit == '4bb9e57bfde8a0affb5553eff13ed6e1f14147f1':
            resolver = 'import sys,json; from pathlib import Path; sys.path.insert(0,sys.argv[1]); from hermes_cli._launchers import runtime_command; from pm.environments import project_python; print(json.dumps(runtime_command(Path(sys.argv[1]),code=sys.argv[2],python=project_python(Path(sys.argv[1])))))'
            args = json.loads(subprocess.check_output([str(python), '-I', '-c', resolver, str(SOURCE), args[2]], env=dict(env, HERMES_HOME=str(SOURCE.parent)), text=True))
        proc = subprocess.Popen(args, cwd=SOURCE, env=env, stdout=log, stderr=log)
        await eventually(lambda: service.backends['default'].connected and service.backends['default'].generation > generation, timeout=30)
        assert (await request('GET', f"/runs/{rr['id']}"))['state'] == 'unknown'
        assert len(model.calls) == before_restart
        if cfg['backends']['default']['bot_mode_roster']:
            cold = await request('POST', '/bots/' + next(b['id'] for b in bots if b['profile_id'] == 'research-orchestrator') + '/conversation', {})
            assert cold['conversation']['id'] == oc['id']
            assert any(m['role'] == 'assistant' for m in cold['messages'])
            first = len(model.calls)
            cold_run = await request('POST', f"/conversations/{oc['id']}/runs", {'text': 'Safely verify your profile after a cold backend restart.'}, 202)
            await eventually(lambda: service.store.get('runs', cold_run['id'])['state'] in {'complete', 'failed'}, timeout=30)
            assert service.store.get('runs', cold_run['id'])['state'] == 'complete'
            assert model.calls[first]['model'] == 'bridge-research-orchestrator-test'
            assert 'ISOLATED_RESEARCH_ORCHESTRATOR_CONTEXT_MARKER' in json.dumps(model.calls[first]['messages'])
            assert 'research-terminal' in json.dumps(model.calls[first]['messages'])
        home_result = await request('GET', '/home')
        assert home_result['recent_completions']
        await request('DELETE', f"/conversations/{c['id']}", {})
        print(json.dumps({'bot_mode_roster': commit == '4bb9e57bfde8a0affb5553eff13ed6e1f14147f1', 'installed_commit': commit, 'model_requests': len(model.calls), 'kanban_mounted': caps['profiles']['default']['features']['kanban'], 'final_state': finished['state'], 'tool_stop_state': 'cancelled'}))
    finally:
        if client:
            await client.close()
        if bridge_runner:
            await bridge_runner.cleanup()
        if proc and proc.poll() is None:
            proc.terminate()
            try:
                await asyncio.to_thread(proc.wait, 8)
            except subprocess.TimeoutExpired:
                proc.kill()
                await asyncio.to_thread(proc.wait)
        log.close()
        await model_runner.cleanup()
