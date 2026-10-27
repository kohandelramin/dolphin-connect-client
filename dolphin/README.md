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
| Customer screens (main window, accept prompt, session view), Dolphin theme, embedded Vazirmatn, About with the licence line | `flutter/lib/dolphin/`, `flutter/assets/fonts/`; hooks marked `// Dolphin Connect` in `flutter/lib/main.dart`, `desktop/pages/desktop_home_page.dart`, `desktop/pages/server_page.dart`, `desktop/pages/desktop_setting_page.dart`, plus the `Vazirmatn` family in `pubspec.yaml` | Own brand (portal design 2026-10-26-own-brand-client) |
| Build workflow; upstream workflows removed | `.github/workflows/dolphin-build.yml` | Three Windows builds: customer x64 (Flutter), customer x86 (Sciter), technician x64 |

Everything else is upstream RustDesk. Copyright notices of the RustDesk authors are kept.

## Build

GitHub Actions → **Dolphin build** → Run workflow, choose the profile (`dev` or `production`) and, for dev runs,
which apps (`builds`: `customer-x64` by default, `technician-x64`, `customer-x86`, `x64`, `all`). A production run
always builds all three. A `production` run with a release tag (`1.5.0-dc.N`) publishes
`DolphinConnect-<tag>-x64.exe`, `DolphinConnect-<tag>-x86.exe`, `DolphinConnect-Technician-<tag>-x64.exe`,
`SHA256SUMS` and `baked-settings.json` as a GitHub release. vcpkg packages are kept between runs (`files` binary
cache in `C:\vcpkg-binary-cache`, saved by `actions/cache`); dev runs use thin LTO, production full LTO.

The Dolphin Connect portal serves each customer binary under two names: one ending in `install.exe`, which
opens RustDesk's installer (`src/common.rs` `is_setup`), and a portable name. The x86 build's outer
(packer) exe has default file properties; the inner `DolphinConnect.exe` is branded. Its `sciter.dll` is
pinned by commit and SHA-256 in the workflow.

Local generation: `python dolphin/gen_profile.py <profile> <customer|technician>`.

Tests (no Rust toolchain needed): `python -m unittest discover -s dolphin -p "test_*.py"` (needs Pillow).

## Upstream

Based on commit `fada664df7a294d1d1a9ca3e7cd3637069122f17` (tag `1.5.0`). To move to a newer release,
branch from the new tag, cherry-pick the `dolphin` commits, and rebuild.

### Build times

Dev profile, `builds=customer-x64`, same commit (`7dbd4ea`), measured 2026-10-27. Before this change a full run
(run 40498394513) took 32 m 60 s for `build-windows (customer)`, of which about 15 min was vcpkg rebuilding everything.

| Run | Cache | Whole run | build-windows (customer) | vcpkg step |
|---|---|---|---|---|
| 40571892473 | cold (vcpkg: "Restored 0 package(s)"; zips stored afterwards) | 59 m 51 s | 51 m 23 s (Build step 24 m) | 17 m 37 s |
| 40580914538 | warm (vcpkg: "Restored 16 package(s) ... in 1.7 s") | 21 m 57 s | 17 m 51 s (Build step 9 m 22 s) | 25 s |

The warm run also gains from the Rust cache and thin LTO. A cold run is slower than before because it now also
saves the caches; it only happens when `vcpkg.json`, `res/vcpkg/**` or the vcpkg commit changes.
