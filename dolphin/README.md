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
| Own version (2.0.0 on), FileVersion `X.Y.Z.<run>`, reported to the portal | `dolphin/version.txt`, `dolphin/build_plan.py`, `dolphin/version_resource.rs`, `build.rs`, `libs/portable/build.rs`, `src/hbbs_http/sync.rs` (`dolphin_version`), `flutter/lib/dolphin/about.dart`, `src/ui.rs` (`get_version`) | The portal and the customer can tell builds apart (TB-4) |
| Update before the app opens: ask the portal, download from it, check size and SHA-256, swap, restart | `src/dolphin_update_core.rs` (rules, texts), `src/dolphin_update.rs`, hooks in `src/flutter_ffi.rs` (`main_get_common`, `main_set_common`) | Owner decisions D10–D12 (TB-20). Upstream's own updater stays off |
| The packer passes its path to the app (`DOLPHIN_PACKER`) and waits for the old app (`DOLPHIN_WAIT_PID`) | `libs/portable/src/dolphin_wait.rs`, `libs/portable/src/main.rs` | A portable app can replace the file the customer started |

Everything else is upstream RustDesk. Copyright notices of the RustDesk authors are kept.

## Build

GitHub Actions → **Dolphin build** → Run workflow, choose the profile (`dev` or `production`) and, for dev runs,
which apps (`builds`: `customer-x64` by default, `technician-x64`, `customer-x86`, `x64`, `all`). A production run
always builds all three. A `production` run with a release tag (`vX.Y.Z`, or `vX.Y.Z-rc.N` for a release
candidate, where `X.Y.Z` is `dolphin/version.txt`) publishes
`DolphinConnect-<version>-x64.exe`, `DolphinConnect-<version>-x86.exe`, `DolphinConnect-Technician-<version>-x64.exe`,
`SHA256SUMS` and `baked-settings.json` as a GitHub release (`<version>` is the tag without the `v`). vcpkg packages
are kept between runs (`files` binary cache in `C:\vcpkg-binary-cache`, saved by `actions/cache`); dev runs build without LTO,
production full LTO.

**Versions (TB-4).** Our apps have their own SemVer number, `dolphin/version.txt` (first: `2.0.0`, owner decision
D3). Releases are `X.Y.Z`, release candidates `X.Y.Z-rc.N`, test builds `X.Y.Z-dev.<run>` (never offered to
customers, never update themselves). Windows FileVersion is `X.Y.Z.<run>`. RustDesk's own `1.5.0` stays
`crate::VERSION` because the protocol compares it with peers. After a release, raise `version.txt` to the next
planned number, so test builds sort after the release.

The Dolphin Connect portal serves each customer binary under two names: one ending in `install.exe`, which
opens RustDesk's installer (`src/common.rs` `is_setup`), and a portable name. The x86 build's outer
(packer) exe has default file properties; the inner `DolphinConnect.exe` is branded. Its `sciter.dll` is
pinned by commit and SHA-256 in the workflow.

Local generation: `python dolphin/gen_profile.py <profile> <customer|technician> <version>`.

Tests (no Rust toolchain needed): `python -m unittest discover -s dolphin -p "test_*.py"` (needs Pillow).

### Build times

Dev profile, measured 2026-10-28. Before the CI speed-up (run 40498394513, 2026-10-27) `build-windows (customer)` took
33 m 00 s, of which about 15 min was vcpkg rebuilding everything; with the vcpkg cache a warm run (40580914538)
took 21 m 57 s, and a warm `builds=all` run (40613624426) 26 min.

What changed (TB-1 follow-up): the Windows builds wait for the bridge only, not for the Dart analysis (which runs
beside them; a release still needs it); the generated bridge is cached on a hash of its inputs; dev builds pack with
brotli quality 5 (production keeps 11) and build without LTO (production keeps full LTO and one codegen unit). Caching
the Flutter SDK was tried and dropped: restoring it took 98 s, installing takes 73 to 77 s.

| Run | Apps | Cache | Whole run | Windows x64 job | Build step |
|---|---|---|---|---|---|
| 40623778613 | customer-x64 | cold (new Rust profile, bridge not cached) | 29 m 00 s | 25 m 51 s | 16 m 53 s |
| 40626568964 | customer-x64 | warm (bridge hit, 11 s) | 12 m 29 s | 12 m 09 s | 6 m 19 s |
| 40627982963 | all | warm (x64 jobs; x86 first run on this profile) | 13 m 44 s | 13 m 16 s (customer), 12 m 42 s (technician); x86 6 m 43 s | 7 m 14 s, 7 m 36 s; x86 3 m 17 s |

In a warm run the bridge job takes about 11 s, "Portable exe and checksums" under 30 s (it was 122 to 227 s), and
the Windows jobs start 30 s after the run does (they used to start after about 400 s). Run 40626568964 still had the
Flutter SDK cache (Install flutter 98 s); run 40627982963 is the final configuration. A cold run is slower than before
because it also saves the caches; it only happens when `vcpkg.json`, `res/vcpkg/**`, the vcpkg commit or the Rust profile
changes.

## Code-mode safety (review P13 T7–T9)

The apps answer, and send, only while the in-app WebView shows the portal itself (`isPortalPage`: the portal address
or a path, query or fragment under it; never `''`, `about:blank` or another origin). The customer app hands out its
one-time code only to that page, and it shows no code and answers no code request while a technician is connected,
because the client rotates the code at a successful login and the technician sees the customer's screen.

PC checks, unverified: (1) that webview_windows delivers `urlChanged` before that page's `webMessageReceived`, so
the current address is known when a message arrives; (2) an external link inside the in-app portal returns to home and
the code is not answered while off-portal; (3) the code disappears from the window while a technician is connected and
the next code shows after the session ends.

## Upstream

Based on commit `fada664df7a294d1d1a9ca3e7cd3637069122f17` (tag `1.5.0`). To move to a newer release,
branch from the new tag, cherry-pick the `dolphin` commits, and rebuild.
