"""Verbatim, device-owned capture inbox. No execution, vault or task coupling."""
import base64
import hashlib
import json
import os
import stat
import uuid
from datetime import datetime, timezone
from pathlib import Path
from .core import Problem
from .uploads import MIMES, TEXT_EXT


class Captures:
    def __init__(self, service):
        self.s = service
        self.root = Path(service.cfg.get('captures_root') or Path(service.cfg['state_dir']) / 'captures')
        if not self.root.is_absolute():
            raise ValueError('captures_root must be absolute')
        # Reject symlinks in every existing component, including a selected parent.
        for component in (self.root, *self.root.parents):
            if component.is_symlink():
                raise ValueError('captures_root may not contain symlinks')
        self.root.mkdir(mode=0o700, parents=True, exist_ok=True)
        st = self.root.stat()
        if st.st_uid != os.getuid() or not stat.S_ISDIR(st.st_mode):
            raise ValueError('Unsafe captures_root owner/type')
        self.root.chmod(0o700)
        self.sync_directory(self.root.parent)
        self.s.store.db.execute('CREATE TABLE IF NOT EXISTS captures(owner TEXT, client_id TEXT, digest TEXT, response TEXT, PRIMARY KEY(owner,client_id))')
        self.s.store.db.execute('CREATE TABLE IF NOT EXISTS capture_uploads(id TEXT PRIMARY KEY, owner TEXT, data TEXT)')
        self.s.store.db.commit()

    def directory(self, owner):
        directory = self.root / hashlib.sha256(owner.encode()).hexdigest()[:32]
        if directory.is_symlink():
            raise Problem(409, 'capture_rejected', 'Unsafe capture directory')
        directory.mkdir(mode=0o700, exist_ok=True)
        directory.chmod(0o700)
        self.sync_directory(self.root)
        return directory

    @staticmethod
    def sync_directory(path):
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
        try: os.fsync(fd)
        finally: os.close(fd)

    @staticmethod
    def write(path, data):
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
        with os.fdopen(fd, 'wb') as f:
            f.write(data)
            f.flush()
            os.fsync(f.fileno())

    def upload(self, auth, body, command_id=None):
        owner = auth['id']
        name, mime = body['name'], body['content_type']
        if not name or len(name) > 200 or name in {'.','..'} or any(c in name for c in '/\\') or any(ord(c) < 32 for c in name):
            raise Problem(400, 'invalid_filename', 'Use a simple capture filename')
        if mime not in MIMES | {'audio/mp4'}:
            raise Problem(415, 'unsupported_type', 'Unsupported capture media')
        limit = min(self.s.cfg.get('upload_limit', 10*1024*1024), 10*1024*1024)
        if len(body['content_base64']) > ((limit+2)//3)*4:
            raise Problem(413, 'capture_too_large', 'Capture media exceeds 10 MiB')
        try:
            data = base64.b64decode(body['content_base64'], validate=True)
        except ValueError:
            raise Problem(400, 'capture_rejected', 'Invalid base64 media') from None
        if not 0 < len(data) <= limit:
            raise Problem(413, 'capture_too_large', 'Capture media exceeds 10 MiB')
        valid = True
        if mime == 'audio/mp4':
            valid = len(data) >= 12 and data[4:8] == b'ftyp'
        elif mime == 'image/png': valid = data.startswith(b'\x89PNG\r\n\x1a\n')
        elif mime == 'image/jpeg': valid = data.startswith(b'\xff\xd8\xff')
        elif mime == 'image/gif': valid = data.startswith((b'GIF87a',b'GIF89a'))
        elif mime == 'image/webp': valid = data.startswith(b'RIFF') and data[8:12] == b'WEBP'
        elif mime == 'application/pdf': valid = data.startswith(b'%PDF-')
        else:
            try:
                text = data.decode('utf-8')
                valid = '\x00' not in text and Path(name).suffix.lstrip('.').lower() in TEXT_EXT
                if mime == 'application/json': json.loads(text)
            except (UnicodeError, ValueError): valid = False
        if not valid:
            raise Problem(415, 'content_type_mismatch', 'Capture bytes do not match their type')
        db = self.s.store.db
        uid = uuid.uuid5(uuid.NAMESPACE_URL, owner + ":" + command_id).hex if command_id else uuid.uuid4().hex
        old = db.execute("SELECT owner,data FROM capture_uploads WHERE id=?", (uid,)).fetchone()
        meta = {"id": uid, "name": name, "content_type": mime, "size": len(data)}
        if old:
            if old[0] != owner or json.loads(old[1]) != meta:
                raise Problem(409, "capture_conflict", "Upload ID already contains different content")
            return {"upload_id": uid, **meta}
        used = sum(json.loads(r[0])['size'] for r in db.execute('SELECT data FROM capture_uploads WHERE owner=?', (owner,)))
        if used + len(data) > self.s.cfg.get('capture_media_quota', 256*1024*1024):
            raise Problem(413, 'capture_too_large', 'Capture media storage is full')
        path = self.directory(owner) / uid
        try: self.write(path, data)
        except FileExistsError:
            fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
            with os.fdopen(fd, "rb") as f:
                st = os.fstat(f.fileno())
                if not stat.S_ISREG(st.st_mode) or st.st_uid != os.getuid() or st.st_nlink != 1 or st.st_mode & 0o077 or f.read() != data:
                    raise Problem(409, "capture_conflict", "Upload persistence conflicts with this ID")
        self.sync_directory(path.parent)
        meta = {'id': uid, 'name': name, 'content_type': mime, 'size': len(data)}
        db.execute('INSERT INTO capture_uploads VALUES (?,?,?)', (uid, owner, json.dumps(meta)))
        db.commit()
        return {'upload_id': uid, **meta}

    def save(self, auth, body):
        owner = auth['id']
        try:
            client_id = str(uuid.UUID(body['client_capture_id']))
            date = datetime.fromisoformat(body['created_at'].replace('Z', '+00:00'))
            if date.tzinfo is None: raise ValueError()
        except (ValueError, TypeError):
            raise Problem(400, 'capture_rejected', 'Provide a UUID and a timestamp with timezone') from None
        if body['kind'] not in {'note','idea','task','link','photo','file','voice'}:
            raise Problem(400, 'capture_rejected', 'Invalid capture kind')
        text = body['text']
        if len(text.encode('utf-8')) > 200000:
            raise Problem(413, 'capture_too_large', 'Capture text exceeds 200 KB')
        ids = body.get('attachment_ids', [])
        if len(ids) > 4 or len(ids) != len(set(ids)) or (not text and not ids):
            raise Problem(400, 'capture_rejected', 'Provide content and at most four distinct attachments')
        context = body.get('context', {})
        if not isinstance(context, dict) or set(context) - {'thread_id','agent_id','tag','transcribed_on_device'}:
            raise Problem(400, 'capture_rejected', 'Invalid capture context')
        if any((not isinstance(v,bool) if k == 'transcribed_on_device' else not isinstance(v,str) or len(v)>1000) for k,v in context.items()):
            raise Problem(400, 'capture_rejected', 'Invalid capture metadata')
        digest = hashlib.sha256(json.dumps(body, sort_keys=True, ensure_ascii=False).encode()).hexdigest()
        db = self.s.store.db
        old = db.execute('SELECT digest,response FROM captures WHERE owner=? AND client_id=?', (owner, client_id)).fetchone()
        if old:
            if old[0] != digest: raise Problem(409, 'capture_conflict', 'Capture ID already contains different content')
            return json.loads(old[1])
        attachments = []
        for uid in ids:
            row = db.execute('SELECT owner,data FROM capture_uploads WHERE id=?', (uid,)).fetchone()
            if not row or row[0] != owner:
                raise Problem(403, 'capture_rejected', 'Capture upload belongs to another device or is missing')
            attachments.append(json.loads(row[1]))
        directory = self.directory(owner)
        stem = date.strftime('%Y-%m-%d') + '-' + client_id
        metadata = {'client_capture_id': client_id, 'created_at': body['created_at'], 'kind': body['kind'], 'context': context, 'attachments': attachments}
        # Files precede confirmation. An interrupted write is reconciled by exact
        # bytes, never overwritten with a different request.
        for suffix, payload in [('.md', text.encode('utf-8')), ('.json', json.dumps(metadata, ensure_ascii=False, sort_keys=True).encode())]:
            path = directory / (stem + suffix)
            try: self.write(path, payload)
            except FileExistsError:
                fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
                with os.fdopen(fd,'rb') as f:
                    st = os.fstat(f.fileno())
                    if not stat.S_ISREG(st.st_mode) or st.st_uid != os.getuid() or st.st_nlink != 1 or st.st_mode & 0o077 or f.read() != payload:
                        raise Problem(409, 'capture_conflict', 'Capture persistence conflicts with this ID')
        self.sync_directory(directory)
        response = {'capture_id': client_id, 'stored_at': datetime.now(timezone.utc).isoformat()}
        db.execute('INSERT INTO captures VALUES (?,?,?,?)', (owner, client_id, digest, json.dumps(response)))
        db.commit()
        return response
