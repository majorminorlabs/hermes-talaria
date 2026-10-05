#!/usr/bin/env python3
"""Private per-user Studio service management. No upstream Hermes edits."""
import argparse
import datetime
import json
import os
from pathlib import Path
import plistlib
import secrets
import shutil
import socket
import sqlite3
import subprocess
import sys
import time
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_ROOT = Path.home() / 'Library/Application Support/HermesMobileBridge'
LABELS = {'backend': 'xyz.majorminor.talaria-mobile-backend', 'bridge': 'xyz.majorminor.talaria-mobile-bridge'}


def private_dir(path):
    if path.is_symlink():
        raise ValueError('Private directory cannot be a symlink')
    path.mkdir(parents=True, exist_ok=True, mode=0o700)
    if path.stat().st_uid != os.getuid():
        raise ValueError('Private directory must belong to the current user')
    path.chmod(0o700)


def private_write(path, value):
    if path.is_symlink():
        raise ValueError('Private file cannot be a symlink')
    tmp = path.with_name(path.name + '.new')
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        with os.fdopen(fd, 'w') as f:
            f.write(value)
        os.replace(tmp, path)
    finally:
        tmp.unlink(missing_ok=True)


def read_json(path):
    if path.is_symlink() or path.stat().st_uid != os.getuid() or path.stat().st_mode & 0o077:
        raise ValueError('Private configuration must be owned and mode 0600')
    return json.loads(path.read_text())


def command(args, **kwargs):
    # stdout/stderr can contain dependency URLs, environment or query tokens.
    return subprocess.run(args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True, **kwargs)


def launch_domain():
    return f'gui/{os.getuid()}'


def load_manifest(root):
    return read_json(root / 'installation.json')


def plist_path(label):
    return Path.home() / 'Library/LaunchAgents' / (label + '.plist')


def stop(root):
    manifest = load_manifest(root)
    for role in ('bridge', 'backend'):
        subprocess.run(['launchctl', 'bootout', launch_domain() + '/' + manifest['labels'][role]], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    deadline = time.monotonic() + 20
    while time.monotonic() < deadline:
        loaded = any(subprocess.run(['launchctl', 'print', launch_domain() + '/' + label], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0 for label in manifest['labels'].values())
        if not loaded and not any(listening(port) for port in (manifest['bridge_port'], manifest['hermes_port'])):
            return
        time.sleep(.2)
    raise ValueError('Service listener did not stop; inspect status before updating')


def start(root):
    manifest = load_manifest(root)
    for role in ('backend', 'bridge'):
        label = manifest['labels'][role]
        command(['launchctl', 'enable', launch_domain() + '/' + label])
        loaded = subprocess.run(['launchctl', 'print', launch_domain() + '/' + label], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0
        if not loaded:
            command(['launchctl', 'bootstrap', launch_domain(), str(plist_path(label))])
        command(['launchctl', 'kickstart', launch_domain() + '/' + label])
    print('Studio backend and bridge started. Use status-bridge.sh for authenticated health.')


def listening(port):
    with socket.socket() as s:
        s.settimeout(.3)
        return s.connect_ex(('127.0.0.1', port)) == 0


def request(root, path, timeout=8):
    manifest = load_manifest(root)
    credential = read_json(root / 'operator.json')
    req = urllib.request.Request(f'http://127.0.0.1:{manifest["bridge_port"]}/mobile/v1' + path,
                                 headers={'Authorization': 'Bearer ' + credential['token']})
    with urllib.request.urlopen(req, timeout=timeout) as response:
        return json.load(response)


def status(root):
    manifest = load_manifest(root)
    result = {'installation_root': str(root), 'services': {}, 'bridge_reachable': False, 'hermes_healthy': False}
    for role in ('backend', 'bridge'):
        r = subprocess.run(['launchctl', 'print', launch_domain() + '/' + manifest['labels'][role]], capture_output=True, text=True)
        state = 'not_loaded'; pid = None
        for line in r.stdout.splitlines():
            if line.strip().startswith('state = '): state = line.split('=', 1)[1].strip()
            if line.strip().startswith('pid = '): pid = int(line.split('=', 1)[1])
        result['services'][role] = {'label':manifest['labels'][role], 'state':state, 'pid':pid}
    try:
        caps = request(root, '/capabilities')
        result.update(bridge_reachable=True, hermes_healthy=all(p['health']['connected'] for p in caps['profiles'].values()),
                      capabilities={p: row['features'] for p, row in caps['profiles'].items()}, bridge_version=caps['bridge_version'])
    except (OSError, ValueError, urllib.error.URLError):
        result['health_error'] = 'authenticated_bridge_health_unavailable'
    if (root / 'transport.json').exists():
        result['studio_url'] = read_json(root / 'transport.json')['url']
    return result


def stage_release(root, python):
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    release = root / 'releases' / stamp
    private_dir(release)
    package = release / 'package'; package.mkdir()
    for name in ['pyproject.toml','README.md']:
        shutil.copyfile(ROOT / 'hermes-mobile-bridge' / name, package / name)
    for path in (ROOT/'hermes-mobile-bridge/src').rglob('*.py'):
        target = package/path.relative_to(ROOT/'hermes-mobile-bridge')
        target.parent.mkdir(parents=True,exist_ok=True); shutil.copyfile(path,target)
    shutil.copyfile(ROOT / 'scripts/studio-runtime.py', release / 'studio-runtime.py')
    command([python, '-m', 'venv', str(release / 'venv')])
    command([str(release / 'venv/bin/python'), '-m', 'pip', 'install', str(release / 'package')])
    command([str(release / 'venv/bin/python'), '-c', 'import hermes_mobile_bridge,aiohttp'])
    return release


def set_current(root, release):
    temp = root / 'current.new'
    temp.unlink(missing_ok=True)
    temp.symlink_to(release.resolve().relative_to(root.resolve()), target_is_directory=True)
    os.replace(temp, root / 'current')


def provision(root, name, scopes):
    manifest = load_manifest(root)
    cmd = [str(root / 'current/venv/bin/hermes-mobile-bridge'), '--config', str(root / 'config.json'), 'token-create', '--name', name, '--scopes', scopes, '--profiles', 'default']
    r = subprocess.run(cmd, capture_output=True, text=True, check=True)
    return json.loads(r.stdout)


def write_agents(root, manifest, reject_existing=False):
    for role, label in manifest['labels'].items():
        template = plistlib.loads((ROOT / f'launchd/{label}.plist').read_bytes())
        template['ProgramArguments'] = [str(root/'current/venv/bin/python'), str(root/'current/studio-runtime.py'), role, str(root)]
        template['WorkingDirectory'] = manifest['workspace']
        plist_path(label).parent.mkdir(parents=True, exist_ok=True)
        if reject_existing and plist_path(label).exists():
            raise ValueError('Existing launchd label is not owned by this installation')
        plist_path(label).write_bytes(plistlib.dumps(template))
        plist_path(label).chmod(0o600)


def install(args, root):
    if (root / 'installation.json').exists():
        if (root/'current').exists():
            raise ValueError('Already installed; use update-bridge.sh to preserve state/configuration')
        manifest = load_manifest(root)
        release = stage_release(root, manifest['python']); set_current(root, release)
        if not (root/'operator.json').exists():
            private_write(root/'operator.json', json.dumps(provision(root, 'Studio health operator', 'read')))
        write_agents(root, manifest)
        start(root)
        return
    if root.is_relative_to(ROOT):
        raise ValueError('Install private state outside the source checkout')
    source = Path(args.hermes_source).expanduser().resolve()
    home = Path(args.hermes_home).expanduser().resolve()
    commit = subprocess.check_output(['git','rev-parse','HEAD'],cwd=source,text=True).strip()
    if not any(commit.startswith(c) for c in ('2a4c9afd7bd', '4bb9e57bfde8a0affb5553eff13ed6e1f14147f1')):
        raise ValueError('Installed Hermes differs from the audited commit')
    if not (source / 'venv/bin/python').exists() or not home.is_dir():
        raise ValueError('Existing Hermes installation/home are required')
    if listening(args.bridge_port) or listening(args.hermes_port):
        raise ValueError('A loopback port is already occupied; choose unused ports')
    if any(plist_path(label).exists() for label in LABELS.values()):
        raise ValueError('Existing launchd labels must be preserved; choose a separate installation intentionally')
    private_dir(root); private_dir(root / 'state'); private_dir(root / 'releases')
    workspace = Path(args.workspace).expanduser().resolve() if args.workspace else root / 'workspace'
    if not workspace.exists(): private_dir(workspace)
    logs = Path.home() / 'Library/Logs/HermesMobileBridge'; private_dir(logs)
    secret = root / 'dashboard-token'
    private_write(secret, secrets.token_urlsafe(48))
    artifact = workspace / '.hermes/desktop-attachments'; private_dir(artifact)
    config = {'state_dir':str(root/'state'), 'listen_host':'127.0.0.1', 'listen_port':args.bridge_port,
              'backends':{'default':{'url':f'http://127.0.0.1:{args.hermes_port}', 'token_file':str(secret),
                 'source_dir':str(source), 'bot_mode_roster':args.bot_mode or args.bot_chat or args.bot_management, 'bot_chat_control':args.bot_chat, 'bot_mode_management':args.bot_management, 'installed_commit':commit, 'boards':args.board, 'workspaces':{'studio':str(workspace)}, 'artifact_roots':[str(artifact)]}}}
    private_write(root/'config.json', json.dumps(config, indent=2))
    manifest = {'hermes_source':str(source), 'hermes_home':str(home), 'hermes_port':args.hermes_port,
                'bridge_port':args.bridge_port, 'workspace':str(workspace), 'logs':str(logs), 'python':args.python,
                'labels':LABELS, 'installed_commit':commit}
    private_write(root/'installation.json', json.dumps(manifest, indent=2))
    release = stage_release(root, args.python); set_current(root, release)
    private_write(root/'operator.json', json.dumps(provision(root, 'Studio health operator', 'read')))
    write_agents(root, manifest, reject_existing=True)
    start(root)


def ensure_idle(root):
    # Bot edits and uploads can be pending without a run yet. Never interrupt
    # those mutations during release staging or service restart.
    config_path = root / 'config.json'
    if config_path.exists():
        config = read_json(config_path)
        journal = Path(config['state_dir']) / 'bridge.sqlite3'
        if journal.is_symlink() or not journal.is_file():
            raise ValueError('Cannot verify the private command journal before update')
        with sqlite3.connect(journal.as_uri() + '?mode=ro', uri=True) as db:
            if db.execute("SELECT 1 FROM commands WHERE status='pending' LIMIT 1").fetchone():
                raise ValueError('A mobile command is pending; wait for it before updating services')
    # An unknown run is active too; interruption cannot be justified by a timeout.
    for state in ('starting', 'running', 'waiting_for_input', 'stop_requested', 'unknown'):
        if request(root, '/runs?state=' + state + '&limit=1')['runs']:
            raise ValueError('Active/unknown work exists; resolve it before updating services')

def update(root):
    manifest = load_manifest(root)
    ensure_idle(root)
    release = stage_release(root, manifest['python'])
    # Recheck after dependency installation; do not interrupt newly accepted work.
    ensure_idle(root)
    previous = (root / 'current').resolve()
    stop(root); set_current(root, release)
    try:
        start(root)
        for _ in range(120):
            if status(root)['hermes_healthy']:
                print('Update healthy; canonical journal and credentials preserved.')
                return
            time.sleep(.5)
    except (OSError, ValueError, subprocess.SubprocessError):
        pass
    stop(root); set_current(root, previous); start(root)
    raise ValueError('Update health failed; previous runtime restored')


def owns_serve(config, proxy):
    webs = list(config.get('Web', {}).values())
    return (not config.get('AllowFunnel') and set(config.get('TCP', {})) == {'443'}
            and config['TCP']['443'].get('HTTPS') is True and len(webs) == 1
            and set(webs[0].get('Handlers', {})) == {'/'}
            and webs[0]['Handlers']['/'].get('Proxy') == proxy)


def tailscale_configure(root):
    manifest = load_manifest(root)
    binary = shutil.which('tailscale')
    if not binary: raise ValueError('Install and authenticate Tailscale first')
    info = json.loads(subprocess.check_output([binary, 'status', '--json'], text=True))
    if info.get('BackendState') != 'Running': raise ValueError('Tailscale login/connection is required')
    dns = info['Self']['DNSName'].rstrip('.')
    expected = f'http://127.0.0.1:{manifest["bridge_port"]}'
    current = json.loads(subprocess.check_output([binary,'serve','status','--json'],text=True))
    if current and not owns_serve(current, expected):
        raise ValueError('Existing Serve/Funnel config is not this bridge; preserve it and choose a separate route')
    command([binary,'serve','--bg','--https=443','--yes',expected])
    private_write(root/'transport.json', json.dumps({'url':'https://'+dns, 'proxy':expected, 'https_port':443}))
    print('https://' + dns)


def uninstall(root, purge=False):
    manifest = load_manifest(root); stop(root)
    for label in manifest['labels'].values(): plist_path(label).unlink(missing_ok=True)
    if (root / 'transport.json').exists():
        # Remove only an unchanged, sole Serve route owned by this installation.
        binary = shutil.which('tailscale')
        if binary:
            config = json.loads(subprocess.check_output([binary,'serve','status','--json'],text=True))
            owned = read_json(root/'transport.json')
            if owns_serve(config, owned['proxy']):
                command([binary,'serve','--https=443','off'])
            else: print('Modified Serve configuration retained; remove only the bridge route manually.')
    (root/'current').unlink(missing_ok=True)
    shutil.rmtree(root/'releases', ignore_errors=True)
    if purge:
        shutil.rmtree(root)
        print('Uninstalled and purged private bridge state. Hermes installation/home were retained.')
    else:
        print('Uninstalled runtime/agents. Private state/configuration retained for backup; do not delete if run IDs or tokens are needed.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bot-management', action='store_true', help='Allow native Desktop bot create/edit/hide with chat.control credentials')
    parser.add_argument('--bot-chat', action='store_true', help='Allow native canonical Bot Chat initialization and control for every local Desktop bot')
    parser.add_argument('--bot-mode', action='store_true', help='Allow mobile read access to every local Desktop bot, including future bots')
    parser.add_argument('action',choices=['install','start','stop','status','update','uninstall','tailscale','pairing'])
    parser.add_argument('--root',default=str(DEFAULT_ROOT)); parser.add_argument('--json',action='store_true')
    parser.add_argument('--hermes-source',default=str(Path.home()/'.hermes/hermes-agent'))
    parser.add_argument('--hermes-home',default=str(Path.home()/'.hermes')); parser.add_argument('--workspace')
    parser.add_argument('--python',default=sys.executable); parser.add_argument('--bridge-port',type=int,default=8787)
    parser.add_argument('--hermes-port',type=int,default=9119); parser.add_argument('--board',action='append',default=[])
    parser.add_argument('--purge',action='store_true'); parser.add_argument('--name',default='iPhone')
    parser.add_argument('--scopes',default='read,chat.control,tasks.manage,approvals.respond')
    parser.add_argument('--forget-transfer',action='store_true'); parser.add_argument('--show',action='store_true'); parser.add_argument('--revoke'); parser.add_argument('--list',action='store_true')
    args = parser.parse_args(); root = Path(args.root).expanduser().absolute()
    if sys.platform != 'darwin': parser.error('Studio service management requires macOS')
    if os.getuid() == 0: parser.error('Run as the Studio user, not root')
    os.umask(0o077)
    try:
        if args.action == 'install': install(args, root)
        elif args.action == 'start': start(root)
        elif args.action == 'stop': stop(root); print('Bridge and dedicated backend stopped.')
        elif args.action == 'status': print(json.dumps(status(root),indent=2))
        elif args.action == 'update': update(root)
        elif args.action == 'uninstall': uninstall(root,args.purge)
        elif args.action == 'tailscale': tailscale_configure(root)
        elif args.action == 'pairing':
            binary = str(root/'current/venv/bin/hermes-mobile-bridge')
            base = [binary,'--config',str(root/'config.json')]
            if args.revoke:
                command(base+['token-revoke',args.revoke])
                path = root/'mobile-pairing.json'
                if path.exists() and read_json(path)['id'] == args.revoke: path.unlink()
                print('Credential revoked.')
            elif args.forget_transfer:
                (root/'mobile-pairing.json').unlink(missing_ok=True)
                print('Local transfer copy removed. Phone credential remains valid until revoked.')
            elif args.list:
                # CLI list contains metadata/hashes? Source exposes no hashes/tokens.
                subprocess.run(base+['token-list'],check=True)
            else:
                path = root/'mobile-pairing.json'
                if not path.exists(): private_write(path,json.dumps(provision(root,args.name,args.scopes)))
                data = read_json(path)
                if args.show:
                    if not sys.stdout.isatty(): raise ValueError('Token display requires a private interactive terminal')
                    print(data['token'])
                else: print('Mobile token prepared in a private file. Use pairing-token.sh --show in a private terminal; never redirect token output to logs. Device ID: '+data['id'])
    except (ValueError, OSError, KeyError, subprocess.SubprocessError, urllib.error.URLError):
        print('Studio service operation failed. Check private file permissions, ports, launchd status, audited Hermes installation and network authorization. No secret diagnostics were logged.',file=sys.stderr)
        return 1
    return 0

if __name__ == '__main__': sys.exit(main())
