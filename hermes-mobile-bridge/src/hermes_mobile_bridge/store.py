"""Durable observations/commands/auth, not a second conversation or task store."""
import fcntl
import hashlib
import json
import os
import secrets
import sqlite3
import uuid
from pathlib import Path
from .core import Problem, SCOPES, now


class Store:
    def __init__(self, cfg, lock=True):
        self.cfg = cfg
        root = Path(cfg["state_dir"]).expanduser()
        root.mkdir(parents=True, exist_ok=True, mode=0o700)
        if root.is_symlink() or root.stat().st_uid != os.getuid() or root.stat().st_mode & 0o077:
            raise ValueError("State directory must be private, owned, and not a symlink")
        self.lock = None
        if lock:
            self.lock = os.fdopen(os.open(root / "bridge.lock", os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600), "a")
            os.chmod(root / "bridge.lock", 0o600)
            try:
                fcntl.flock(self.lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                self.lock.close()
                raise ValueError("A bridge already owns this state directory") from None
        dbpath = root / "bridge.sqlite3"
        if dbpath.is_symlink():
            raise ValueError("Database may not be a symlink")
        # SQLite sidecars inherit the private database mode.
        fd = os.open(dbpath, os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
        os.close(fd)
        os.chmod(dbpath, 0o600)
        self.db = sqlite3.connect(dbpath)
        self.db.row_factory = sqlite3.Row
        self.db.execute("PRAGMA journal_mode=WAL")
        self.db.execute("PRAGMA synchronous=FULL")
        self.db.executescript('''
        CREATE TABLE IF NOT EXISTS meta(key TEXT PRIMARY KEY, value TEXT);
        CREATE TABLE IF NOT EXISTS credentials(id TEXT PRIMARY KEY, hash TEXT UNIQUE, name TEXT, scopes TEXT, profiles TEXT, revoked INTEGER DEFAULT 0);
        CREATE TABLE IF NOT EXISTS conversations(id TEXT PRIMARY KEY, profile TEXT, stored_id TEXT, live_id TEXT, owned INTEGER, data TEXT, UNIQUE(profile,stored_id));
        CREATE TABLE IF NOT EXISTS aliases(profile TEXT, stored_id TEXT, conversation_id TEXT, PRIMARY KEY(profile,stored_id));
        CREATE TABLE IF NOT EXISTS runs(id TEXT PRIMARY KEY, conversation_id TEXT, profile TEXT, live_id TEXT, state TEXT, created REAL, updated REAL, data TEXT);
        CREATE TABLE IF NOT EXISTS events(seq INTEGER PRIMARY KEY AUTOINCREMENT, run_id TEXT, profile TEXT, type TEXT, created REAL, data TEXT, raw TEXT, dedup TEXT UNIQUE);
        CREATE TABLE IF NOT EXISTS floors(key TEXT PRIMARY KEY, seq INTEGER);
        CREATE TABLE IF NOT EXISTS commands(id TEXT PRIMARY KEY, credential TEXT, digest TEXT, status TEXT, result TEXT);
        CREATE TABLE IF NOT EXISTS attention(id TEXT PRIMARY KEY, run_id TEXT, profile TEXT, data TEXT);
        CREATE TABLE IF NOT EXISTS artifacts(id TEXT PRIMARY KEY, conversation_id TEXT, profile TEXT, data TEXT);
        ''')
        self.db.execute("INSERT OR IGNORE INTO meta VALUES ('epoch',?)", (uuid.uuid4().hex,))
        if lock:
            self.db.execute("UPDATE commands SET status='uncertain' WHERE status='pending'")
        self.db.commit()
        self.epoch = self.db.execute("SELECT value FROM meta WHERE key='epoch'").fetchone()[0]

    def close(self):
        self.db.close()
        if self.lock:
            self.lock.close()

    def token(self, name, scopes, profiles):
        if not set(scopes) <= SCOPES or not scopes or not profiles:
            raise ValueError("Invalid scopes/profiles")
        token = secrets.token_urlsafe(48)
        cid = uuid.uuid4().hex
        self.db.execute("INSERT INTO credentials(id,hash,name,scopes,profiles) VALUES (?,?,?,?,?)", (cid, hashlib.sha256(token.encode()).hexdigest(), name, json.dumps(scopes), json.dumps(profiles)))
        self.db.commit()
        return cid, token

    def auth(self, token):
        row = self.db.execute("SELECT * FROM credentials WHERE hash=? AND revoked=0", (hashlib.sha256(token.encode()).hexdigest(),)).fetchone()
        if not row:
            raise Problem(401, "unauthorized", "Valid application bearer credential required")
        return {"id": row["id"], "scopes": json.loads(row["scopes"]), "profiles": json.loads(row["profiles"])}

    def revoke(self, cid):
        self.db.execute("UPDATE credentials SET revoked=1 WHERE id=?", (cid,))
        self.db.commit()

    def get(self, table, rid):
        row = self.db.execute(f"SELECT * FROM {table} WHERE id=?", (rid,)).fetchone()
        if not row:
            raise Problem(404, "not_found", "Resource not found")
        return dict(row) | {"data": json.loads(row["data"])}

    def save_conversation(self, cid, profile, stored, live=None, owned=False, data=None):
        old = self.db.execute("SELECT * FROM conversations WHERE id=?", (cid,)).fetchone()
        merged = (json.loads(old["data"]) if old else {}) | (data or {})
        self.db.execute("INSERT OR IGNORE INTO aliases VALUES (?,?,?)", (profile, stored, cid))
        self.db.execute("INSERT INTO conversations VALUES (?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET stored_id=excluded.stored_id,live_id=excluded.live_id,owned=excluded.owned,data=excluded.data", (cid, profile, stored, live, int(bool(owned or (old and old["owned"]))), json.dumps(merged)))
        self.db.commit()

    def run(self, cid, profile, live, prompt, parent=None):
        rid = uuid.uuid4().hex
        self.db.execute("INSERT INTO runs VALUES (?,?,?,?,?,?,?,?)", (rid, cid, profile, live, "starting", now(), now(), json.dumps({"prompt": prompt, "parent_run_id": parent, "assistant_text": "", "coverage_gap": False}),))
        self.db.commit()
        return self.get("runs", rid)

    def update_run(self, rid, state=None, **fields):
        row = self.get("runs", rid)
        data = row["data"] | fields
        self.db.execute("UPDATE runs SET state=?,updated=?,data=? WHERE id=?", (state or row["state"], now(), json.dumps(data), rid))
        self.db.commit()
        return self.get("runs", rid)

    def runs(self, profiles, states=None, limit=None, offset=0):
        if not profiles:
            return []
        sql = "SELECT id FROM runs WHERE profile IN (" + ",".join("?" for _ in profiles) + ")"
        args = list(profiles)
        if states:
            sql += " AND state IN (" + ",".join("?" for _ in states) + ")"
            args.extend(states)
        sql += " ORDER BY created DESC LIMIT ? OFFSET ?"
        args.extend([limit if limit is not None else -1, offset])
        return [self.get("runs", r[0]) for r in self.db.execute(sql, args).fetchall()]

    def append(self, profile, kind, payload, run_id=None, conversation_id=None, raw=None, dedup=None):
        if raw is not None and len(json.dumps(raw)) > 65536:
            raw = {"truncated": True}
        if len(json.dumps(payload)) > 131072:
            payload = {"truncated": True, "preview": json.dumps(payload)[:65536], "hydrate": True}
        evt = {"type": kind, "profile": profile, "run_id": run_id, "conversation_id": conversation_id, "observed_at": now(), "payload": payload}
        try:
            cur = self.db.execute("INSERT INTO events(run_id,profile,type,created,data,raw,dedup) VALUES (?,?,?,?,?,?,?)", (run_id, profile, kind, now(), json.dumps(evt), json.dumps(raw) if raw is not None else None, dedup))
        except sqlite3.IntegrityError:
            self.db.rollback()  # release SQLite writer lock on a duplicate
            return None
        seq = cur.lastrowid
        evt.update(seq=seq, cursor=f"{self.epoch}:{seq}")
        self.db.execute("UPDATE events SET data=? WHERE seq=?", (json.dumps(evt), seq))
        self.db.commit()
        self.prune()
        return evt

    def prune(self):
        # Record the highest evicted sequence independently for each run and
        # globally. This detects holes even when a terminal event is retained.
        rows = self.db.execute('''SELECT seq,run_id FROM events WHERE created < ? OR seq IN
          (SELECT seq FROM events ORDER BY seq DESC LIMIT -1 OFFSET ?) OR seq IN
          (SELECT seq FROM (SELECT seq,ROW_NUMBER() OVER(PARTITION BY run_id ORDER BY seq DESC) n FROM events WHERE run_id IS NOT NULL) WHERE n>?)''', (now() - self.cfg["event_days"] * 86400, self.cfg["event_limit"], self.cfg["run_event_limit"])).fetchall()
        byte_rows = self.db.execute("SELECT seq,run_id FROM (SELECT seq,run_id,SUM(LENGTH(data)+COALESCE(LENGTH(raw),0)) OVER(ORDER BY seq DESC) size FROM events) WHERE size>?", (self.cfg.get("event_bytes", 32 * 1024 * 1024),)).fetchall()
        unique = {r["seq"]: r for r in [*rows, *byte_rows]}
        for row in unique.values():
            for key in ["global", "run:" + row["run_id"]] if row["run_id"] else ["global"]:
                self.db.execute("INSERT INTO floors VALUES (?,?) ON CONFLICT(key) DO UPDATE SET seq=MAX(seq,excluded.seq)", (key, row["seq"]))
            self.db.execute("DELETE FROM events WHERE seq=?", (row["seq"],))
        self.db.commit()

    def run_cursor(self, rid):
        last = self.db.execute("SELECT MAX(seq) FROM events WHERE run_id=?", (rid,)).fetchone()[0] or 0
        floor = self.db.execute("SELECT seq FROM floors WHERE key=?", ("run:" + rid,)).fetchone()
        return f"{self.epoch}:{max(last, floor[0] if floor else 0)}"

    def cursor(self):
        seq = self.db.execute("SELECT seq FROM sqlite_sequence WHERE name='events'").fetchone()
        return f"{self.epoch}:{seq[0] if seq else 0}"

    def replay(self, cursor, profiles, run_id=None, limit=500):
        self.prune()
        seq = 0
        if cursor:
            try:
                epoch, number = cursor.split(":")
                seq = int(number)
                if epoch != self.epoch or seq < 0 or seq > int(self.cursor().split(":")[1]):
                    raise ValueError()
            except (ValueError, AttributeError):
                raise Problem(409, "resync_required", "Unknown journal or cursor", cursor=self.cursor()) from None
        floor = self.db.execute("SELECT seq FROM floors WHERE key=?", ("run:" + run_id if run_id else "global",)).fetchone()
        if floor and seq < floor[0]:
            raise Problem(409, "resync_required", "Events have expired; hydrate resource snapshots", cursor=self.cursor())
        # Cursor advances only through scanned events, never past an undelivered page.
        sql = "SELECT * FROM events WHERE seq>?"
        args = [seq]
        if run_id:
            sql += " AND run_id=?"
            args.append(run_id)
        sql += " ORDER BY seq LIMIT ?"
        args.append(limit)
        rows = self.db.execute(sql, args).fetchall()
        return {"events": [json.loads(r["data"]) for r in rows if r["profile"] in profiles], "cursor": f"{self.epoch}:{rows[-1]['seq'] if rows else int(self.cursor().split(':')[1])}", "has_more": len(rows) == limit}

    def command_begin(self, cid, credential, body):
        digest = hashlib.sha256(json.dumps(body, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
        old = self.db.execute("SELECT * FROM commands WHERE id=?", (cid,)).fetchone()
        if old:
            if old["credential"] != credential or old["digest"] != digest:
                raise Problem(409, "command_conflict", "Command ID was used for another request")
            if old["status"] in {"pending", "uncertain"}:
                raise Problem(409, "command_uncertain", "Command may have reached Hermes; inspect state before retrying")
            return json.loads(old["result"])
        self.db.execute("INSERT INTO commands VALUES (?,?,?,'pending',NULL)", (cid, credential, digest))
        self.db.commit()
        return None

    def command_finish(self, cid, result):
        self.db.execute("UPDATE commands SET status='done',result=? WHERE id=?", (json.dumps(result), cid))
        self.db.commit()
