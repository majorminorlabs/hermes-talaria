"""Bounded, conversation-owned staging. No caller-selected paths or automatic replay."""
import base64
import json
import os
import stat
import uuid
from pathlib import Path
from .core import Problem, now

TEXT_EXT = {'txt','md','markdown','json','csv','tsv','py','swift','js','jsx','ts','tsx','c','h','cpp','hpp','rs','go','java','kt','rb','sh','bash','zsh','css','html','xml','yaml','yml','toml','sql','log'}
MIMES = {'image/png','image/jpeg','image/webp','image/gif','application/pdf','text/plain','text/markdown','text/csv','application/json'}

class Uploads:
    def __init__(self, service):
        self.s = service
        self.root = Path(service.cfg['state_dir'])/'uploads'
        if self.root.is_symlink(): raise ValueError('Unsafe upload root')
        self.root.mkdir(mode=0o700,exist_ok=True)
        self.root.chmod(0o700)
        service.store.db.execute('CREATE TABLE IF NOT EXISTS uploads(id TEXT PRIMARY KEY, conversation_id TEXT, data TEXT)')
        service.store.db.commit()
        self.cleanup()

    def cleanup(self):
        db=self.s.store.db
        for row in db.execute('SELECT id,data FROM uploads').fetchall():
            item=json.loads(row[1])
            if item['expires'] < now():
                (self.root/item['id']).unlink(missing_ok=True)
                db.execute('DELETE FROM uploads WHERE id=?',(row[0],))
                db.execute('DELETE FROM artifacts WHERE id=?',(row[0],))
        known={r[0] for r in db.execute('SELECT id FROM uploads')}
        for p in self.root.iterdir():
            if p.name not in known: p.unlink(missing_ok=True)
        db.commit()

    def stage(self,c,body):
        self.cleanup()
        name=body['name'];mime=body['content_type'];limit=min(self.s.cfg['upload_limit'],10*1024*1024)
        if not name or len(name)>200 or name in {'.','..'} or '/' in name or '\\' in name or any(ord(x)<32 for x in name):
            raise Problem(400,'invalid_filename','Attachment must have a simple filename')
        if mime not in MIMES: raise Problem(415,'unsupported_type','Use an image, PDF, JSON or UTF-8 text/source file')
        if len(body['content_base64']) > (limit+2)//3*4: raise Problem(413,'attachment_too_large','Attachment exceeds the size limit')
        try: data=base64.b64decode(body['content_base64'],validate=True)
        except ValueError: raise Problem(400,'invalid_attachment','Invalid base64 attachment') from None
        if not 0<len(data)<=limit: raise Problem(413,'attachment_too_large','Attachment exceeds the size limit')
        ext=Path(name).suffix.lower().lstrip('.')
        good=True
        if mime=='image/png': good=data.startswith(b'\x89PNG\r\n\x1a\n')
        elif mime=='image/jpeg': good=data.startswith(b'\xff\xd8\xff')
        elif mime=='image/gif': good=data.startswith((b'GIF87a',b'GIF89a'))
        elif mime=='image/webp': good=data.startswith(b'RIFF') and data[8:12]==b'WEBP'
        elif mime=='application/pdf': good=data.startswith(b'%PDF-')
        else:
            if ext not in TEXT_EXT: good=False
            try:
                text=data.decode('utf-8');good=good and '\x00' not in text
                if mime=='application/json': json.loads(text)
            except (UnicodeError,ValueError): good=False
        if not good: raise Problem(415,'content_type_mismatch','Attachment bytes do not match a supported type')
        rows=[json.loads(r[0]) for r in self.s.store.db.execute('SELECT data FROM uploads')]
        if sum(r['size'] for r in rows)+len(data)>256*1024*1024 or sum(r['size'] for r in rows if r['conversation_id']==c['id'] and r['state']=='ready')+len(data)>40*1024*1024:
            raise Problem(413,'upload_quota','Pending attachment storage is full')
        aid=uuid.uuid4().hex;p=self.root/aid
        fd=os.open(p,os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW,0o600)
        with os.fdopen(fd,'wb') as f:f.write(data)
        st=p.stat()
        item={'id':aid,'conversation_id':c['id'],'profile':c['profile'],'run_id':None,'name':name,'size':len(data),'content_type':mime,'path':str(p),'device':st.st_dev,'inode':st.st_ino,'mtime_ns':st.st_mtime_ns,'state':'ready','expires':now()+86400}
        db=self.s.store.db
        db.execute('INSERT INTO uploads VALUES (?,?,?)',(aid,c['id'],json.dumps(item)))
        db.execute('INSERT INTO artifacts VALUES (?,?,?,?)',(aid,c['id'],c['profile'],json.dumps(item)));db.commit()
        return {'attached':False,'staged':True,'upload_id':aid,'artifact':self.s.artifact_view(item)}

    def selected(self,c,ids):
        if any(not isinstance(aid,str) or len(aid)!=32 or not all(ch in '0123456789abcdef' for ch in aid) for aid in ids) or len(ids)>4 or len(ids)!=len(set(ids)):raise Problem(400,'invalid_attachments','Select at most four distinct attachments')
        items=[]
        for aid in ids:
            row=self.s.store.db.execute('SELECT data FROM uploads WHERE id=?',(aid,)).fetchone()
            if not row:raise Problem(404,'attachment_unavailable','Upload is unavailable or expired')
            item=json.loads(row[0])
            if item['conversation_id']!=c['id'] or item['profile']!=c['profile']:raise Problem(403,'attachment_denied','Upload belongs to another conversation')
            if item['expires']<now() or item['state']!='ready':raise Problem(409,'attachment_consumed','Upload expired or already submitted; never automatically resend')
            items.append(item)
        return items

    async def attach(self,c,sid,run,items):
        refs=[];db=self.s.store.db;b=self.s.backends[c['profile']]
        for item in items:
            item.update(state='submitting',run_id=run['id'],expires=now()+7*86400)
            db.execute('UPDATE uploads SET data=? WHERE id=?',(json.dumps(item),item['id']));db.commit()
            with self.s.artifact_open(c['profile'],item['path'])[0] as f:data=f.read()
            encoded=base64.b64encode(data).decode();mime=item['content_type']
            if mime.startswith('image/'):
                result=await b.rpc('image.attach_bytes',{'session_id':sid,'content_base64':encoded,'filename':item['name']})
            elif mime=='application/pdf':
                result=await b.rpc('pdf.attach',{'session_id':sid,'content_base64':encoded,'first_page':1,'last_page':5})
                refs.append(f'[Attached PDF {item["name"]}: visual preview limited to the first five pages]')
            else:
                result=await b.rpc('file.attach',{'session_id':sid,'data_url':f'data:{mime};base64,{encoded}','name':item['name']})
            if result.get('ref_text'):refs.append(result['ref_text'])
            item['state']='consumed'
            db.execute('UPDATE uploads SET data=? WHERE id=?',(json.dumps(item),item['id']))
            db.execute('UPDATE artifacts SET data=? WHERE id=?',(json.dumps(item),item['id']));db.commit()
        return refs
