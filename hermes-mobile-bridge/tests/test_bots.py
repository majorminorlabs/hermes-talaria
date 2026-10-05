"""Sanitized Studio-shaped wire fixtures; names never enter production code."""
import pytest
from hermes_mobile_bridge.bots import bot_row
from hermes_mobile_bridge.core import opaque

pytestmark = pytest.mark.asyncio

SKILLS = ['research-terminal', 'arxiv', 'hermes-bluebubbles-operations', 'llama-cpp', 'llm-wiki', 'online-price-comparison']


def studio_rows():
    return [{'name': name, 'is_default': name == 'default', 'display_name': title,
             'description': 'Configured Studio identity', 'model': 'studio-model', 'provider': 'studio-provider',
             'path': '/private/never-expose', 'ui_meta': {'hermes-bots': {'title': title}},
             'canonical_session': {'id': name + '-root', 'resolved_id': name + '-tip', 'title': 'Bot Chat', 'last_active': 10}}
            for name, title in [('research-orchestrator', 'Research Orchestrator'), ('default', 'Hermes'), ('research-worker', 'Research Worker')]]


async def enable(h):
    h.fake.bot_roster = studio_rows()
    h.service.backends['default'].cfg['bot_mode_roster'] = True
    h.service.backends['default'].bot_mode_supported = True


async def test_roster_dynamic_refresh_remove_reconnect(harness):
    h = harness
    await enable(h)
    rows = (await h.request('GET', '/bots'))['bots']
    assert [x['name'] for x in rows] == ['Research Orchestrator', 'Hermes', 'Research Worker']
    assert len([x for x in rows if x['is_default']]) == 1
    assert '/private/' not in str(rows)
    h.fake.bot_roster.append({'name': 'new-bot', 'display_name': 'New Bot'})
    assert len((await h.request('GET', '/bots'))['bots']) == 4
    h.fake.bot_roster[0]['ui_meta']['hermes-bots']['hidden'] = True
    assert len((await h.request('GET', '/bots'))['bots']) == 3
    h.fake.bot_roster.pop()
    await h.client.close()
    await h.bridge_runner.cleanup()
    await h.start_bridge()
    assert len((await h.request('GET', '/bots'))['bots']) == 2
    await h.request('GET', '/bots/' + opaque('default', 'new-bot'), expected=404)


async def test_detail_attached_skills_and_canonical_tip(harness):
    h = harness
    await enable(h)
    h.fake.bot_details['research-orchestrator'] = {'soul': 'Configured SOUL', 'skills': [{'name': s, 'enabled': True, 'path': '/secret'} for s in SKILLS],
        'model': {'default': 'studio-model', 'provider': 'studio-provider'}, 'toolsets': [{'name': 'terminal', 'enabled': True}],
        'mcp_servers': [{'name': 'local', 'enabled': True, 'env': {'API_KEY': 'never'}}]}
    bid = opaque('default', 'research-orchestrator')
    d = await h.request('GET', '/bots/' + bid)
    assert [s['name'] for s in d['skills']] == SKILLS
    assert d['soul_summary'] == 'Configured SOUL'
    assert 'never' not in str(d) and '/secret' not in str(d)
    h.fake.sessions['native'] = {'stored': 'research-orchestrator-tip', 'status': 'idle', 'title': 'Bot Chat', 'messages': [{'id': 1, 'role': 'user', 'content': 'Existing Studio conversation'}]}
    chat = await h.request('GET', '/bots/' + bid + '/conversation')
    assert chat['conversation']['id'] == 'botchat.' + bid
    assert chat['conversation']['read_only'] is True
    assert chat['messages'][0]['content'] == 'Existing Studio conversation'
    assert 'session.resume' not in h.fake.methods and 'session.create' not in h.fake.methods
    # A compressed tip moves; the next read resolves by title rather than the previous ID.
    h.fake.bot_roster[0]['canonical_session']['resolved_id'] = 'next-tip'
    h.fake.sessions['native']['stored'] = 'next-tip'
    assert (await h.request('GET', '/bots/' + bid + '/conversation'))['messages'] == chat['messages']


async def test_capability_scope_fallback_no_mock_leak(harness):
    h = harness
    caps = await h.request('GET', '/capabilities')
    assert caps['profiles']['default']['features']['profiles'] is True
    assert caps['profiles']['default']['features']['botMode'] is False
    assert (await h.request('GET', '/bots'))['bots'] == []
    await enable(h)
    assert (await h.request('GET', '/capabilities'))['profiles']['default']['features']['botMode'] is True
    await h.request('GET', '/bots/' + opaque('private', 'default'), expected=403)
    h.fake.bot_roster = []
    assert (await h.request('GET', '/bots'))['bots'] == []


async def test_missing_chat_never_mints(harness):
    h = harness
    await enable(h)
    h.fake.bot_roster[0]['canonical_session'] = None
    await h.request('GET', '/bots/' + opaque('default', 'research-orchestrator') + '/conversation', expected=404)
    assert h.fake.prompts == 0 and 'session.create' not in h.fake.methods


async def test_activity_unknown_not_guessed_idle():
    r = bot_row('default', {'name': 'default', 'last_session': {'last_active': 12}, 'canonical_session': {'last_active': 10}})
    assert r['name'] == 'Hermes' and r['status'] == 'unknown' and r['last_active'] == 12
