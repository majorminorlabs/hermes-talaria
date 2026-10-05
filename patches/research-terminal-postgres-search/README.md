# Research Terminal PostgreSQL search handoff

`validation.md` retains the source-grounded root cause, regression coverage and
Studio validation. `baseline-manifest.json` retains source hashes for provenance.
Final physical search evidence is in [BOT_MODE_VALIDATION.md](../../BOT_MODE_VALIDATION.md).

The baseline-relative `research-terminal-track-a.patch` retains all original
changes with zero context, removing unrelated machine-specific paths from the
baseline. Its per-file additions/deletions were checked against the original patch.
The original was backed up privately outside the checkout. This repository does
not vendor or modify the separate Research Terminal application during release cleanup.

Apply only to the matching baseline identified by the manifest. Check first:

```sh
git apply --check --unidiff-zero /path/to/research-terminal-track-a.patch
git apply --unidiff-zero /path/to/research-terminal-track-a.patch
```

Zero-context patches require extra care: inspect the resulting diff, compare the
manifest's current hashes, and run the focused regression coverage in `validation.md`.
Do not apply over an already fixed or otherwise divergent checkout.
