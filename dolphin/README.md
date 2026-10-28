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
| Update before the app opens: ask the portal, download from it, check size and SHA-256, swap, restart | `src/dolphin_update_core.rs` (rules, texts), `src/dolphin_update.rs`, hooks in `src/flutter_ffi.rs` (`main_get_common`, `main_set_common`) | Owner decisions D10–D12 and D19 (TB-20). Upstream's own updater stays off |
| Update screens: x64 `flutter/lib/dolphin/update.dart`, `update_view.dart`; x86 `src/ui/dolphin_update.html`, handlers in `src/ui.rs`, inlined by `res/inline-sciter.py`. «ادامه با همین نسخه» (D19, this run only) sets `DOLPHIN_UPDATE_CONTINUE` for the x86 relaunch. The install waits while a session is open; a download with no bytes for 30 s fails | `src/dolphin_update.rs`, `src/dolphin_update_core.rs`, `src/lib.rs`, `src/flutter_ffi.rs`, `src/ui.rs` | A failed update never locks a customer out; an update never cuts a live session |
| The connection count (`video_conn_count`, `Data::VideoConnCount`) is also built in the Sciter build | `src/ui_interface.rs` (`UiStatus`), `src/ipc.rs` | The x86 window hides the one-time code during a session, and the update waits for it to end |
| One-time code rotated again when the last authorised connection closes | `src/server/connection.rs` (`AuthedConnID::drop`, marked block) | A code seen during a session is dead afterwards (code mode) |
| Closed-session tab kept with who ended it, 60 s ended screen | `src/ui_cm_interface.rs` (hook behind `feature = "flutter"`), `flutter/lib/dolphin/connection.dart`, `connection_view.dart` | The customer sees who ended the session (D15, D16) |
| Technician sees the customer's permission toggles as a strip | `flutter/lib/desktop/pages/remote_page.dart` (marked hook), `flutter/lib/dolphin/permissions.dart` | Plan 13 T10–T11 |
| x86 one-time code hidden while a technician is connected | `src/ui/index.tis` (`PasswordEyeArea`, `updatePasswordArea`, marked `// Dolphin Connect:`) | Same rule as `dolphinCode(inSession:)` on x64 |
| Persian overlay for the technician app's texts | `dolphin/rebrand.py` (`FA_OVERLAY`) → `src/lang/fa.rs` | Own wording, no reversed text |
| Checks and Dart analysis on every push | `.github/workflows/dolphin-check.yml`, `dolphin-analyze.yml`, `bridge.yml` (upstream's, now cached) | CI is the only test runner |
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
(packer) exe is branded by `libs/portable/build.rs` and the inner `DolphinConnect.exe` by the Sciter resource file;
CI checks FileVersion and ProductVersion of both. Its `sciter.dll` is pinned by commit and SHA-256 in the workflow.

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
one-time code only to that page.

The code is hidden (no display, no «کپی رمز», no answer to a code request) while the server reports a connection,
and for a short time after the window opens: `home.dart` has no immediate read (the first read would be the unsynced 0
and flash the code for 1–2 s when the window opens during a session), so the code stays hidden until the first 2 s tick
(about 2 s on x64), then every 2 s (`connectedCount`, `codeHiddenFor`). The x86 window (`index.tis`) starts hidden and
reads the count from its 4th 1 s callback (about 4 s). This is a timing margin, not proof that the count is known: the
server's first count lands about 1 s after the window opens, and if the server never answers over IPC the default 0 is
trusted and the code shows after that time. `model.clients` is not used: on desktop it is empty in the main window,
because connections live in the `--cm` process. The client rotates the code at a successful login (upstream) and again
when the last authorised connection closes (the `// Dolphin Connect:` block in `src/server/connection.rs`,
`AuthedConnID::drop`; not for failed logins; in every approve mode, since rotating in click mode is harmless). So a
code seen during the polling lag (about 4 s) is dead afterwards. The portal profile URL is written
in WebView2's normalised form (lower-case host, no default port) by `gen_profile.portal_url`.

PC checks, unverified: (1) that webview_windows delivers `urlChanged` before that page's `webMessageReceived`, so
the current address is known when a message arrives; (2) an external link inside the in-app portal returns to home and
the code is not answered while off-portal; (3) the code disappears from the window within about 4 s of a technician
connecting (the poll is 2 s, plus the status refresh and the password poll: about 4 s), and the next code shows after
the session ends; (4) a code seen during a session no longer works
afterwards. Accepted residual: the code rotated at login can be visible for about 4 s while the technician is
connected, and a second connection with that code would still need the portal to authorise it (every connection is
authorised by the portal); the rotation when the session closes kills it either way. Known small gap: a reply that passes the origin check is executed natively after a platform-channel hop,
and `PostWebMessageAsJson` has no target origin; a foreign page cannot reach this window, so it is theoretical.

## Upstream

Based on commit `fada664df7a294d1d1a9ca3e7cd3637069122f17` (tag `1.5.0`). To move to a newer release,
branch from the new tag, cherry-pick the `dolphin` commits, and rebuild.

## Last fixes before 2.0.0

- CI: `rust-unit` compiles and runs on separate lines, so a compile error fails the job (`test_workflows.py` forbids `rustc … &&`).
- Update, installed app: if the elevated installer never ends the process within 120 s, the screen shows the failure («تلاش دوباره», «ادامه با همین نسخه») instead of closing silently.
- Update, waiting for a session to end: «ادامه با همین نسخه» is offered too (Flutter and Sciter). It opens the current version, ends the wait without swapping, and never cuts the session.
- Installer: after 60 s with the install not done, only a hint shows (no second «نصب»: a refused or closed Windows prompt already ends the process, so an open window means the first install is pending); «فقط این بار اجرا شود» runs once; the body text names shortcuts only when the options are on.
- D5 (WF-11): only a technician the portal vouched for (`TechCheck.verified`) can be accepted, in every approve mode (`acceptAllowed`, `verify.dart`). Otherwise the prompt has no «پذیرفتن»; it shows «پورتال دلفین در دسترس نیست؛ با دلفین تماس بگیرید.» and the support phone. «رد» always works, and Accept is checked again at the moment it is pressed. The heartbeat loop (`src/hbbs_http/sync.rs`, rule in `src/dolphin_portal.rs`) sets the local option `dolphin-portal-down` to `Y` on a failed heartbeat and clears it on the next success, writing only on a change; the `--cm` process reads it like `dolphin-tech-id`. While it is `Y`, a stale `-`, another ID or an expired ID is `unverifiable`, not «این اتصال از کارشناس دلفین نیست»; an ID that matches and has not expired still verifies. Code mode stays usable: a valid one-time code is authorised in Rust (`src/server/connection.rs`) before any prompt, so a code login never reaches the prompt and works with the portal down. The prompt serves only a peer with no code or a wrong one. x86 (Sciter) is unchanged: its accept prompt (`src/ui/cm.tis`) has no portal check today (the D4 stopgap).
- x86 «ادامه با همین نسخه» (Sciter) ends the process after starting a new one, so it is hidden when this process hosts the server (portable run) and a session is live (`may_exit_for_continue`, `can_continue` in the progress JSON); the waiting screen then has no button and the install goes on after the session. Installed x86 keeps the button: its sessions live in the service.
