import base64
import json
import uuid
import aiohttp
import pytest
from hermes_mobile_bridge.core import now

def body(c,name='note.md',data=b'# safe existing evidence',mime='text/markdown'):
    return {'conversation_id':c['id'],'name':name,'content_type':mime,'content_base64':base64.b64encode(data).decode()}

async def test_stage_then_send_exact_conversation_and_no_duplicate(harness):
    h=harness;c=await h.request('POST','/conversations',{},expected=201)
    key=str(uuid.uuid4());out=await h.request('POST','/attachments',body(c),key=key,expected=201)
    assert out['staged'] and not out['attached'] and 'path' not in out['artifact']
    assert await h.request('POST','/attachments',body(c),key=key,expected=201)==out
    assert not any(m=='file.attach' for m in h.fake.methods)
    r=await h.request('POST',f"/conversations/{c['id']}/runs",{'text':'Read this note','attachment_ids':[out['upload_id']]},expected=202)
    assert h.fake.methods.count('file.attach')==1
    assert '@file:' in next(p['text'] for m,p in h.fake.requests if m=='prompt.submit')
    assert (await h.request('GET',f"/artifacts/{out['upload_id']}"))['run_id']==r['id']
    # Reuse in another conversation is refused before any native attachment action.
    other=await h.request('POST','/conversations',{},expected=201)
    await h.request('POST',f"/conversations/{other['id']}/runs",{'text':'wrong','attachment_ids':[out['upload_id']]},expected=403)
    assert h.fake.methods.count('file.attach')==1

async def test_image_upload_survives_bridge_restart(harness):
    h=harness;c=await h.request('POST','/conversations',{},expected=201)
    png=base64.b64decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=')
    out=await h.request('POST','/attachments',body(c,'pixel.png',png,'image/png'),expected=201)
    await h.client.close();await h.bridge_runner.cleanup();await h.start_bridge()
    await h.request('POST',f"/conversations/{c['id']}/runs",{'text':'inspect','attachment_ids':[out['upload_id']]},expected=202)
    assert h.fake.methods.count('image.attach_bytes')==1

async def test_upload_rejects_size_type_traversal_auth_and_unknown_fields(harness):
    h=harness;c=await h.request('POST','/conversations',{},expected=201)
    await h.request('POST','/attachments',body(c,data=b'x'*(h.cfg['upload_limit']+1)),expected=413)
    await h.request('POST','/attachments',body(c,'archive.zip',b'zip','application/zip'),expected=415)
    await h.request('POST','/attachments',body(c,'fake.png',b'not png','image/png'),expected=415)
    await h.request('POST','/attachments',body(c,'a.json',b'not json','application/json'),expected=415)
    for name in ('../escape.txt','..\\escape.txt','/tmp/escape.txt','nul\x00.txt','a\n.txt'):
        await h.request('POST','/attachments',body(c,name),expected=400)
    await h.request('POST','/attachments',body(c)|{'path':'/tmp/escape'},expected=400)
    async with aiohttp.ClientSession() as client:
        async with client.post(f'http://127.0.0.1:{h.port}/mobile/v1/attachments',json=body(c)) as r:assert r.status==401
    assert not list(h.service.uploads.root.iterdir())

async def test_expired_upload_cleanup_and_duplicate_selection(harness):
    h=harness;c=await h.request('POST','/conversations',{},expected=201)
    out=await h.request('POST','/attachments',body(c),expected=201);aid=out['upload_id']
    await h.request('POST',f"/conversations/{c['id']}/runs",{'text':'inspect','attachment_ids':[aid,aid]},expected=400)
    for invalid in ([{}], [42], ['../escape'], [True]):
        await h.request('POST',f"/conversations/{c['id']}/runs",{'text':'inspect','attachment_ids':invalid},expected=400)
    row=json.loads(h.service.store.db.execute('SELECT data FROM uploads WHERE id=?',(aid,)).fetchone()[0]);row['expires']=now()-1
    h.service.store.db.execute('UPDATE uploads SET data=? WHERE id=?',(json.dumps(row),aid));h.service.store.db.commit()
    h.service.uploads.cleanup();assert not (h.service.uploads.root/aid).exists()
    assert not h.service.store.db.execute('SELECT 1 FROM artifacts WHERE id=?',(aid,)).fetchone()
    await h.request('POST',f"/conversations/{c['id']}/runs",{'text':'inspect','attachment_ids':[aid]},expected=404)

async def test_pdf_upload_limits_native_preview_and_preserves_context(harness):
    h=harness;c=await h.request('POST','/conversations',{},expected=201)
    a=await h.request('POST','/attachments',body(c,'evidence.pdf',b'%PDF-1.4\nfixture','application/pdf'),expected=201)
    await h.request('POST',f"/conversations/{c['id']}/runs",{'text':'Inspect evidence','attachment_ids':[a['upload_id']]},expected=202)
    params=next(p for m,p in h.fake.requests if m=='pdf.attach')
    assert params['first_page']==1 and params['last_page']==5 and 'path' not in params
    prompt=next(p['text'] for m,p in h.fake.requests if m=='prompt.submit')
    assert 'evidence.pdf' in prompt and 'first five pages' in prompt
