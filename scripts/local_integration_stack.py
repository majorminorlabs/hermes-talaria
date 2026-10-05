"""Disposable installed-Hermes/bridge stack for simulator integration tests.
No production homes/keys are inherited. Private fixture JSON is the only token
handoff to hosted Swift tests. The auxiliary control API is test-only loopback.
"""
import asyncio
import json
import os
from pathlib import Path
import signal
import socket
import subprocess
import sys
import uuid
import aiohttp
from aiohttp import web
from hermes_mobile_bridge.store import Store

SOURCE = Path(os.environ.get('HERMES_SOURCE', str(Path.home()/'.hermes/hermes-agent')))
ROOT = Path(__file__).resolve().parents[1]

def free_port():
    with socket.socket() as s:
        s.bind(('127.0.0.1', 0))
        return s.getsockname()[1]

class Stack:
    def __init__(self, directory):
        self.directory = directory.resolve(); self.directory.mkdir(mode=0o700, parents=True, exist_ok=True)
        self.home = self.directory / 'home'; self.home.mkdir(mode=0o700, exist_ok=True)
        self.work = self.directory / 'work'; self.work.mkdir(exist_ok=True)
        self.hp, self.bp, self.mp, self.cp = [free_port() for _ in range(4)]
        self.token = None; self.hermes = None; self.bridge = None
        self.calls = []; self.runners = []
        self.env = {k:v for k,v in os.environ.items() if not any(x in k.upper() for x in ('API_KEY','TOKEN','SECRET','HERMES_','ANTHROPIC_','OPENAI_','OPENROUTER_','NOUS_')) and k not in {'PYTHONPATH','PYTHONHOME'}}
        self.env.update(HERMES_HOME=str(self.home),HERMES_DASHBOARD_SESSION_TOKEN='isolated-dashboard-'+'u'*32,HERMES_TUI_TOOLSETS='terminal,file',PYTHONUNBUFFERED='1')
        self.logs = []

    def launch(self, which):
        f = open(self.directory / (which+'.log'), 'a'); self.logs.append(f)
        if which == 'hermes':
            args = [str(SOURCE/'venv/bin/python'),'-c',f'from hermes_cli.web_server import start_server; start_server(port={self.hp}, open_browser=False)']
            self.hermes = subprocess.Popen(args,cwd=SOURCE,env=self.env,stdout=f,stderr=f)
        else:
            args=[str(ROOT/'hermes-mobile-bridge/.venv/bin/hermes-mobile-bridge'),'--config',str(self.directory/'bridge.json'),'serve']
            self.bridge = subprocess.Popen(args,cwd=ROOT,env=self.env,stdout=f,stderr=f)

    async def model(self, request):
        body=await request.json(); self.calls.append(body)
        messages=body['messages']; user=next((str(m.get('content','')) for m in reversed(messages) if m.get('role')=='user'),'')
        tool = 'exercise-safe-tool' in user and not any(m.get('role')=='tool' for m in messages)
        payload={'role':'assistant','content':'Local Studio stream complete.'}
        if tool:
            payload={'role':'assistant','content':None,'tool_calls':[{'id':'call_safe','type':'function','function':{'name':'terminal','arguments':json.dumps({'command':'sleep 6','timeout':10})}}]}
        finish='tool_calls' if tool else 'stop'
        if not body.get('stream'):
            return web.json_response({'id':'local','object':'chat.completion','model':'bridge-local-test','choices':[{'index':0,'message':payload,'finish_reason':finish}], 'usage':{'prompt_tokens':20,'completion_tokens':8,'total_tokens':28}})
        response=web.StreamResponse(headers={'Content-Type':'text/event-stream'}); await response.prepare(request)
        deltas=[{'tool_calls':[{**payload['tool_calls'][0],'index':0}]}] if tool else [{'content':s} for s in ['Local ','Studio ','stream ','complete.']]
        try:
            for delta in deltas:
                await response.write(('data: '+json.dumps({'id':'local','object':'chat.completion.chunk','model':'bridge-local-test','choices':[{'index':0,'delta':delta,'finish_reason':None}]})+'\n\n').encode())
                await asyncio.sleep(.35)
            await response.write(('data: '+json.dumps({'id':'local','object':'chat.completion.chunk','model':'bridge-local-test','choices':[{'index':0,'delta':{},'finish_reason':finish}], 'usage':{'prompt_tokens':20,'completion_tokens':8,'total_tokens':28}})+'\n\n').encode())
            await response.write(b'data: [DONE]\n\n')
        except ConnectionError: pass
        return response

    async def control(self, request):
        if request.headers.get('Authorization') != 'Bearer '+self.token: raise web.HTTPUnauthorized()
        name=request.match_info.get('which')
        if name:
            p=self.hermes if name=='hermes' else self.bridge
            p.kill(); await asyncio.to_thread(p.wait,5)
            # Give the bridge observer a chance to mark lost Hermes outcomes unknown.
            await asyncio.sleep(.6)
            self.launch(name)
            return web.json_response({'restarted':name})
        return web.json_response({'model_requests':len(self.calls),'steering_consumed':any('safe-steering-evidence' in json.dumps(c['messages']) for c in self.calls), 'commit':subprocess.check_output(['git','rev-parse','HEAD'],cwd=SOURCE,text=True).strip()})

    async def start(self):
        commit=subprocess.check_output(['git','rev-parse','HEAD'],cwd=SOURCE,text=True).strip(); assert commit.startswith('2a4c9afd7bd')
        (self.home/'config.yaml').write_text(f'''model:
  default: bridge-local-test
  provider: custom
  base_url: http://127.0.0.1:{self.mp}/v1
  api_key: isolated-test-only
  api_mode: chat_completions
agent:
  max_turns: 4
  reasoning_effort: none
toolsets: [terminal, file]
display:
  tool_progress: all
terminal:
  backend: local
  cwd: {self.work}
memory:
  memory_enabled: false
  user_profile_enabled: false
''')
        token_file=self.directory/'upstream-token';token_file.write_text(self.env['HERMES_DASHBOARD_SESSION_TOKEN'])
        state=self.directory/'state'
        store=Store({'state_dir':str(state)},lock=False);_,self.token=store.token('simulator',['read','chat.control','tasks.manage','approvals.respond'],['default']);store.close()
        cfg={'state_dir':str(state),'listen_port':self.bp,'backends':{'default':{'url':f'http://127.0.0.1:{self.hp}','token_file':str(token_file),'source_dir':str(SOURCE),'boards':['default'],'workspaces':{'test':str(self.work)},'artifact_roots':[str(self.work/'.hermes/desktop-attachments')]}}}
        (self.directory/'bridge.json').write_text(json.dumps(cfg))
        modelapp=web.Application();modelapp.router.add_post('/v1/chat/completions',self.model);modelapp.router.add_get('/v1/models',lambda r:web.json_response({'data':[{'id':'bridge-local-test'}]}))
        control=web.Application();control.router.add_post('/restart/{which:hermes|bridge}',self.control);control.router.add_get('/evidence',self.control)
        for app,port in [(modelapp,self.mp),(control,self.cp)]:
            runner=web.AppRunner(app,access_log=None);await runner.setup();await web.TCPSite(runner,'127.0.0.1',port).start();self.runners.append(runner)
        self.launch('hermes');self.launch('bridge')
        headers={'Authorization':'Bearer '+self.token}
        async with aiohttp.ClientSession(headers=headers) as client:
            async with asyncio.timeout(45):
                while True:
                    try:
                        async with client.get(f'http://127.0.0.1:{self.bp}/mobile/v1/capabilities') as r:
                            j=await r.json()
                            if j['profiles']['default']['health']['connected']: break
                    except (aiohttp.ClientError,KeyError): pass
                    await asyncio.sleep(.25)
            for path,body in [('/cron',{'prompt':'Safe scheduled fixture','schedule':'every 1h','name':'Local scheduled work'}),('/kanban/tasks',{'title':'Local Kanban fixture','body':'Read-only integration inventory','triage':True})]:
                async with client.post(f'http://127.0.0.1:{self.bp}/mobile/v1'+path,json=body,headers={'Idempotency-Key':str(uuid.uuid4())}) as r:
                    assert r.status==201
        fixture={'url':f'http://127.0.0.1:{self.bp}','control_url':f'http://127.0.0.1:{self.cp}','token':self.token,'commit':commit}
        (self.directory/'fixture.json').write_text(json.dumps(fixture))
        print(json.dumps({'ready':True,'fixture':str(self.directory/'fixture.json'),'bridge_port':self.bp}),flush=True)

    async def close(self):
        for p in [self.bridge,self.hermes]:
            if p and p.poll() is None: p.kill(); await asyncio.to_thread(p.wait,5)
        for runner in self.runners: await runner.cleanup()
        for f in self.logs:f.close()

async def main():
    os.umask(0o077)
    stack=Stack(Path(sys.argv[1]));stop=asyncio.Event()
    for sig in (signal.SIGTERM,signal.SIGINT):asyncio.get_running_loop().add_signal_handler(sig,stop.set)
    try:await stack.start();await stop.wait()
    finally:await stack.close()
if __name__=='__main__':asyncio.run(main())
