"""Normalized, capability-gated access to Hermes Desktop's native bot lifecycle.

The phone only supplies bounded profile fields and capability names. Hermes owns
profile creation/configuration, and every successful mutation is read back before
the bridge reports the normalized bot.
"""
import re
import unicodedata

from .bots import BOT_MANAGEMENT_COMMIT, contains_credential_value
from .core import Problem, identifier, opaque, unopaque, only

_BOT_META = 'hermes-bots'
_MAX_TITLE = 96
_MAX_DESCRIPTION = 2000
_MAX_SOUL = 20000
_MAX_SELECTION = 512
_SLUG_RE = re.compile(r'^[a-z0-9][a-z0-9_-]{0,63}$')
_CREATE_FIELDS = {'name', 'description', 'soul', 'provider', 'model', 'skills', 'toolsets', 'mcp_servers'}
_UPDATE_FIELDS = _CREATE_FIELDS | {'confirm_expensive_model'}
_DUPLICATE_LOOK_FIELDS = {
    'sectionId', 'sectionName', 'color', 'custom', 'description', 'groups', 'group',
    'imageKind', 'pinned', 'screenAutoOpen', 'shape',
}


def _clean_title(value):
    if not isinstance(value, str):
        raise Problem(400, 'invalid_bot_name', 'Name is required')
    title = value.strip()
    if (not title or len(title) > _MAX_TITLE or '/' in title or '\\' in title
            or any(unicodedata.category(c).startswith('C') for c in title)):
        raise Problem(400, 'invalid_bot_name', 'Name must be 1 to 96 characters without control characters')
    if contains_credential_value(title):
        raise Problem(400, 'invalid_bot_name', 'Name cannot contain credential-like text')
    return title


def _slugify(title):
    """Mirror Desktop's Unicode-aware profile slug conversion, with Hermes' 64-char limit."""
    text = unicodedata.normalize('NFC', title)
    pieces = []
    for char in text:
        category = unicodedata.category(char)
        if category.startswith(('L', 'N')):
            base = ''.join(c for c in unicodedata.normalize('NFKD', char) if not unicodedata.category(c).startswith('M'))
            if base and base.isascii() and base.isalnum():
                pieces.append(base.lower())
            else:
                pieces.append(f'-u{ord(char):x}-')
        elif char == '_':
            pieces.append('_')
        else:
            pieces.append('-')
    slug = re.sub(r'-+', '-', ''.join(pieces).lower()).strip('-_')
    if len(slug) > 64:
        cut = slug[:64]
        if slug[64] != '-':
            cut = cut.rsplit('-', 1)[0]
        slug = cut.rstrip('-_')
    if not _SLUG_RE.fullmatch(slug) or slug == 'default':
        raise Problem(400, 'invalid_bot_name', 'Name cannot be converted to a supported Hermes profile name')
    return slug


def _text(fields, name, *, required=False, maximum):
    if name not in fields:
        if required:
            raise Problem(400, 'invalid_bot_field', f'{name} is required', field=name)
        return None
    value = fields[name]
    if not isinstance(value, str) or len(value) > maximum or '\x00' in value:
        raise Problem(400, 'invalid_bot_field', f'Invalid {name}', field=name)
    if name in {'description', 'soul'} and contains_credential_value(value):
        raise Problem(400, 'invalid_bot_field', f'{name} cannot contain credential-like text', field=name)
    value = value.strip() if name != 'soul' else value
    if required and not value:
        raise Problem(400, 'invalid_bot_field', f'{name} is required', field=name)
    return value


def _selection(fields, name):
    if name not in fields:
        return None
    value = fields[name]
    if not isinstance(value, list) or len(value) > _MAX_SELECTION:
        raise Problem(400, 'invalid_bot_field', f'Invalid {name}', field=name)
    if any(not isinstance(v, str) or not v.strip() or len(v) > 200 for v in value):
        raise Problem(400, 'invalid_bot_field', f'Invalid {name}', field=name)
    values = [v.strip() for v in value]
    if len(set(values)) != len(values):
        raise Problem(400, 'invalid_bot_field', f'Duplicate values in {name}', field=name)
    return values


def _validate_shape(fields, allowed, required=()):
    if not isinstance(fields, dict) or set(fields) - allowed:
        raise Problem(400, 'invalid_bot_field', 'Unknown bot configuration field')
    for name in required:
        if name not in fields:
            raise Problem(400, 'invalid_bot_field', f'{name} is required', field=name)


class BotManagement:
    """Uses only the audited Desktop RPC lifecycle; never edits profile files directly."""

    def __init__(self, service, auth):
        self.service, self.auth = service, auth

    def backend(self, source):
        source = identifier(source)
        backend = self.service.require(self.auth, source, 'chat.control')
        if ('chat.control' not in self.auth.get('scopes', [])
                or backend.cfg.get('bot_mode_roster') is not True
                or backend.cfg.get('bot_mode_management') is not True
                or backend.cfg.get('installed_commit') != BOT_MANAGEMENT_COMMIT
                or not backend.bot_mode_supported):
            raise Problem(404, 'bot_management_unavailable', 'Bot management is not enabled for this Hermes backend')
        if not backend.connected:
            raise Problem(503, 'upstream_unavailable', 'Hermes is not connected')
        return backend

    async def _profiles(self, backend):
        raw = await backend.rpc('profiles.list', {'include_sessions': False})
        if raw.get('bot_mode_protocol') is not True:
            raise Problem(404, 'bot_management_unavailable', 'Hermes does not expose the audited Bot Mode contract')
        return [row for row in raw.get('profiles', []) if isinstance(row, dict) and isinstance(row.get('name'), str)]

    @staticmethod
    def _namespace_meta(row):
        ui_meta = row.get('ui_meta') if isinstance(row.get('ui_meta'), dict) else {}
        value = ui_meta.get(_BOT_META)
        return dict(value) if isinstance(value, dict) else {}

    @staticmethod
    def _with_meta_patch(params, row, patch):
        # Hermes replaces the complete value of each incoming ui_meta namespace. Re-read the
        # namespace from profiles.list, patch it locally, and use Hermes' per-namespace CAS so
        # title/visibility changes cannot erase Desktop presentation metadata or race a writer.
        params['ui_meta'] = {_BOT_META: {**BotManagement._namespace_meta(row), **patch}}
        revisions = row.get('ui_meta_revisions')
        if isinstance(revisions, dict):
            revision = revisions.get(_BOT_META, 0)
            if isinstance(revision, int) and not isinstance(revision, bool) and revision >= 0:
                params['ui_meta_expected_revisions'] = {_BOT_META: revision}
        return params

    async def _describe(self, backend, profile_id):
        return await backend.rpc('profiles.describe', {'name': profile_id})

    async def _models(self, backend, profile_id):
        raw = await backend.rest('GET', '/api/model/options', query={'profile': profile_id})
        providers = []
        for provider in raw.get('providers', []) if isinstance(raw, dict) else []:
            if not isinstance(provider, dict):
                continue
            provider_id = provider.get('slug') or provider.get('id')
            if not isinstance(provider_id, str) or not provider_id or provider.get('available') is False:
                continue
            models = []
            for model in provider.get('models', []):
                if isinstance(model, str):
                    mid, label = model, model
                elif isinstance(model, dict):
                    mid = model.get('id')
                    label = model.get('name') or model.get('label') or mid
                else:
                    continue
                if isinstance(mid, str) and mid and isinstance(label, str):
                    models.append({'id': mid, 'name': label})
            providers.append({'id': provider_id,
                              'name': str(provider.get('name') or provider.get('label') or provider_id),
                              'available': provider.get('available'), 'configured': provider.get('configured'),
                              'models': models})
        return providers

    async def inventory(self, source='default', bot_id=None):
        profile_id = 'default'
        if bot_id:
            from .bots import BotMode
            adapter = BotMode(self.service, self.auth)
            bot_source, profile_id, _, _ = await adapter.resolve(bot_id)
            if source not in (None, '', 'default', bot_source):
                raise Problem(400, 'invalid_bot_inventory_target', 'Bot ID does not belong to the requested Hermes source')
            source = bot_source
        backend = self.backend(source)
        model_providers = []
        skills, toolsets, mcp_servers = [], [], []
        availability = {'models': False, 'skills': False, 'toolsets': False, 'mcp_servers': False}

        if '/api/model/options' in backend.paths:
            try:
                model_providers = await self._models(backend, profile_id)
                availability['models'] = True
            except Problem:
                pass
        if '/api/skills' in backend.paths:
            try:
                raw = await backend.rest('GET', '/api/skills', query={'profile': profile_id})
                skills = [only(x, 'name description category enabled source tags') for x in raw
                          if isinstance(x, dict) and isinstance(x.get('name'), str)]
                availability['skills'] = True
            except (Problem, TypeError):
                pass
        if '/api/tools/toolsets' in backend.paths:
            try:
                raw = await backend.rest('GET', '/api/tools/toolsets', query={'profile': profile_id})
                toolsets = [only(x, 'name label description enabled available configured') for x in raw
                            if isinstance(x, dict) and isinstance(x.get('name'), str)]
                availability['toolsets'] = True
            except (Problem, TypeError):
                pass
        if '/api/mcp/servers' in backend.paths:
            try:
                raw = await backend.rest('GET', '/api/mcp/servers', query={'profile': profile_id})
                mcp_servers = [only(x, 'name enabled configured connected status tool_count transport')
                               for x in raw.get('servers', []) if isinstance(x, dict) and isinstance(x.get('name'), str)]
                availability['mcp_servers'] = True
            except Problem:
                pass
        return {'source': source, 'profile_id': profile_id, 'providers': model_providers, 'skills': skills,
                'toolsets': toolsets, 'mcp_servers': mcp_servers, 'availability': availability}

    async def _validate_model(self, backend, profile_id, provider, model):
        if (provider is None) != (model is None):
            raise Problem(400, 'invalid_bot_model', 'Select both provider and model', field='model')
        if provider is None:
            return
        if not provider or not model or len(provider) > 200 or len(model) > 300:
            raise Problem(400, 'invalid_bot_model', 'Invalid provider or model', field='model')
        providers = await self._models(backend, profile_id)
        match = next((p for p in providers if p['id'] == provider), None)
        if match is None or not any(m['id'] == model for m in match['models']):
            raise Problem(400, 'invalid_bot_model', 'Choose a provider and model from this Hermes host inventory', field='model')

    @staticmethod
    def _enabled_names(items):
        return {item.get('name') for item in items if isinstance(item, dict) and item.get('enabled') is True
                and isinstance(item.get('name'), str)}

    async def _validate_selections(self, backend, profile_id, fields):
        selections = {name: _selection(fields, name) for name in ('skills', 'toolsets', 'mcp_servers')}
        if not any(value is not None for value in selections.values()):
            return selections, None
        current = await self._describe(backend, profile_id)
        lists = {'skills': current.get('skills', []), 'toolsets': current.get('toolsets', []),
                 'mcp_servers': current.get('mcp_servers', [])}
        for field, selected in selections.items():
            if selected is None:
                continue
            allowed = {item.get('name') for item in lists[field]
                       if isinstance(item, dict) and isinstance(item.get('name'), str)}
            # No arbitrary install/config writes: the phone may select only entries Hermes
            # already describes for this profile.
            if not set(selected) <= allowed:
                raise Problem(400, 'invalid_bot_capability', f'Choose {field} from this bot\'s Hermes inventory', field=field)
        return selections, current

    @staticmethod
    def _configure_result(raw, required, *, partial=False):
        applied = raw.get('applied') if isinstance(raw, dict) else None
        applied = applied if isinstance(applied, dict) else {}
        failed = [field for field in required if applied.get(field) is not True]
        if failed:
            applied_fields = [field for field in required if applied.get(field) is True]
            raise Problem(502, 'bot_configuration_not_applied', 'Hermes did not apply every requested bot field',
                          fields=failed, applied_fields=applied_fields,
                          partial=partial or bool(applied_fields))
        return applied

    async def _check_unique_title(self, profiles, title, *, except_name=None):
        folded = title.casefold()
        for row in profiles:
            if row.get('name') == except_name:
                continue
            meta = (row.get('ui_meta') or {}).get(_BOT_META) or {}
            existing = meta.get('title') or row.get('display_name') or row.get('name')
            if isinstance(existing, str) and existing.strip().casefold() == folded:
                raise Problem(409, 'duplicate_bot_name', 'A Hermes bot with this name already exists')

    async def create(self, source, fields):
        _validate_shape(fields, _CREATE_FIELDS, ('name', 'description'))
        backend = self.backend(source)
        title = _clean_title(fields['name'])
        description = _text(fields, 'description', required=True, maximum=_MAX_DESCRIPTION)
        soul = _text(fields, 'soul', maximum=_MAX_SOUL)
        slug = _slugify(title)
        provider = _text(fields, 'provider', maximum=200)
        model = _text(fields, 'model', maximum=300)
        await self._validate_model(backend, 'default', provider, model)
        profiles = await self._profiles(backend)
        await self._check_unique_title(profiles, title)
        if any(row.get('name') == slug for row in profiles):
            raise Problem(409, 'duplicate_bot_name', 'A Hermes profile already uses the generated name; choose another bot name')

        selections, _ = await self._validate_selections(backend, 'default', fields)
        create = {'name': slug, 'description': description, 'clone_from': 'default', 'share_auth': True}
        if soul is not None:
            create['soul'] = soul
        if provider is not None:
            create.update(provider=provider, model=model)
        await backend.rpc('profiles.create', create)

        configured = {'name': slug, 'ui_meta': {_BOT_META: {'title': title}}}
        required = ['ui_meta']
        try:
            if selections['skills'] is not None:
                new_detail = await self._describe(backend, slug)
                installed = {item.get('name') for item in new_detail.get('skills', []) if isinstance(item, dict)}
                if not set(selections['skills']) <= installed:
                    raise Problem(502, 'bot_create_partially_applied',
                                  'Hermes created the bot but a selected skill is not present in the cloned profile; refresh the Bots list',
                                  profile_id=slug, fields=['skills'])
                configured['disabled_skills'] = sorted(installed - set(selections['skills']))
                required.append('skills')
            if selections['toolsets'] is not None:
                configured['enabled_toolsets'] = selections['toolsets']
                required.append('toolsets')
            if selections['mcp_servers'] is not None:
                configured['enabled_mcp_servers'] = selections['mcp_servers']
                required.append('mcp_servers')
            result = await backend.rpc('profiles.configure', configured)
            self._configure_result(result, required)
        except Problem as exc:
            if exc.code == 'bot_create_partially_applied':
                raise
            raise Problem(502, 'bot_create_partially_applied',
                          'Hermes created the bot profile but did not complete every requested setting; refresh the Bots list before retrying',
                          profile_id=slug, failed_fields=exc.details.get('fields', []),
                          applied_fields=exc.details.get('applied_fields', [])) from None
        return await self._read_bot(source, slug)

    async def _read_bot(self, source, profile_id):
        from .bots import BotMode
        return await BotMode(self.service, self.auth).detail(opaque(source, profile_id))

    async def _resolve(self, bid, include_hidden=False):
        from .bots import BotMode
        adapter = BotMode(self.service, self.auth)
        source, profile_id, backend, row = await adapter.resolve(bid, include_hidden=include_hidden)
        backend = self.backend(source)
        return adapter, source, profile_id, backend, row

    async def update(self, bid, fields):
        _validate_shape(fields, _UPDATE_FIELDS)
        if not fields:
            raise Problem(400, 'invalid_bot_field', 'At least one supported bot field is required')
        adapter, source, profile_id, backend, row = await self._resolve(bid)
        title = _clean_title(fields['name']) if 'name' in fields else None
        description = _text(fields, 'description', maximum=_MAX_DESCRIPTION)
        soul = _text(fields, 'soul', maximum=_MAX_SOUL)
        provider = _text(fields, 'provider', maximum=200)
        model = _text(fields, 'model', maximum=300)
        selections, before = await self._validate_selections(backend, profile_id, fields)
        if provider is not None or model is not None:
            await self._validate_model(backend, profile_id, provider, model)
        if 'confirm_expensive_model' in fields and not isinstance(fields['confirm_expensive_model'], bool):
            raise Problem(400, 'invalid_bot_field', 'confirm_expensive_model must be boolean', field='confirm_expensive_model')

        profiles = await self._profiles(backend)
        if title is not None:
            await self._check_unique_title(profiles, title, except_name=profile_id)

        # Keep Hermes' guarded-model confirmation atomic from the phone's point of view:
        # the model operation runs alone before other requested fields.
        if provider is not None:
            model_params = {'name': profile_id, 'provider': provider, 'model': model}
            if fields.get('confirm_expensive_model') is True:
                model_params['confirm_expensive_model'] = True
            model_result = await backend.rpc('profiles.configure', model_params)
            if isinstance(model_result, dict) and model_result.get('confirm_required') is True:
                raise Problem(409, 'bot_model_confirmation_required', 'Hermes requires confirmation before applying this model',
                              confirm_message=str(model_result.get('confirm_message') or '')[:1000])
            self._configure_result(model_result, ['model'])

        config = {'name': profile_id}
        required = []
        if title is not None:
            self._with_meta_patch(config, row, {'title': title})
            required.append('ui_meta')
        if description is not None:
            config['description'] = description
            required.append('description')
        if soul is not None:
            config['soul'] = soul
            required.append('soul')
        if selections['skills'] is not None:
            installed = {item.get('name') for item in (before or {}).get('skills', []) if isinstance(item, dict)}
            config['disabled_skills'] = sorted(installed - set(selections['skills']))
            required.append('skills')
        if selections['toolsets'] is not None:
            config['enabled_toolsets'] = selections['toolsets']
            required.append('toolsets')
        if selections['mcp_servers'] is not None:
            config['enabled_mcp_servers'] = selections['mcp_servers']
            required.append('mcp_servers')
        if required:
            result = await backend.rpc('profiles.configure', config)
            self._configure_result(result, required, partial=provider is not None)

        # Read the Desktop roster and profile editor snapshot again. We never tell the
        # phone a write succeeded based only on a request being sent.
        updated = await self._read_bot(source, profile_id)
        if title is not None and updated['name'] != title:
            raise Problem(502, 'bot_configuration_not_applied', 'Hermes did not persist the bot name', fields=['name'])
        if description is not None and updated['description'] != description:
            raise Problem(502, 'bot_configuration_not_applied', 'Hermes did not persist the bot description', fields=['description'])
        if soul is not None and updated.get('soul') != soul:
            raise Problem(502, 'bot_configuration_not_applied', 'Hermes did not persist the bot instructions', fields=['soul'])
        if provider is not None and (updated.get('provider') != provider or updated.get('model') != model):
            raise Problem(502, 'bot_configuration_not_applied', 'Hermes did not persist the selected model', fields=['model'])
        for field, result_key in (('skills', 'skills'), ('toolsets', 'toolsets'), ('mcp_servers', 'mcp_servers')):
            selected = selections[field]
            if selected is not None and field == 'skills':
                actual = {x['name'] for x in updated.get(result_key, []) if x.get('enabled') is True}
                if actual != set(selected):
                    raise Problem(502, 'bot_configuration_not_applied', 'Hermes did not persist the selected skills', fields=[field])
            elif selected is not None and field == 'mcp_servers':
                actual = {x['name'] for x in updated.get(result_key, []) if x.get('enabled') is True}
                if actual != set(selected):
                    raise Problem(502, 'bot_configuration_not_applied', 'Hermes did not persist the selected MCP servers', fields=[field])
        return updated

    async def hide(self, bid, hidden):
        if not isinstance(hidden, bool):
            raise Problem(400, 'invalid_bot_field', 'hidden must be boolean', field='hidden')
        adapter, source, profile_id, backend, row = await self._resolve(bid, include_hidden=True)
        if row.get('is_default') or profile_id == 'default':
            raise Problem(400, 'default_bot_protected', 'The default Hermes profile cannot be hidden')
        current = bool((row.get('ui_meta') or {}).get(_BOT_META, {}).get('hidden'))
        if current != hidden:
            params = self._with_meta_patch({'name': profile_id}, row, {'hidden': hidden})
            result = await backend.rpc('profiles.configure', params)
            self._configure_result(result, ['ui_meta'])
        profiles = await self._profiles(backend)
        verified = next((p for p in profiles if p.get('name') == profile_id), None)
        persisted = bool((((verified or {}).get('ui_meta') or {}).get(_BOT_META) or {}).get('hidden'))
        if persisted != hidden:
            raise Problem(502, 'bot_configuration_not_applied', 'Hermes did not persist the visibility change', fields=['hidden'])
        return {'id': bid, 'profile_id': profile_id, 'hidden': hidden,
                'canonical_chat_available': bool(row.get('canonical_session')),
                'history_preserved': True}

    async def duplicate(self, bid):
        """Clone a Hermes profile through the native create RPC; sessions are never cloned."""
        adapter, source, profile_id, backend, row = await self._resolve(bid)
        profiles = await self._profiles(backend)
        names = {profile.get('name') for profile in profiles}
        display_name = adapter_detail_name(source, row)
        for number in range(2, 100):
            suffix = f'-{number}'
            candidate_id = profile_id[:64 - len(suffix)].rstrip('-_') + suffix
            copy_suffix = ' (copy)' if number == 2 else f' (copy {number - 1})'
            candidate_title = display_name[:_MAX_TITLE - len(copy_suffix)].rstrip() + copy_suffix
            if candidate_id in names:
                continue
            try:
                await self._check_unique_title(profiles, candidate_title)
            except Problem as exc:
                if exc.code == 'duplicate_bot_name':
                    continue
                raise
            break
        else:
            raise Problem(409, 'bot_duplicate_name_exhausted', 'No free Hermes profile name is available for a duplicate')

        description = row.get('description') if isinstance(row.get('description'), str) else ''
        # Desktop duplicates the source profile's config, SOUL and installed
        # skills using this native Hermes operation. It does not copy sessions.
        await backend.rpc('profiles.create', {'name': candidate_id, 'clone_from': profile_id,
                                              'description': description, 'share_auth': True})
        try:
            source_meta = self._namespace_meta(row)
            # Desktop carries Bot Mode presentation metadata to the clone. Keep only known
            # BotMeta fields, while a new profile must not inherit canonical-chat identity,
            # creation time, or hidden state. Avatar bytes travel through Hermes' asset RPC.
            duplicate_meta = {key: source_meta[key] for key in _DUPLICATE_LOOK_FIELDS if key in source_meta}
            duplicate_meta.update(title=candidate_title, hidden=False)
            new_profiles = await self._profiles(backend)
            new_row = next((profile for profile in new_profiles if profile.get('name') == candidate_id), None)
            if new_row is None:
                raise Problem(502, 'bot_duplicate_partially_applied',
                              'Hermes created the duplicate but did not return its new profile metadata',
                              profile_id=candidate_id)
            configured = await backend.rpc('profiles.configure', self._with_meta_patch(
                {'name': candidate_id}, new_row, duplicate_meta))
            self._configure_result(configured, ['ui_meta'])
            if row.get('has_avatar'):
                asset = await backend.rpc('profiles.get_asset', {'name': profile_id, 'asset': 'avatar'})
                data = asset.get('data') if isinstance(asset, dict) and asset.get('found') is True else None
                if isinstance(data, str) and len(data) <= 2_800_000 and data.startswith((
                        'data:image/png;base64,', 'data:image/jpeg;base64,', 'data:image/webp;base64,')):
                    copied = await backend.rpc('profiles.set_asset', {
                        'name': candidate_id, 'asset': 'avatar', 'data': data})
                    if not isinstance(copied, dict) or copied.get('ok') is not True:
                        raise Problem(502, 'bot_duplicate_partially_applied',
                                      'Hermes created the duplicate but did not copy its avatar',
                                      profile_id=candidate_id)
        except Problem as exc:
            # The profile is already a native Hermes object; report partial state and never
            # delete it automatically as a failed UI metadata write might have raced another user.
            if exc.code == 'bot_duplicate_partially_applied':
                raise
            raise Problem(502, 'bot_duplicate_partially_applied',
                          'Hermes created the duplicate profile but did not finish its Bot Mode title; refresh the Bots list',
                          profile_id=candidate_id) from None

        duplicated = await self._read_bot(source, candidate_id)
        original = await self._read_bot(source, profile_id)
        if duplicated.get('canonical_chat_available'):
            raise Problem(502, 'bot_duplicate_contract_mismatch',
                          'Hermes returned a duplicate with a canonical chat; refresh and inspect the bot',
                          profile_id=candidate_id)
        comparisons = ('description', 'soul', 'model', 'provider')
        if any(duplicated.get(field) != original.get(field) for field in comparisons):
            raise Problem(502, 'bot_duplicate_contract_mismatch',
                          'Hermes did not copy the source bot configuration completely',
                          profile_id=candidate_id)
        for field in ('skills', 'toolsets', 'mcp_servers'):
            before = {(item.get('name'), item.get('enabled')) for item in original.get(field, [])}
            after = {(item.get('name'), item.get('enabled')) for item in duplicated.get(field, [])}
            if before != after:
                raise Problem(502, 'bot_duplicate_contract_mismatch',
                              'Hermes did not copy the source bot capabilities completely',
                              profile_id=candidate_id, field=field)
        return duplicated


def adapter_detail_name(source, row):
    from .bots import bot_row
    return bot_row(source, row)['name']
