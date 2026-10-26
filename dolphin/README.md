# Dolphin Connect client

This is the Windows client of **Dolphin Connect** («دلفین کانکت»), Dolphin's remote-support service
(`https://support.dolphindev.ir`). It is RustDesk 1.5.0 (`rustdesk/rustdesk`, tag `1.5.0`), licensed
AGPL-3.0, with the changes below. The full source of every build we ship is this branch (`dolphin`).

## What we changed

| Change | Where | Why |
|---|---|---|
| Settings compiled in from `dolphin/settings.json` and one profile | `dolphin/gen_profile.py`, `src/dolphin.rs`, `src/common.rs` (`load_custom_client`) | The client reaches only Dolphin's server and keeps Dolphin's security settings |
| The exe's file name can no longer set server, key or API | `src/platform/windows.rs` (`get_license_from_exe_name`) | A renamed copy must not be re-pointed to another server |
| Name, icons and file metadata | `dolphin/brand.py` (`brand_rc`, `brand_winres`), applied in CI | Branding of the Flutter (x64) and Sciter (x86) builds |
| Customer builds incoming-only, technician build outgoing-only, installation allowed | `dolphin/settings.json` (`variants`, `hard`) | Customers can only be connected to; technicians can only connect (ADR-0010 in the portal repo) |
| Build workflow; upstream workflows removed | `.github/workflows/dolphin-build.yml` | Three Windows builds: customer x64 (Flutter), customer x86 (Sciter), technician x64 |

Everything else is upstream RustDesk. Copyright notices of the RustDesk authors are kept.

## Build

GitHub Actions → **Dolphin build** → Run workflow, choose the profile (`dev` or `production`). Each run
builds three clients. A `production` run with a release tag (`1.5.0-dc.N`) publishes
`DolphinConnect-<tag>-x64.exe`, `DolphinConnect-<tag>-x86.exe`, `DolphinConnect-Technician-<tag>-x64.exe`,
`SHA256SUMS` and `baked-settings.json` as a GitHub release.

The Dolphin Connect portal serves each customer binary under two names: one ending in `install.exe`, which
opens RustDesk's installer (`src/common.rs` `is_setup`), and a portable name. The x86 build's outer
(packer) exe has default file properties; the inner `DolphinConnect.exe` is branded. Its `sciter.dll` is
pinned by commit and SHA-256 in the workflow.

Local generation: `python dolphin/gen_profile.py <profile> <customer|technician>`.

Tests (no Rust toolchain needed): `python -m unittest discover -s dolphin -p "test_*.py"` (needs Pillow).

## Upstream

Based on commit `fada664df7a294d1d1a9ca3e7cd3637069122f17` (tag `1.5.0`). To move to a newer release,
branch from the new tag, cherry-pick the `dolphin` commits, and rebuild.
