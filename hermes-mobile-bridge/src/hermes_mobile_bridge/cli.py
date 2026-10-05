import argparse
import json
import logging
import os
import ssl
import subprocess
import sys
from aiohttp import web
from .api import create_app
from .core import SCOPES, load_config
from .bots import AUDITED_COMMITS
from .store import Store


def main():
    parser = argparse.ArgumentParser(description="Private Studio bridge for Hermes desktop APIs")
    parser.add_argument("--config", required=True)
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("serve")
    token = sub.add_parser("token-create")
    token.add_argument("--name", required=True)
    token.add_argument("--scopes", default="read,chat.control,tasks.manage,approvals.respond")
    token.add_argument("--profiles", default="default")
    revoke = sub.add_parser("token-revoke")
    revoke.add_argument("id")
    sub.add_parser("token-list")
    args = parser.parse_args()
    os.umask(0o077)
    try:
        cfg = load_config(args.config)
        if args.command == "serve":
            for b in cfg["backends"].values():
                if b.get("source_dir"):
                    b["installed_commit"] = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=b["source_dir"], text=True, timeout=5).strip()
                    if not any(b["installed_commit"].startswith(c) for c in AUDITED_COMMITS):
                        raise ValueError("Hermes commit differs from audited contract; audit before serving")
            tls = None
            if cfg.get("tls_cert") and cfg.get("tls_key"):
                tls = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
                tls.minimum_version = ssl.TLSVersion.TLSv1_2
                tls.load_cert_chain(cfg["tls_cert"], cfg["tls_key"])
            if cfg["listen_host"] not in {"127.0.0.1", "::1"} and not tls:
                raise ValueError("Nonloopback listener requires TLS; alternatively terminate tailnet HTTPS at a loopback proxy")
            # No access logs: token headers/query URLs and prompts stay private.
            logging.getLogger("aiohttp").setLevel(logging.CRITICAL)
            web.run_app(create_app(cfg), host=cfg["listen_host"], port=cfg["listen_port"], ssl_context=tls, access_log=None, print=None, shutdown_timeout=3)
        else:
            store = Store(cfg, lock=False)
            try:
                if args.command == "token-create":
                    profiles = args.profiles.split(",")
                    if not set(profiles) <= set(cfg["backends"]):
                        raise ValueError("Unknown credential profile")
                    cid, secret = store.token(args.name, args.scopes.split(","), profiles)
                    # Deliberate one-time provisioning output, never server logs.
                    print(json.dumps({"id": cid, "token": secret}))
                elif args.command == "token-revoke":
                    store.revoke(args.id)
                    print(json.dumps({"revoked": args.id}))
                else:
                    rows = store.db.execute("SELECT id,name,scopes,profiles,revoked FROM credentials").fetchall()
                    print(json.dumps([dict(r) for r in rows]))
            finally:
                store.close()
    except (ValueError, OSError, subprocess.SubprocessError):
        print("Bridge configuration/startup failed. Check private file permissions, backend origins, audited commit, TLS, and state ownership.", file=sys.stderr)
        sys.exit(1)
