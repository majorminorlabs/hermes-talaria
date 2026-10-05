"""Small contract types; no imports from the Hermes runtime."""
import base64
import json
import os
import re
import stat
import time
from pathlib import Path
from urllib.parse import urlsplit

SCOPES = {"read", "chat.control", "tasks.manage", "approvals.respond"}
TERMINAL = {"complete", "failed", "cancelled"}
ACTIVE = {"starting", "running", "waiting_for_input", "stop_requested", "unknown"}


class Problem(Exception):
    def __init__(self, status, code, message, **details):
        self.status, self.code, self.message, self.details = status, code, message, details
        super().__init__(code)

    def body(self):
        return {"error": {"code": self.code, "message": self.message, "details": self.details}}


def now():
    return time.time()


def only(value, fields):
    return {k: value[k] for k in fields.split() if k in value}


def identifier(value):
    if not isinstance(value, str) or not re.fullmatch(r"[A-Za-z0-9_.-]{1,200}", value):
        raise Problem(400, "invalid_id", "Invalid resource identifier")
    return value


def opaque(profile, upstream_id):
    return base64.urlsafe_b64encode(json.dumps([profile, upstream_id], separators=(",", ":")).encode()).decode().rstrip("=")


def unopaque(value):
    try:
        profile, upstream_id = json.loads(base64.urlsafe_b64decode(value + "=" * (-len(value) % 4)))
        return identifier(profile), identifier(upstream_id)
    except (ValueError, TypeError, UnicodeError):
        raise Problem(400, "invalid_id", "Invalid resource identifier") from None


def secure_read(path):
    """Refuse symlinks and credentials readable by other OS users."""
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    with os.fdopen(fd) as f:
        st = os.fstat(f.fileno())
        if not stat.S_ISREG(st.st_mode) or st.st_uid != os.getuid() or st.st_mode & 0o077:
            raise ValueError("Secret/config file must be owned by this user with mode 0600")
        return f.read()


def load_config(path):
    cfg = json.loads(secure_read(path))
    cfg.setdefault("listen_host", "127.0.0.1")
    cfg.setdefault("listen_port", 8787)
    cfg.setdefault("event_limit", 10000)
    cfg.setdefault("run_event_limit", 2000)
    cfg.setdefault("event_days", 7)
    cfg.setdefault("upload_limit", 10 * 1024 * 1024)
    cfg.setdefault("artifact_limit", 50 * 1024 * 1024)
    if not cfg.get("state_dir") or not cfg.get("backends"):
        raise ValueError("state_dir and at least one backend are required")
    urls = set()
    for name, backend in cfg["backends"].items():
        identifier(name)
        parsed = urlsplit(backend["url"])
        # This release deliberately supports only the audited loopback auth path.
        if parsed.scheme != "http" or parsed.hostname not in {"127.0.0.1", "::1"} or parsed.username or parsed.password or parsed.path not in {"", "/"} or parsed.query or parsed.fragment:
            raise ValueError("Hermes backends must be explicit loopback HTTP origins")
        if backend["url"].rstrip("/") in urls:
            raise ValueError("Each profile requires a distinct isolated backend origin")
        urls.add(backend["url"].rstrip("/"))
        backend["token"] = secure_read(backend["token_file"]).strip()
        if len(backend["token"]) < 24:
            raise ValueError("Upstream token is too short")
        backend.setdefault("boards", [])
        backend.setdefault("artifact_roots", [])
        backend.setdefault("workspaces", {})
        for board in backend["boards"]:
            identifier(board)
    if not 1 <= cfg["run_event_limit"] <= cfg["event_limit"] or cfg["event_days"] <= 0:
        raise ValueError("Invalid retention bounds")
    return cfg


def usage(raw):
    return {"scope": "conversation_cumulative", "tokens": only(raw, "input output cache_read cache_write reasoning prompt completion total calls context_used context_max context_percent compressions"), "model": raw.get("model"), "cost": ({"status": raw.get("cost_status"), "usd": raw.get("cost_usd"), "source": "hermes_estimate"} if "cost_status" in raw else None)}


def message(raw):
    return only(raw, "id role content tool_calls tool_call_id tool_name timestamp created_at reasoning")


def cron(raw, profile):
    return {"id": opaque(profile, raw["id"]), "profile": profile, "kind": "cron", **only(raw, "name prompt skills schedule schedule_display repeat enabled state created_at next_run_at last_run_at last_status last_error last_delivery_error model provider workdir"), "upstream_id": raw["id"]}


def task(raw, profile, board):
    return {"id": opaque(profile, board + "." + raw["id"]), "profile": profile, "board": board, "upstream_id": raw["id"], "kind": "kanban", "state": "complete" if raw.get("status") == "done" else raw.get("status"), "raw_state": raw.get("status"), **only(raw, "title body assignee priority result block_reason created_at updated_at started_at completed_at last_heartbeat_at max_runtime_seconds latest_summary current_run_id age workspace_kind workspace_path")}


def host_info(raw):
    result = only(raw, "hostname system release version platform arch cpu_count cpu_percent load_avg uptime_seconds hermes_version")
    for k, fields in [("memory", "total available used percent"), ("disk", "total used free percent"), ("process", "rss create_time num_threads")]:
        if isinstance(raw.get(k), dict):
            result[k] = only(raw[k], fields)
    return result
