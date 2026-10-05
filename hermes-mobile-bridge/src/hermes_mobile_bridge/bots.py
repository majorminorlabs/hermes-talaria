"""Bot Mode adapter for the audited profile-backed Desktop roster.

No raw paths, arbitrary config or credentials cross the inventory boundary.
A backend explicitly grants whole-roster reads and, separately, canonical chat control.
"""
import asyncio
import re
from .core import Problem, identifier, opaque, unopaque, only, message

AUDITED_COMMITS = ('2a4c9afd7bd', '4bb9e57bfde8a0affb5553eff13ed6e1f14147f1')
BOT_MANAGEMENT_COMMIT = '4bb9e57bfde8a0affb5553eff13ed6e1f14147f1'
_CREDENTIAL_PATTERNS = tuple(re.compile(pattern, re.IGNORECASE) for pattern in (
    r'\bsk-[A-Za-z0-9_-]{20,}\b', r'\b(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9_]{20,}\b',
    r'\bgithub_pat_[A-Za-z0-9_]{20,}\b', r'\bxox[baprs]-[A-Za-z0-9-]{10,}\b',
    r'\bAKIA[0-9A-Z]{16}\b', r'\bBearer\s+[A-Za-z0-9._~-]{20,}',
    r'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----'))


def contains_credential_value(value):
    return isinstance(value, str) and any(pattern.search(value) for pattern in _CREDENTIAL_PATTERNS)


def bot_row(source, row):
    name = identifier(row['name'])
    meta = (row.get('ui_meta') or {}).get('hermes-bots') or {}
    title = meta.get('title') or row.get('display_name') or ('Hermes' if name == 'default' else name.replace('-', ' ').replace('_', ' ').title())
    if contains_credential_value(title):
        title = 'Private bot'
    sessions = [s for s in (row.get('canonical_session'), row.get('last_session'), row.get('worker_session')) if isinstance(s, dict)]
    last = max(sessions, key=lambda s: s.get('last_active') or 0, default={})
    description = row.get('description') if isinstance(row.get('description'), str) else meta.get('description') or ''
    if contains_credential_value(description):
        description = ''
    return {'id': opaque(source, name), 'name': title.strip(), 'profile_id': name,
            'is_default': bool(row.get('is_default') or name == 'default'),
            'description': description,
            'model': row.get('model'), 'provider': row.get('provider'),
            'status': 'unknown', 'last_active': last.get('last_active'),
            'activity': only(last, 'title preview last_active'), 'has_avatar': bool(row.get('has_avatar')),
            'canonical_chat_available': isinstance(row.get('canonical_session'), dict),
            'source': 'hermes_desktop_profiles', 'activity_coverage': 'persisted_sessions_and_this_backend_only'}


class BotMode:
    def __init__(self, service, auth):
        self.service, self.auth = service, auth

    async def roster(self, source, include_hidden=False):
        backend = self.service.require(self.auth, source)
        if not backend.cfg.get('bot_mode_roster'):
            raise Problem(404, 'bot_mode_unavailable', 'Bot Mode is not enabled on this backend')
        raw = await backend.rpc('profiles.list', {'include_sessions': True})
        if raw.get('bot_mode_protocol') is not True:
            raise Problem(404, 'bot_mode_unavailable', 'This Hermes backend has no audited Bot Mode contract')
        rows = [r for r in raw.get('profiles', []) if isinstance(r, dict)]
        if not include_hidden:
            rows = [r for r in rows if not (r.get('ui_meta') or {}).get('hermes-bots', {}).get('hidden')]
        return backend, rows

    async def list(self):
        result = []
        for source in self.service.profiles(self.auth):
            if self.service.backends[source].cfg.get('bot_mode_roster'):
                _, rows = await self.roster(source)
                result.extend(bot_row(source, r) for r in rows)
        return result

    async def resolve(self, bid, include_hidden=False):
        source, name = unopaque(bid)
        backend, rows = await self.roster(source, include_hidden=include_hidden)
        row = next((r for r in rows if r.get('name') == name), None)
        if row is None:
            raise Problem(404, 'not_found', 'Bot is no longer in the Studio roster')
        return source, name, backend, row

    async def detail(self, bid):
        source, name, backend, row = await self.resolve(bid)
        raw = await backend.rpc('profiles.describe', {'name': name})
        result = bot_row(source, row)
        model = raw.get('model') or {}
        soul = raw.get('soul') if isinstance(raw.get('soul'), str) else ''
        soul_redacted = contains_credential_value(soul)
        if soul_redacted:
            soul = ''
        result.update(model=model.get('default') or result['model'], provider=model.get('provider') or result['provider'],
                      soul=soul[:20000], soul_summary=soul[:12000] or None,
                      skills=[only(s, 'name enabled') for s in raw.get('skills', [])],
                      toolsets=[only(t, 'name enabled available') for t in raw.get('toolsets', [])],
                      mcp_servers=[only(m, 'name enabled transport') for m in raw.get('mcp_servers', [])],
                      editable_fields={'name': True, 'description': True, 'soul': len(soul) <= 20000 and not soul_redacted,
                                       'model': '/api/model/options' in backend.paths,
                                       'skills': True, 'toolsets': True, 'mcp_servers': True,
                                       'hide': not result['is_default'], 'duplicate': True},
                      soul_redacted=soul_redacted,
                      hidden=bool((row.get('ui_meta') or {}).get('hermes-bots', {}).get('hidden')),
                      config_metadata={'toolsets_pinned': raw.get('toolsets_pinned'), 'source': 'profiles.describe'})
        if row.get('has_avatar'):
            asset = await backend.rpc('profiles.get_asset', {'name': name, 'asset': 'avatar'})
            data = asset.get('data')
            if isinstance(data, str) and len(data) <= 2800000 and data.startswith(('data:image/png;base64,', 'data:image/jpeg;base64,', 'data:image/webp;base64,')):
                result['avatar_data'] = data
        # Safe allowlisted metadata only. Optional resources stay absent on failure.
        for resource, path in [('routines', '/api/cron/jobs'), ('memory', '/api/memory')]:
            try:
                value = await backend.rest('GET', path, query={'profile': name})
                if resource == 'routines' and isinstance(value, list):
                    result[resource] = [only(v, 'id name enabled last_run_at last_status next_run_at') for v in value]
                elif resource == 'memory' and isinstance(value, dict):
                    result['memory_metadata'] = {'active': value.get('active'), 'providers': [only(v, 'name configured') for v in value.get('providers', [])], 'builtin_bytes': only(value.get('builtin_files') or {}, 'memory user')}
            except Problem:
                pass
        try:
            plugins = await backend.rpc('plugins.manage', {'profile': name, 'action': 'list'})
            result['plugins'] = [only(v, 'name enabled') for v in plugins.get('plugins', [])]
        except Problem:
            pass
        return result

    def management_capabilities(self, source):
        """Per-source feature gate; roster reads never imply permission to mutate bots."""
        if source not in self.auth.get('profiles', []) or 'chat.control' not in self.auth.get('scopes', []):
            return {'botCreate': False, 'botEdit': False, 'botHide': False, 'botDuplicate': False, 'botInventory': False}
        backend = self.service.backends.get(source)
        available = bool(backend and backend.connected and backend.bot_mode_supported
                         and backend.cfg.get('bot_mode_roster') is True
                         and backend.cfg.get('bot_mode_management') is True
                         and backend.cfg.get('installed_commit') == BOT_MANAGEMENT_COMMIT)
        inventory = bool(available and any(path in backend.paths for path in (
            '/api/model/options', '/api/skills', '/api/tools/toolsets', '/api/mcp/servers')))
        return {'botCreate': available, 'botEdit': available, 'botHide': available, 'botDuplicate': available,
                'botInventory': inventory}

    def capabilities(self, source):
        return self.management_capabilities(source)

    async def inventory(self, source='default', bot_id=None):
        from .bot_management import BotManagement
        return await BotManagement(self.service, self.auth).inventory(source, bot_id=bot_id)

    async def create(self, fields, source='default'):
        from .bot_management import BotManagement
        return await BotManagement(self.service, self.auth).create(source, fields)

    async def update(self, bid, fields):
        from .bot_management import BotManagement
        return await BotManagement(self.service, self.auth).update(bid, fields)

    async def hide(self, bid, hidden=True):
        from .bot_management import BotManagement
        return await BotManagement(self.service, self.auth).hide(bid, hidden)

    async def duplicate(self, bid):
        from .bot_management import BotManagement
        return await BotManagement(self.service, self.auth).duplicate(bid)

    async def conversation(self, bid):
        source, name, backend, bot = await self.resolve(bid)
        row = await self.lookup(backend, name, bot)
        if row is None:
            raise Problem(404, 'bot_chat_unavailable', 'This bot has no canonical Bot Chat yet')
        conv = self.bind(bid, source, name, bot, row)
        cursor = self.service.store.cursor()
        history = await backend.rest('GET', f'/api/sessions/{conv["stored_id"]}/messages', query={'profile': name})
        return {'conversation': self.service.conversation_view(conv) | {'read_only': not self.can_control(backend)},
                'messages': [message(m) for m in history.get('messages', [])], 'cursor': cursor,
                'observed_runs': [self.service.run_view(r) for r in self.service.store.runs([source], limit=200) if r['conversation_id'] == conv['id']]}

    def can_control(self, backend):
        return backend.cfg.get('bot_chat_control') is True and 'chat.control' in self.auth['scopes']

    async def lookup(self, backend, name, bot):
        # Indexed exact-title lookup EVERY open/read. Never use recency or a saved id pin.
        raw = await backend.rpc('session.list', {'profile': name, 'title': 'Bot Chat', 'include_hidden': True})
        rows = raw.get('sessions', [])
        if not rows:
            if bot.get('canonical_session'):
                raise Problem(409, 'bot_chat_unconfirmed', 'Could not confirm the existing canonical Bot Chat; retry opening it')
            return None
        row = rows[0]
        if row.get('title') != 'Bot Chat' or len(rows) != 1 or (bot.get('canonical_session') and row.get('id') != bot['canonical_session'].get('id')):
            raise Problem(502, 'bot_chat_contract_mismatch', 'Hermes did not resolve the exact Bot Chat identity')
        return row

    def bind(self, bid, source, name, bot, row, live=None, owned=False):
        store = self.service.store
        sid = identifier(row.get('resolved_id') or row['id'])
        existing = store.db.execute("SELECT id FROM conversations WHERE profile=? AND json_extract(data,'$.bot_id')=?", (source, bid)).fetchone()
        alias = store.db.execute('SELECT conversation_id FROM aliases WHERE profile=? AND stored_id=?', (source, sid)).fetchone()
        cid = existing[0] if existing else alias[0] if alias else 'botchat.' + bid
        old = store.db.execute('SELECT live_id FROM conversations WHERE id=?', (cid,)).fetchone()
        if existing and alias and alias[0] != cid:
            raise Problem(409, 'bot_chat_alias_conflict', 'Canonical history already belongs to another mobile conversation')
        data = only(row, 'model provider started_at message_count last_active preview archived') | {
            'title': 'Bot Chat', 'source': 'desktop', 'canonical': True,
            'bot_id': bid, 'bot_profile': name, 'bot_name': bot_row(source, bot)['name']}
        for field in ('model', 'provider'):
            if bot.get(field):
                data[field] = bot[field]
        store.save_conversation(cid, source, sid, live or (old[0] if old else None), owned, data)
        return store.get('conversations', cid)

    async def open(self, bid):
        source, name, backend, bot = await self.resolve(bid)
        self.service.require(self.auth, source, 'chat.control')
        if not self.can_control(backend):
            raise Problem(403, 'bot_chat_read_only', 'Writable Bot Chat is not enabled for this source')
        async with self.service.locks.setdefault('botchat.' + bid, asyncio.Lock()):
            # Adopt before minting; failures or a positive roster with an empty lookup never mean absent.
            row = await self.lookup(backend, name, bot)
            created = None
            if row is None:
                created = await backend.rpc('session.create', {'profile': name, 'title': 'Bot Chat', 'hidden': True,
                    'follow_profile_config': True, 'close_on_disconnect': False, 'idempotency_key': 'mobile-botchat-' + bid})
                runtime = identifier(created['session_id'])
                try:
                    # Same modern Desktop eager write: persist the hidden empty row without an intro/model turn.
                    await backend.rpc('session.title', {'session_id': runtime, 'title': 'Bot Chat'})
                except Problem:
                    # A concurrent writer can win UNIQUE(title). Adopt only a confirmed registry row.
                    row = await self.lookup(backend, name, bot)
                    if row is None:
                        raise
                row = row or await self.lookup(backend, name, bot)
                if row is None:
                    raise Problem(502, 'bot_chat_initialization_failed', 'Hermes did not persist the canonical Bot Chat')
                if (row.get('resolved_id') or row['id']) != created.get('stored_session_id'):
                    # Only our own unused runtime is retired, never the winner or its history.
                    await backend.rpc('session.close', {'session_id': runtime})
                    created = None
            conv = self.bind(bid, source, name, bot, row, created.get('session_id') if created else None, bool(created))
            await self.service.ensure_live(conv, allow_running=True)
        return await self.conversation(bid)
