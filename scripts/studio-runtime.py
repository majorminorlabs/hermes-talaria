#!/usr/bin/env python3
"""launchd supervisor with bounded lifecycle-only logs; raw child output discarded."""
import datetime
import json
import logging
from logging.handlers import RotatingFileHandler
import os
from pathlib import Path
import signal
import subprocess
import sys
import threading


def private_json(path):
    if path.is_symlink() or path.stat().st_uid != os.getuid() or path.stat().st_mode & 0o077:
        raise ValueError('Unsafe private configuration')
    return json.loads(path.read_text())


def main():
    os.umask(0o077)
    role, directory = sys.argv[1:]
    root = Path(directory)
    config = private_json(root/'installation.json')
    logger = logging.getLogger('studio'); logger.setLevel(logging.INFO)
    handler = RotatingFileHandler(Path(config['logs'])/(role+'.log'), maxBytes=1024*1024, backupCount=2)
    logger.addHandler(handler)
    def log(event, **fields):
        logger.info(json.dumps({'time':datetime.datetime.now(datetime.timezone.utc).isoformat(), 'service':role, 'event':event, **fields}))
    env = dict(os.environ)
    env.update(PATH=str(Path(config['hermes_source'])/'venv/bin')+':/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin',
               HERMES_HOME=config['hermes_home'], PYTHONUNBUFFERED='1')
    if role == 'backend':
        secret = root/'dashboard-token'
        if secret.is_symlink() or secret.stat().st_uid != os.getuid() or secret.stat().st_mode & 0o077: raise ValueError('Unsafe private credential')
        env['HERMES_DASHBOARD_SESSION_TOKEN'] = secret.read_text().strip()
        # Audited entry point. Explicit loopback binding and no browser/client sink.
        code = 'from hermes_cli.web_server import start_server; start_server(host="127.0.0.1",port='+str(config['hermes_port'])+',open_browser=False)'
        args = [str(Path(config['hermes_source'])/'venv/bin/python'),'-c',code]
        env['PYTHONPATH'] = config['hermes_source']
        commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=config['hermes_source'], text=True).strip()
        if commit == '4bb9e57bfde8a0affb5553eff13ed6e1f14147f1':
            # Current Hermes uses a managed Python/dependency store. The old venv is stale.
            # Resolve its published stdlib-only launcher, then bootstrap without lazy installs.
            code = code.replace('open_browser=False)', 'open_browser=False,headless=True,isolated=True)')
            resolver = 'import sys,json; from pathlib import Path; sys.path.insert(0,sys.argv[1]); from hermes_cli._launchers import runtime_command; print(json.dumps(runtime_command(Path(sys.argv[1]),code=sys.argv[2])))'
            args = json.loads(subprocess.check_output([args[0], '-I', '-c', resolver, config['hermes_source'], code], env=env, text=True))
            env['HERMES_DISABLE_LAZY_INSTALLS'] = '1'
        cwd = config['workspace']
    elif role == 'bridge':
        args = [str(root/'current/venv/bin/hermes-mobile-bridge'),'--config',str(root/'config.json'),'serve']
        cwd = config['workspace']
    else: raise ValueError('Unknown service role')
    # Never persist upstream raw output: it can include prompt/provider/query data.
    child = subprocess.Popen(args,env=env,cwd=cwd,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,start_new_session=True)
    log('started',pid=child.pid)
    def shutdown(signum, frame):
        log('stop_requested')
        try: os.killpg(child.pid, signal.SIGTERM)
        except ProcessLookupError: return
        # Hermes can retain background threads after its listener shuts down.
        # Bound shutdown so launchd cannot orphan the dedicated child.
        def force_stop():
            try: os.killpg(child.pid, signal.SIGKILL)
            except ProcessLookupError: pass
        timer = threading.Timer(5, force_stop); timer.daemon = True; timer.start()
    signal.signal(signal.SIGTERM,shutdown); signal.signal(signal.SIGINT,shutdown)
    code = child.wait()
    log('exited',returncode=code)
    # launchd KeepAlive handles a crash. Intentional bootout stops the supervisor.
    return code if code >= 0 else 128-code

if __name__ == '__main__':
    try: sys.exit(main())
    except (ValueError,OSError,KeyError):
        print('Private Studio runtime configuration failed.',file=sys.stderr)
        sys.exit(1)
