> Historical implementation/design reference. For current 0.2.0 navigation,
> Capture/voice semantics and capability boundaries, see [Use Talaria](docs/USING_TALARIA.md)
> and [current release notes](CHANGELOG.md). Agents are underlying Hermes bots/profiles.

# Hermes Bot management from iPhone

Bot Mode uses Hermes profiles as its source of truth. The bridge calls the same
profile RPCs used by Hermes Desktop and never writes profile files itself:

- `profiles.create` creates a normal Hermes profile, cloning the host's
  `default` profile as Desktop does. It shares the host auth pool; no provider
  credentials are returned to the phone.
- `profiles.configure` updates the profile description, `SOUL.md`, model pin,
  installed-skill selection, configured toolsets/MCP servers, and the Bot Mode
  display title in `profile.yaml` metadata.
- `profiles.describe` and `profiles.list` read the saved values back before the
  bridge reports success. Profile identity is the native Hermes profile name;
  changing the display title never renames that identity or changes its chat.
- Hiding sets `ui_meta['hermes-bots'].hidden`. It only removes a bot from the
  Bot Mode roster. The Hermes profile and canonical `Bot Chat` history remain.
  Unhide sets the flag to `false`. Both operations re-read the current
  `hermes-bots` namespace and use Hermes' namespace revision check, preserving
  the display title and other Desktop metadata. The default profile cannot be
  hidden.
- Duplicating calls `profiles.create` with the source profile as `clone_from`.
  Hermes copies profile configuration, instructions, and installed skills into
  a new profile; it does not copy session history. The bridge carries across
  the supported Desktop Bot Mode presentation metadata and avatar, resets
  hidden state, and leaves canonical-chat identity/history and creation time
  behind. It chooses a free `-2`, `-3`, … identity and a matching `(copy)`
  display title, then reads the clone back from Hermes. Each duplicate starts
  without a canonical `Bot Chat`.

The phone supplies a display title. The bridge derives a Unicode-aware Hermes
profile slug, checks it against all profiles including hidden ones, and lets
Hermes enforce its own reserved-name and creation rules. Description is the
Hermes profile description, not the separate Hermes permission role. Model and
provider must be a pair present in that backend's live model inventory. Skill,
toolset, and MCP selections are restricted to entries Hermes already reports
for the target profile, with a maximum of 512 selected entries per category;
this interface does not install skills, configure MCP commands, or edit
arbitrary profile files.

The live inventory is available as `GET /mobile/v1/bots/inventory`. Pass
`profile=<authorized backend>` for creation inventory. Pass `bot_id=<opaque bot
ID>` to retrieve that bot's profile-specific installed capabilities for edit.
Inventory entries contain selector metadata only; provider credentials, API
keys, base URLs, MCP commands, environment values, and filesystem paths are
excluded. Credential-like values in bot titles, descriptions, or SOUL text are
rejected on writes and obvious token/private-key forms are withheld from mobile
detail responses.

## Capability and permission gates

Mutations require all of the following:

- The mobile credential has `read` and `chat.control` for the backend.
- The backend grants `bot_mode_roster: true` and the separate
  `bot_mode_management: true` in its private bridge configuration.
- The connected Hermes backend advertises the Bot Mode protocol and is running
  the audited `4bb9e57bfde8a0affb5553eff13ed6e1f14147f1` lifecycle contract.

The bridge reports per-backend `botCreate`, `botEdit`, `botHide`, `botDuplicate`,
and `botInventory` capabilities. Older or disconnected backends return these as
unavailable so clients can hide management controls. Bot Chat access alone
does not enable profile mutation.

Hermes may require a confirmation before applying a guarded model change. The
bridge returns that confirmation requirement without reporting the model as
saved; a client should show Hermes' message and retry only after the user
confirms. A successful edit is re-read from Hermes and returned to the client.
If Hermes creates a profile but rejects a later Bot Mode metadata or capability
write, the bridge reports an explicit partial-create error and profile ID so the
client can refresh. It does not auto-delete the profile or its host state.

## Deletion and history

Mobile deletion is not exposed. Hermes' native `profile delete` permanently
removes the profile, stops its gateway and related backends, removes the
profile's files, and settles its persisted identity. Hiding is the supported
reversible action and preserves canonical chats. A future delete action would
need a separate confirmation that explains these Hermes semantics.

## Diagnostics

If management controls are absent, inspect `GET /mobile/v1/capabilities` for
the backend and check the two private bridge grants, Hermes connection state,
the negotiated `bot_mode_protocol`, and the installed Hermes commit. If a save
returns an error, reopen or refresh the bot detail to see the values Hermes
actually stored. Do not repair a failed edit by writing `profile.yaml`,
`config.yaml`, or `SOUL.md` from the phone.

## Physical acceptance — 2026-10-04

The phone created a real temporary native bot with name, description and SOUL,
inheriting the host's safe model/provider. Description and SOUL edits were verified
in Hermes Desktop. Immediate discovery, refreshed detail, background/foreground,
app relaunch and writable canonical chat passed. Phone Hide removed it from both
visible rosters and retained it in Desktop's Hidden list. Its canonical session and
ten messages were unchanged by Hide. Optional provider/model/skill selection and
Duplicate retain the earlier automated/Studio coverage; they were not repeated on
this physical pass. See [BOT_MODE_VALIDATION.md](BOT_MODE_VALIDATION.md) for evidence.
