> Historical implementation/design reference. For current 0.2.0 navigation,
> Capture/voice semantics and capability boundaries, see [Use Talaria](docs/USING_TALARIA.md)
> and [current release notes](CHANGELOG.md). Agents are underlying Hermes bots/profiles.

# Talaria design

Talaria is the native iPhone companion for Hermes running on the Mac Studio.
The name comes from the winged sandals of Hermes. Hermes stays the system
being controlled; Talaria is only the phone client.

## 1. What Hermes Desktop does (observed)

Studied from `apps/desktop` (`DESIGN.md`, `styles.css`, `components/ui`,
`plugins/hermes-bots`) at `4bb9e57` and the running app.

- **One blue.** `--theme-primary` is `#0053FD`. It marks selection, toggles,
  links and "learned" badges. Everything else is neutral text at four
  strengths (94 / 74 / 54 / 36 %).
- **Flat, not boxed.** No card-in-card. Group with whitespace and one
  hairline. Inline widgets get a soft fill and no border; their actions sit
  outside the panel.
- **Small radii.** Badges are 3 px "app radius", not pills. Text buttons are
  square; only icon buttons are rounded.
- **Badges** are a tinted fill with matching text (`default` = primary 10 %,
  `muted`, `success`, `warn`, `destructive`).
- **Status is a dot.** A small green dot beside a bot name means active. It
  pulses once every 5 s, not continuously.
- **Bot identity** is a colored blob face with eyes. It is derived from the
  profile name and rasterized to a PNG avatar per profile. The default
  profile has no color of its own.
- **Technical metadata is quiet.** Session titles, counts (`×273`), versions
  (`# v0.21.5`) and IDs use small secondary or tertiary type. Monospace is
  used only where the value is literally code.
- **Section labels** are small, uppercase and tracked (`BOTS`, `SESSIONS`).
  Counts ride beside tab labels (`Skills 118`).
- **Errors.** Red is reserved for explicit failure. Ambiguous outcomes use
  neutral notices. The real explanation is available on expansion.
- **Never the word "Loading…".** Use a real loader or skeleton.

## 2. How Talaria translates it

The aim is not to copy the desktop layout onto a phone. Talaria uses native
iOS structure (tab bar, navigation stacks, inset lists, sheets) and carries
Desktop's DNA inside it.

| Desktop | Talaria |
| --- | --- |
| `#0053FD` primary | Talaria blue `#0150F9`, sampled from the mark. It is within 2 % of Desktop's primary. Dark mode lifts it to `#4D8BFF` so text and links stay legible. |
| Badge (tinted fill, 3 px radius) | `Tag`: caption2 semibold, 4 pt continuous radius, 12 % tint. |
| Status dot with a 5 s pulse | `StatusDot`: a 1 s ring about every 4.7 s. Nothing animates between beats, so the render loop idles. Off under Reduce Motion. |
| Uppercase section labels | `SectionHeader` on every list section, with an optional trailing count or action. VoiceOver reads it in title case. |
| Blob faces / profile glyph | `ProfileAvatar`: the Desktop face PNG when the bridge provides one. Otherwise a Desktop-style glyph: the soft profile hue with an initial. The default profile gets a neutral home glyph, as on Desktop. |
| Widget shell (fill, no border) | `.panel()`: a soft secondary fill with no stroke, used for the live run, approvals, tool groups and failures. |
| Key/value metadata table | `KeyValueRow`. Monospace is used only for IDs, paths and codes. |
| Neutral notice vs. red failure | `StatusCopy` maps raw codes to plain titles. `FailureCallout` keeps the raw code under **Details**. |
| Blue switches | `.accentSwitches()` on screens with toggles. A root tint would also repaint destructive bordered buttons. |

## 3. Brand

- **Canonical mark:** the blue winged sandal, `Hermes/Resources/Assets.xcassets/TalariaMark`.
  It is the only Talaria logo. Never use an SF Symbol or robot/AI glyph in its place.
- **App icon:** the mark in `#0150F9` on pure white, with no text and no ring.
  It spans 70 % of the canvas so it clears the iOS mask and still reads at 40 pt.
  It is generated from the supplied artwork by re-compositing its coverage
  (the shape is unchanged). Talaria ships one icon for all appearances
  because the white tile is part of the identity.
- **In-app use is sparse.** It appears in the identity footer of More and in
  Settings › About, on the first-run "Pair with your Mac" welcome, and in the
  Add Host sheet. Operational screens stay
  content-first. The Home title is the word **Talaria**.
- **Naming:** "Talaria" refers to this client. "Hermes" refers to the agent on
  the Mac ("Connected to Hermes on Mac Studio"). The bundle ID stays
  `xyz.majorminor.talaria`.

## 4. Color and status semantics

The accent is used only for interaction and selection: links, selected chips,
the send button and the brand. Status colors keep fixed meanings and always
come with a word or a glyph, never color alone.

| Meaning | Color | Glyph |
| --- | --- | --- |
| Active / running | accent blue | pulsing dot |
| Needs you | orange | hand / question |
| Succeeded | green | checkmark |
| Failed | red | xmark octagon |
| Idle / unknown / cancelled | secondary | none or minus |
| Steering | indigo | turn-down-right arrow |

## 5. Typography

- System fonts only (SF Pro / SF Mono). Dynamic Type throughout.
- Titles are semibold. Body text is regular. Metadata is footnote or caption in
  secondary color. Counts and elapsed times use monospaced digits.
- Monospace is for paths, commands, raw codes, IDs and code blocks only. Skill
  names use the normal font, as on Desktop. Tool function names
  (`browser_navigate`) stay monospaced because they are literal identifiers.
- Markdown tables keep the horizontally scrolling native grid at standard text
  sizes. At accessibility sizes, each row becomes vertically stacked header/value
  pairs with unrestricted wrapping. This avoids SwiftUI Grid's large-text layout
  loop inside the lazy transcript and retains Dynamic Type and all cell values.

## 6. Reusable components (`Hermes/DesignSystem`)

- `TalariaMark`: the brand tile.
- `ProfileAvatar` / `ProfileAvatarWithStatus` with `IdentityColor`: bot identity. The hue is Desktop's `profileColor` hash, ported exactly.
- `Tag`, `StatusDot`, `SectionHeader`, `.panel()`, `.accentSwitches()`.
- `FailureCallout` and `StatusCopy`: plain-language failures.
- `FlowLayout` / `TagCloud`: skills, toolsets and MCP chips, with "Show all".
- `KeyValueRow` and `CommandBlock`.
- `TranscriptItem`: groups persisted tool history rows in a conversation.

## 7. Major UX decisions

- **Home** answers five questions from top to bottom: connected?, anything
  running?, does anything need me?, what happened?, what's next? A single
  status line replaces repeated host labels. Rows allow two-line titles.
- **Conversation** hides the tab bar, the way chat apps do. This gives the
  composer the bottom edge and removes the floating tab bar from the
  transcript. Consecutive tool-only history rows collapse into one tool group.
  Request and result rows merge by call ID.
- **Composer:** the text field is primary. Attach sits outside on the left. The
  mic is a secondary control inside the field. Send appears beside the field
  once there is something to send, and Stop takes that slot while a run is
  active. Dictation shows a listening row with Cancel and outlines the field;
  partial words stream into the editable text.
- **Bots:** the roster has no "Groups — Later" placeholder. Rows show the bot's
  face, last activity and model. Detail is ordered identity → Chat → status →
  configuration → skills/tools → management. Long skill lists are a tag
  cloud with "Show all".
- **Create/Edit Bot** has three sections: Basics, Brain and Capabilities.
  Skills, toolsets and MCP are searchable sub-pages with counts, so creating a
  bot is never a wall of 100+ toggles.
- **Failures** lead with a human title and sentence. The raw code is one tap
  away under Details and can be copied.
- **More** separates what the host offers from what it doesn't. Unavailable
  areas are summarized in one line instead of shown as dead rows.
