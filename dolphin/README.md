# Dolphin Connect client

This is the Windows client of **Dolphin Connect** («دلفین کانکت»), Dolphin's remote-support service
(`https://support.dolphindev.ir`). It is RustDesk 1.5.0 (`rustdesk/rustdesk`, tag `1.5.0`), licensed
AGPL-3.0, with the changes below. The full source of every build we ship is this branch (`dolphin`).

## What we changed

| Change | Where | Why |
|---|---|---|
| Settings compiled in from `dolphin/settings.json` and one profile | `dolphin/gen_profile.py`, `src/dolphin.rs`, `src/common.rs` (`load_custom_client`) | The client reaches only Dolphin's server and keeps Dolphin's security settings |
| The exe's file name can no longer set server, key or API | `src/platform/windows.rs` (`get_license_from_exe_name`) | A renamed copy must not be re-pointed to another server |
| Name, icons and file metadata | `dolphin/brand.py`, applied in CI | Branding |
| Build workflow; upstream workflows removed | `.github/workflows/dolphin-build.yml` | We build Windows x64 only |

Everything else is upstream RustDesk. Copyright notices of the RustDesk authors are kept.

## Build

GitHub Actions → **Dolphin build** → Run workflow, choose the profile (`dev` or `production`). A
`production` run with a release tag (`1.5.0-dc.N`) publishes `DolphinConnect-<tag>-x86_64.exe`,
`SHA256SUMS` and `baked-settings.json` as a GitHub release.

Tests (no Rust toolchain needed): `python -m unittest discover -s dolphin -p "test_*.py"` (needs Pillow).

## Upstream

Based on commit `fada664df7a294d1d1a9ca3e7cd3637069122f17` (tag `1.5.0`). To move to a newer release,
branch from the new tag, cherry-pick the `dolphin` commits, and rebuild.
