import asyncio
import uuid
from pathlib import Path
import aiohttp
from aiohttp import web
import pytest_asyncio
from hermes_mobile_bridge.api import create_app, SERVICE


async def eventually(fn, timeout=6):
    async with asyncio.timeout(timeout):
        while not fn():
            await asyncio.sleep(.02)


async def serve(app, port=0):
    runner = web.AppRunner(app, access_log=None, shutdown_timeout=.1)
    await runner.setup()
    site = web.TCPSite(runner, '127.0.0.1', port)
    await site.start()
    return runner, site._server.sockets[0].getsockname()[1]


class FakeHermes:
    def __init__(self, root):
        self.root = root
        root.mkdir()
        self.sessions, self.jobs, self.cards = {}, {}, {}
        self.ws, self.prompts, self.approval_calls, self.methods = None, 0, 0, []
        self.drop_prompt_reply = False
        self.bot_roster = []
        self.bot_details = {}
        self.requests, self.questions = [], {}
        self.fail_registry = self.fail_title = self.wrong_profile = False
        self.create_keys = {}
        self.app = web.Application()
        self.app.router.add_get('/api/ws', self.socket)
        self.app.router.add_route('*', '/{path:.*}', self.rest)

    async def emit(self, sid, kind, payload=None):
        await self.ws.send_json({'jsonrpc': '2.0', 'method': 'event', 'params': {'type': kind, 'session_id': sid, 'payload': payload or {}}})

    async def socket(self, request):
        if request.query.get('token') != 'u' * 32:
            raise web.HTTPUnauthorized()
        ws = web.WebSocketResponse()
        await ws.prepare(request)
        self.ws = ws
        async for msg in ws:
            if msg.type != 1:
                continue
            req = msg.json()
            if 'method' not in req:
                continue
            method, p, result, error = req['method'], req['params'], {}, None
            self.methods.append(method)
            self.requests.append((method, dict(p)))
            if method == 'profiles.list':
                result = {'profiles': self.bot_roster, 'bot_mode_protocol': True}
            elif method == 'profiles.describe':
                result = self.bot_details.get(p['name'], {})
            elif method == 'profiles.get_asset':
                result = {'found': False}
            elif method == 'session.list':
                row = next((x for x in self.bot_roster if x['name'] == p.get('profile')), {})
                result = {'sessions': [row['canonical_session']] if row.get('canonical_session') else []}
                if self.fail_registry:
                    error = {'code': -32000, 'message': 'registry unavailable'}
            elif method == 'session.active_list':
                result = {'sessions': [{'id': sid, 'session_key': x['stored'], 'status': x['status']} for sid, x in self.sessions.items()]}
            elif method == 'session.create':
                sid, stored = self.create_keys.get(p.get('idempotency_key'), (uuid.uuid4().hex[:8], uuid.uuid4().hex))
                if p.get('idempotency_key'):
                    self.create_keys[p['idempotency_key']] = (sid, stored)
                self.sessions.setdefault(sid, {'stored': stored, 'status': 'idle', 'title': p.get('title', ''), 'messages': [], 'profile': p.get('profile', 'default'), 'hidden': p.get('hidden', False), 'follow_profile_config': p.get('follow_profile_config', False)})
                result = {'session_id': sid, 'stored_session_id': stored, 'info': {'model': 'test', 'desktop_contract': 2}}
            elif method == 'session.title':
                x = self.sessions[p['session_id']]
                row = next((r for r in self.bot_roster if r['name'] == self.profile_of(x)), None)
                if self.fail_title:
                    error = {'code': -32000, 'message': 'title write unavailable'}
                elif row and row.get('canonical_session') and row['canonical_session']['id'] != x['stored']:
                    error = {'code': 4022, 'message': 'title taken'}
                else:
                    x['title'] = p['title']
                    if row:
                        row['canonical_session'] = {'id': x['stored'], 'resolved_id': x['stored'], 'title': p['title']}
                    result = {'ok': True, 'title': p['title']}
            elif method == 'client.capabilities':
                result = {'server_requests': ['clarify', 'approval', 'terminal.read'], 'declines_not_shown': True}
            elif method == 'clarify.lock':
                questions = self.questions.get(p['request_id'])
                if questions is None or p['question_id'] not in questions:
                    result = {'status': 'expired'}
                else:
                    questions.pop(p['question_id'])
                    result = {'status': 'ok', 'remaining': list(questions)}
                    if not questions:
                        self.questions.pop(p['request_id'])
            elif method == 'session.resume':
                match = next(((sid, x) for sid, x in self.sessions.items() if x['stored'] == p['session_id'] and (not p.get('profile') or self.profile_of(x) == p['profile'])), None)
                if not match:
                    error = {'code': 4007, 'message': 'not found'}
                else:
                    sid, x = match
                    result = {'session_id': sid, 'session_key': x['stored'], 'running': x['status'] in {'working', 'starting', 'waiting'}, 'status': x['status'], 'info': {'profile_name': 'wrong' if self.wrong_profile else self.profile_of(x), 'model': next((r.get('model') for r in self.bot_roster if r['name'] == self.profile_of(x)), 'test'), 'provider': next((r.get('provider') for r in self.bot_roster if r['name'] == self.profile_of(x)), 'custom')}, 'inflight': {'assistant': 'partial'}, 'open_requests': x.get('open_requests', [])}
            elif method == 'prompt.submit':
                self.prompts += 1
                self.sessions[p['session_id']]['status'] = 'working'
                result = {'status': 'streaming'}
                if self.drop_prompt_reply:
                    self.drop_prompt_reply = False
                    await ws.close()
                    break
            elif method == 'session.interrupt':
                result = {'status': 'interrupted'}
            elif method == 'session.steer':
                result = {'status': 'queued'}
            elif method == 'session.usage':
                result = {'input': 10, 'output': 5, 'total': 15}
            elif method == 'clarify.respond':
                result = {'status': 'ok'}
            elif method == 'approval.respond':
                self.approval_calls += 1
                result = {'resolved': True}
            elif method == 'session.close':
                self.sessions.pop(p['session_id'], None)
                result = {'closed': True}
            elif method == 'session.delete':
                result = {'deleted': p['session_id']}
            elif method in {'image.attach_bytes', 'pdf.attach'}:
                import base64
                path = self.root / ('upload-' + uuid.uuid4().hex)
                path.write_bytes(base64.b64decode(p['content_base64']))
                result = {'path':str(path),'count':1,'bytes':path.stat().st_size}
            elif method == 'file.attach':
                import base64
                path = self.root / p['name']
                path.write_bytes(base64.b64decode(p['data_url'].split(',')[1]))
                result = {'uploaded': True, 'path': str(path), 'ref_text': '@file:' + str(path)}
            else:
                error = {'code': -32601, 'message': 'not supported'}
            await ws.send_json({'jsonrpc': '2.0', 'id': req['id'], **({'error': error} if error else {'result': result})})
        return ws

    def profile_of(self, session):
        if 'profile' in session:
            return session['profile']
        return next((r['name'] for r in self.bot_roster if session['stored'] in {(r.get('canonical_session') or {}).get('id'), (r.get('canonical_session') or {}).get('resolved_id')}), 'default')

    async def rest(self, request):
        path, method = request.path, request.method
        if path == '/openapi.json':
            return web.json_response({'paths': {x: {} for x in ['/api/sessions', '/api/cron/jobs', '/api/plugins/kanban/board', '/api/analytics/usage', '/api/skills', '/api/tools/toolsets', '/api/mcp/servers']}})
        if request.headers.get('Authorization') != 'Bearer ' + 'u' * 32:
            raise web.HTTPUnauthorized()
        if path == '/api/sessions':
            rows = [{'id': x['stored'], 'title': x['title'], 'message_count': len(x['messages'])} for x in self.sessions.values() if self.profile_of(x) == request.query.get('profile', 'default') and not x.get('hidden')]
            return web.json_response({'sessions': rows, 'total': len(rows)})
        if path == '/api/sessions/search':
            return web.json_response({'results': [{'session_id': x['stored'], 'title': x['title'], 'snippet': 'found'} for x in self.sessions.values()]})
        if path.startswith('/api/sessions/'):
            sid = path.split('/')[3]
            row = next((x for x in self.sessions.values() if x['stored'] == sid and self.profile_of(x) == request.query.get('profile', 'default')), None)
            if not row:
                raise web.HTTPNotFound()
            if path.endswith('/messages'):
                return web.json_response({'session_id': sid, 'messages': row['messages']})
            if method == 'PATCH':
                row.update(await request.json())
                return web.json_response({'ok': True, 'title': row['title']})
            return web.json_response({'id': sid, 'title': row['title'], 'api_key': 'must-never-leak'})
        inventory = {
            '/api/model/info': {'model': 'test', 'provider': 'custom', 'capabilities': {}},
            '/api/model/options': {'providers': [{'slug': 'test', 'name': 'Test', 'api_key': 'secret', 'base_url': 'secret', 'models': [{'id': 'test', 'api_key': 'secret'}]}]},
            '/api/profiles': {'profiles': [{'name': 'default', 'description': 'Test', 'skill_count': 0}]},
            '/api/skills': [{'name': 'test', 'enabled': True, 'path': '/hidden/path'}],
            '/api/tools/toolsets': [{'name': 'terminal', 'enabled': True, 'tools': ['terminal']}],
            '/api/mcp/servers': {'servers': [{'name': 'test', 'enabled': True, 'command': 'secret', 'env': {'TOKEN': 'secret'}}]},
            '/api/analytics/usage': {'totals': {'input_tokens': 15}},
            '/api/status': {'version': 'test', 'gateway_running': True},
            '/api/system/stats': {'hostname': 'test', 'memory': {}},
            '/api/memory': {'active': 'builtin', 'builtin_files': {}},
        }
        if path.endswith('/soul'):
            return web.json_response({'exists': True, 'content': 'Local SOUL'})
        if path in inventory:
            return web.json_response(inventory[path])
        if path == '/api/cron/jobs':
            if method == 'GET':
                return web.json_response(list(self.jobs.values()))
            job = {'id': uuid.uuid4().hex[:8], 'enabled': True, **await request.json()}
            self.jobs[job['id']] = job
            return web.json_response(job)
        if path.startswith('/api/cron/jobs/'):
            jid = path.split('/')[4]
            if jid not in self.jobs:
                raise web.HTTPNotFound()
            if path.endswith('/runs'):
                return web.json_response({'runs': []})
            if method == 'PUT':
                self.jobs[jid].update((await request.json())['updates'])
            if path.endswith('/pause'):
                self.jobs[jid]['enabled'] = False
            if path.endswith('/resume'):
                self.jobs[jid]['enabled'] = True
            if path.endswith('/trigger'):
                self.jobs[jid]['next_run_at'] = 'now'
            if method == 'DELETE':
                self.jobs.pop(jid)
                return web.json_response({'ok': True})
            return web.json_response(self.jobs[jid])
        if path == '/api/plugins/kanban/board':
            return web.json_response({'columns': [{'name': 'todo', 'tasks': list(self.cards.values())}]})
        if path == '/api/plugins/kanban/workers/active':
            return web.json_response({'workers': [], 'checked_at': 1})
        if path == '/api/plugins/kanban/tasks' and method == 'POST':
            row = {'id': 't_' + uuid.uuid4().hex[:8], 'status': 'todo', **await request.json()}
            self.cards[row['id']] = row
            return web.json_response({'task': row})
        if path.startswith('/api/plugins/kanban/tasks/'):
            tid = path.split('/')[5]
            if tid not in self.cards:
                raise web.HTTPNotFound()
            if method == 'PATCH':
                self.cards[tid].update(await request.json())
                return web.json_response({'ok': True})
            if method == 'DELETE':
                self.cards.pop(tid)
                return web.json_response({'ok': True})
            return web.json_response({'task': self.cards[tid], 'runs': [], 'comments': [], 'links': {'parents': [], 'children': []}, 'attachments': []})
        raise web.HTTPNotFound()


class Harness:
    def __init__(self, tmp):
        self.fake = FakeHermes(tmp / 'artifacts')
        self.cfg = {'state_dir': str(tmp / 'state'), 'event_limit': 1000, 'run_event_limit': 100, 'event_days': 7, 'upload_limit': 1024 * 1024, 'artifact_limit': 2 * 1024 * 1024}
        self.token = None

    async def start(self):
        self.upstream_runner, self.upstream_port = await serve(self.fake.app)
        self.cfg['backends'] = {'default': {'url': f'http://127.0.0.1:{self.upstream_port}', 'token': 'u' * 32, 'boards': ['default'], 'workspaces': {}, 'artifact_roots': [str(self.fake.root)]}}
        await self.start_bridge()

    async def start_bridge(self):
        self.app = create_app(self.cfg)
        self.service = self.app[SERVICE]
        if not self.token:
            self.credential, self.token = self.service.store.token('test', ['read', 'chat.control', 'tasks.manage', 'approvals.respond'], ['default'])
        self.bridge_runner, self.port = await serve(self.app)
        self.client = aiohttp.ClientSession(headers={'Authorization': 'Bearer ' + self.token})
        await eventually(lambda: self.service.backends['default'].connected)

    async def request(self, method, path, body=None, key=None, expected=200):
        headers = {'Idempotency-Key': key or str(uuid.uuid4())} if method != 'GET' else {}
        async with self.client.request(method, f'http://127.0.0.1:{self.port}/mobile/v1' + path, json=body if method != 'GET' else None, headers=headers) as res:
            data = await res.json()
            assert res.status == expected, data
            return data

    async def start_run(self):
        c = await self.request('POST', '/conversations', {'title': 'test'}, expected=201)
        r = await self.request('POST', f"/conversations/{c['id']}/runs", {'text': 'hello'}, expected=202)
        sid = self.service.store.get('runs', r['id'])['live_id']
        await self.fake.emit(sid, 'message.start')
        await eventually(lambda: self.service.store.get('runs', r['id'])['state'] == 'running')
        return c, r, sid

    async def close(self):
        await self.client.close()
        await self.bridge_runner.cleanup()
        await self.upstream_runner.cleanup()


@pytest_asyncio.fixture
async def harness(tmp_path):
    h = Harness(tmp_path)
    await h.start()
    try:
        yield h
    finally:
        await h.close()
