# Private development history privacy audit

Audited 2026-10-05 before release cleanup. Baseline HEAD:
`08518c98be502f0ec3149f341cbb14c51b9832fb`.

The existing development repository is **not safe to publish as-is**. Keep it
private. This report omits matched private values; detailed object evidence is
retained only in ignored, owner-only local audit output.

## Scope and findings

`git cat-file --batch-all-objects` enumerated all 843 available objects:
27 commits, 536 blobs and 280 trees. Every object was read, including unreachable
objects. All 27 commits are reachable from normal branch refs. No tags or remote
refs were present. Normal branches were `main`, `bridge-integration` and
`codex/bot-mode-milestone` and `codex/public-release-preparation`; auxiliary Codex refs also exist. `git fsck --full
--no-reflogs --unreachable` identified 50 objects outside live refs.

- All 27 commits contain the local author's name/email in Git metadata. Some
  commit messages also contain attribution emails. These must not enter public history.
- Earlier committed source, mock hosts, bridge examples and validation docs
  contain personal absolute paths and private Tailscale hostnames. They remain
  reachable through branch history even though the release tree removed them.
- Three **unreachable blobs**, rather than any of the 27 commit trees, contain
  the known personal signing Team identifier. This corrects the earlier broad
  statement that it was necessarily present in historical commits. Copying the
  development `.git` directory would copy those private blobs too.
- No populated provisioning profile, signing certificate/private key, Apple
  device UDID, personal LAN/Tailscale IP, or provider-key pattern was detected
  in the available Git objects. Known local credential-value comparisons and
  final public scans are covered by the handoff. Pattern scanning cannot prove
  the absence of an unknown credential with an arbitrary format.
- Tree object names were examined; no private names were detected. The private
  material resides in commit metadata and blobs. No tag objects were present.
- Baseline HEAD's product/project files are sanitized. It still exposes private
  backup locations, local test-evidence paths and two live run record IDs in
  documentation. Release cleanup removes those references; test results remain.
  Its remaining broad scanner hits are intentional synthetic fixtures or empty
  signing overrides, not private credentials.

## Commit inventory

This table identifies every original commit with private Git metadata and whether
its tree also contains path/host candidates. Commit hashes are provenance only;
they will not be ancestors in the public repository.

| Commit | Finding categories | Reachable from normal branches |
| --- | --- | --- |
| `08518c98be502f0ec3149f341cbb14c51b9832fb` | Author/committer identity | Yes |
| `112c432762a75c827dc56785bad8d823b171661c` | Author/committer identity; personal path, private tailnet | Yes |
| `15bf746d36d4109e38fc66fc9941f367c8e3430b` | Author/committer identity; personal path, private tailnet | Yes |
| `28a5f59d2fcbd5d3b186386e2cbd4ddfa9e2ced3` | Author/committer identity; personal path, private tailnet | Yes |
| `387384e1170a9a8ccfed67ebe62bd1eebf228921` | Author/committer identity; personal path, private tailnet | Yes |
| `4be81501112c79afea525b1fcae8d0c9beee2bd1` | Author/committer identity; personal path, private tailnet | Yes |
| `545b7569b18fa9d8e7b72553785af7e0920bfe12` | Author/committer identity; personal path, private tailnet | Yes |
| `60a6524ee99e685085be7db9b7a1240b5aba5905` | Author/committer identity | Yes |
| `69261f1ce8f2d3c139bb82675d652a2a6c950175` | Author/committer identity; personal path, private tailnet | Yes |
| `8923efbd11607ea4137a22da6ef5c66e93804411` | Author/committer identity; personal path, private tailnet | Yes |
| `987ed8a79a0182456df9762bd9bd4257bfc5cdd7` | Author/committer identity | Yes |
| `9e9fc0337969137ddef386ec5b448dec0974770e` | Author/committer identity; personal path, private tailnet | Yes |
| `a6b854e3c029c2082be2068b075789ceeed3a502` | Author/committer identity; personal path, private tailnet | Yes |
| `aaee49dc9ba9b1ff06b48d8f0d6193333b7c03da` | Author/committer identity; personal path, private tailnet | Yes |
| `ad9fb66e6c9838bd6baf52762b52b600d017efcf` | Author/committer identity; personal path, private tailnet | Yes |
| `af8d8a81d366954b7aa6c3ea54255d5a1b04344b` | Author/committer identity | Yes |
| `b0adc878653f46f81252e28f3a407a0046d23bba` | Author/committer identity; personal path, private tailnet | Yes |
| `b106fbfa7c3ff4bab2991200edaf127d00433844` | Author/committer identity; personal path, private tailnet | Yes |
| `b53b35811901ec5ca07b276b769446f3eb3a2f17` | Author/committer identity; personal path, private tailnet | Yes |
| `bc9282935d088b592f3a17f3d326e85bf36fecd1` | Author/committer identity; personal path, private tailnet | Yes |
| `c184b46fc3cca402e95349e30d548e9125904c90` | Author/committer identity; personal path, private tailnet | Yes |
| `c61f26cfc1cf0ae43e66cd709218d08d6c2cb377` | Author/committer identity; personal path, private tailnet | Yes |
| `c70d9ecf3038da1b1963f6a4d0c4f56626444809` | Author/committer identity; personal path, private tailnet | Yes |
| `d4026930d9f3d0fc9c5f305b772d38bfdae55f5e` | Author/committer identity; personal path, private tailnet | Yes |
| `d515d0258c587a69bfd36dac7f8eaddc46bddce5` | Author/committer identity; personal path, private tailnet | Yes |
| `de7517fe3321af5a1078196bec52054045cd99ef` | Author/committer identity | Yes |
| `df387cf04d23340ce708af9b9f290fc1138b45d5` | Author/committer identity; private tailnet | Yes |

The affected historical file families include `Hermes/Domain/Host.swift`, mock
catalogs, `hermes-mobile-bridge/config.example.json`, installed-Hermes tests,
`README.md`, install/Studio guides, physical validation reports, capability and
architecture audits, integration mappings, the local integration harness and the
Research Terminal patch. Detailed commit-to-blob/path mappings are retained locally.

## Disposition

Create an independent Git repository by exporting the final tracked release tree,
then `git init` and a neutral-author root commit. Do not clone, share an object store,
copy `.git`, copy reflogs, merge old branches, or rewrite this private repository.
The original refs and object database remain intact. See
[public release handoff](PUBLIC_RELEASE_HANDOFF.md) for parity and final scans.
