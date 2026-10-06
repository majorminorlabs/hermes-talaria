import base64
import json
import stat
import uuid
from pathlib import Path
import pytest
from test_bot_chat import prepare_bot, rpc_requests
pytestmark = pytest.mark.asyncio

async def test_agent_threads_are_distinct_and_listed(harness):
    h = harness
    _, bid = prepare_bot(h)
    a = await h.request('POST', f'/bots/{bid}/conversations', {'title': 'Find suppliers'},expected=201)
    b = await h.request('POST', f'/bots/{bid}/conversations', {'title': 'Compare models'},expected=201)
    assert a['id'] != b['id'] and a['bot_id'] == b['bot_id'] == bid
    assert not a['is_bot_chat'] and not b['is_bot_chat']
    assert all(r['follow_profile_config'] for r in rpc_requests(h,'session.create'))
    listed = await h.request('GET','/conversations')
    assert {a['id'], b['id']} <= {r['id'] for r in listed['conversations']}
    await h.request('POST', f"/conversations/{a['id']}/runs", {'text':'Fresh ask'},expected=202)
    assert rpc_requests(h,'prompt.submit')[-1]['profile'] == 'research-orchestrator'

async def test_agent_thread_cannot_break_canonical_chat_or_read_only_grant(harness):
    h = harness
    _, bid = prepare_bot(h,control=False)
    await h.request('POST',f'/bots/{bid}/conversations',{},expected=403)
    h.service.backends['default'].cfg['bot_chat_control'] = True
    await h.request('POST',f'/bots/{bid}/conversations',{'title':'Bot Chat'},expected=400)

async def test_capture_verbatim_persistence_and_idempotency(harness):
    h = harness
    body = {'client_capture_id':str(uuid.uuid4()),'created_at':'2026-10-05T12:00:00-05:00','kind':'note','text':'  exact\n# text\n\ntrailing  ', 'context':{'tag':'metadata only'}}
    a = await h.request('POST','/captures',body,expected=201)
    b = await h.request('POST','/captures',body,expected=201)
    assert a == b
    root = Path(h.service.cfg['state_dir'])/'captures'
    files = list(root.rglob('*.md'))
    assert len(files) == 1 and files[0].read_bytes() == body['text'].encode()
    assert json.loads(files[0].with_suffix('.json').read_text())['context'] == body['context']
    for path in [root, files[0].parent]: assert stat.S_IMODE(path.stat().st_mode) == 0o700
    for path in [files[0],files[0].with_suffix('.json')]: assert stat.S_IMODE(path.stat().st_mode) == 0o600
    await h.request('POST','/captures',body | {'text':'changed'},expected=409)
    h.service.backends['default'].connected = False
    await h.request('POST','/captures',body | {'client_capture_id':str(uuid.uuid4())},expected=201)

async def test_capture_audio_upload_and_metadata(harness):
    h = harness
    audio = b'\x00\x00\x00\x18ftypM4A '+b'\x00'*20
    upload = await h.request('POST','/captures/uploads',{'name':'Voice.m4a','content_type':'audio/mp4','content_base64':base64.b64encode(audio).decode()},expected=201)
    body = {'client_capture_id':str(uuid.uuid4()),'created_at':'2026-10-05T12:00:00Z','kind':'voice','text':'spoken exactly','attachment_ids':[upload['upload_id']]}
    await h.request('POST','/captures',body,expected=201)
    root = Path(h.service.cfg['state_dir'])/'captures'
    assert json.loads(next(root.rglob('*.json')).read_text())['attachments'][0]['content_type'] == 'audio/mp4'
    assert next(root.rglob(upload['upload_id'])).read_bytes() == audio
    await h.request('POST','/captures/uploads',{'name':'../bad','content_type':'audio/mp4','content_base64':base64.b64encode(audio).decode()},expected=400)
    await h.request('POST','/captures/uploads',{'name':'bad.m4a','content_type':'audio/mp4','content_base64':base64.b64encode(b'bad').decode()},expected=415)

async def test_capture_interrupted_receipt_is_recoverable_but_ask_is_not(harness):
    h = harness
    body = {'client_capture_id': str(uuid.uuid4()), 'created_at': '2026-10-05T12:00:00Z', 'kind':'note','text':'durable'}
    key = str(uuid.uuid4())
    first = await h.request('POST','/captures',body,expected=201,key=key)
    h.service.store.db.execute("UPDATE commands SET status='uncertain', result=NULL WHERE id=?",(key,)); h.service.store.db.commit()
    assert await h.request('POST','/captures',body,expected=201,key=key) == first
    assert len(list(h.service.captures.root.rglob('*.md'))) == 1
    assert (await h.request('GET','/commands/'+key))['state'] == 'done'
    assert (await h.request('GET','/commands/'+str(uuid.uuid4())))['state'] == 'not_received'
    await h.request('POST','/captures',body | {'text':'different'}, expected=409,key=key)

async def test_capture_owner_and_scope_isolation(harness):
    h = harness
    _, other = h.service.store.token('other',['read','chat.control'],['default'])
    _, reader = h.service.store.token('reader',['read'],['default'])
    key = str(uuid.uuid4())
    payload = {'name':'Voice.m4a','content_type':'audio/mp4','content_base64':base64.b64encode(b'\x00\x00\x00\x18ftypM4A '+b'\x00'*20).decode()}
    upload = await h.request('POST','/captures/uploads',payload,expected=201,key=key)
    capture = {'client_capture_id':str(uuid.uuid4()),'created_at':'2026-10-05T12:00:00Z','kind':'voice','text':'exact','attachment_ids':[upload['upload_id']]}
    await h.request('POST','/captures',capture,expected=403,token=other)
    await h.request('POST','/captures',capture,expected=403,token=reader)
    await h.request('GET','/commands/'+key,expected=403,token=other)

async def test_audio_interrupted_upload_does_not_duplicate(harness):
    h = harness
    key = str(uuid.uuid4())
    payload = {'name':'Voice.m4a','content_type':'audio/mp4','content_base64':base64.b64encode(b'\x00\x00\x00\x18ftypM4A '+b'\x00'*20).decode()}
    first = await h.request('POST','/captures/uploads',payload,expected=201,key=key)
    h.service.store.db.execute("UPDATE commands SET status='uncertain', result=NULL WHERE id=?",(key,));h.service.store.db.commit()
    assert await h.request('POST','/captures/uploads',payload,expected=201,key=key) == first
    assert h.service.store.db.execute('SELECT COUNT(*) FROM capture_uploads').fetchone()[0] == 1

async def test_capture_quota_is_owner_scoped_and_replay_safe_at_limit(harness):
    h = harness
    data = b'quota'
    h.service.cfg['capture_media_quota'] = len(data)
    payload = {'name':'note.txt','content_type':'text/plain','content_base64':base64.b64encode(data).decode()}
    key = str(uuid.uuid4())
    first = await h.request('POST','/captures/uploads',payload,expected=201,key=key)
    h.service.store.db.execute("UPDATE commands SET status='uncertain', result=NULL WHERE id=?",(key,));h.service.store.db.commit()
    assert await h.request('POST','/captures/uploads',payload,expected=201,key=key) == first
    await h.request('POST','/captures/uploads',payload,expected=413)
    _, other = h.service.store.token('other',['read','chat.control'],['default'])
    second = await h.request('POST','/captures/uploads',payload,expected=201,token=other)
    assert second['upload_id'] != first['upload_id']

async def test_agent_override_and_receipt_preserve_creation_contract(harness):
    h = harness
    _, bid = prepare_bot(h)
    key = str(uuid.uuid4())
    fields = {'model':'fixture/model','provider':'custom','reasoning_effort':'low'}
    c = await h.request('POST',f'/bots/{bid}/conversations',fields,expected=201,key=key)
    assert await h.request('POST',f'/bots/{bid}/conversations',fields,expected=201,key=key) == c
    created = rpc_requests(h,'session.create')
    assert len(created) == 1 and created[0]['follow_profile_config'] is False
    assert created[0]['model'] == 'fixture/model' and created[0]['reasoning_effort'] == 'low'

async def test_review_targets_and_note_preservation(harness):
    h = harness
    from hermes_mobile_bridge.core import opaque
    tid = 'review-fixture'
    h.fake.cards[tid] = {'id':tid,'title':'Review shortlist','status':'review'}
    bid = opaque('default','default.'+tid)
    board = await h.request('GET','/kanban/tasks')
    row = next(t for t in board['tasks'] if t['id'] == bid)
    assert {'done','ready','todo'} <= set(row['supported_targets'])
    await h.request('PATCH','/kanban/tasks/'+bid,{'status':'done','summary':'Checked evidence'})
    assert h.fake.cards[tid]['summary'] == 'Checked evidence'
    h.fake.cards[tid]['status'] = 'review'
    key = str(uuid.uuid4())
    await h.request('PATCH','/kanban/tasks/'+bid,{'status':'ready','summary':'Revise supplier two'},key=key)
    assert h.fake.comments[tid] == [{'body':'Revise supplier two','author':'Talaria'}]
    await h.request('PATCH','/kanban/tasks/'+bid,{'status':'ready','summary':'Revise supplier two'},key=key)
    assert len(h.fake.comments[tid]) == 1

async def test_agent_workspace_is_creation_only_and_allowlisted(harness):
    h = harness
    _, bid = prepare_bot(h)
    h.service.backends['default'].cfg['workspaces']['fixture'] = str(h.fake.root)
    await h.request('POST',f'/bots/{bid}/conversations',{'workspace':'fixture'},expected=201)
    assert rpc_requests(h,'session.create')[-1]['cwd'] == str(h.fake.root)
    await h.request('POST',f'/bots/{bid}/conversations',{'workspace':'/etc'},expected=400)

async def test_capture_confirmation_waits_for_directory_durability(harness,monkeypatch):
    from hermes_mobile_bridge.captures import Captures
    h = harness
    original = Captures.sync_directory
    def interrupted(path):
        if path != h.service.captures.root: raise OSError('simulated directory flush failure')
        original(path)
    monkeypatch.setattr(Captures,'sync_directory',staticmethod(interrupted))
    key = str(uuid.uuid4())
    body = {'client_capture_id':str(uuid.uuid4()),'created_at':'2026-10-05T12:00:00Z','kind':'note','text':'exact durable text','context':{'tag':'true'}}
    await h.request('POST','/captures',body,key=key,expected=500)
    assert h.service.store.db.execute('SELECT COUNT(*) FROM captures').fetchone()[0] == 0
    monkeypatch.setattr(Captures,'sync_directory',staticmethod(original))
    result = await h.request('POST','/captures',body,key=key,expected=201)
    assert result['capture_id'] == body['client_capture_id']
    files = list(h.service.captures.root.rglob('*.md'))
    assert len(files) == 1 and files[0].read_bytes() == body['text'].encode()
    assert json.loads(files[0].with_suffix('.json').read_text())['context']['tag'] == 'true'

async def test_kanban_native_agent_assignment_preserves_identity(harness):
    h = harness
    _, bid = prepare_bot(h)
    card = await h.request('POST','/kanban/tasks',{'title':'Native Agent card','assignee':bid},expected=201)
    assert card['assignee'] == bid
    raw = h.fake.cards[card['upstream_id']]
    assert raw['assignee'] == 'research-orchestrator'
    await h.request('PATCH','/kanban/tasks/'+card['id'],{'assignee':bid})
    assert (await h.request('GET','/kanban/tasks/'+card['id']))['task']['assignee'] == bid
