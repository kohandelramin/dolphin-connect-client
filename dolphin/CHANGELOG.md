# Dolphin Connect apps — changelog

Versions follow SemVer (`dolphin/version.txt`; owner decision D3). Customer x64, customer x86 and technician x64 are
released together. Each entry has a short Persian note for customers.

## Unreleased (next build; no app build until the owner says)

All three apps. Owner decisions D21 and D23 (2026-11-10). Not compiled on the maintainer's PC (no Rust or Flutter
there): the Python tests ran; the std-only Rust, the Dart analysis and the widget tests run in CI at the next push.

- D21, fixed password: every app carries one fixed password from the GitHub Actions secret `DOLPHIN_FIXED_PASSWORD`
  (never in git). The apps hold HMAC-SHA256(secret, context), XOR-masked with two random pads per build
  (`src/dolphin_fixed_generated.rs`, git-ignored): obfuscation, not encryption. A production build fails without the
  secret; a dev build without it leaves the feature out and logs so.
- The technician app sends it when the panel gave no password (before any remembered password); it is never saved to
  the peer's config.
- A customer PC (x64 and x86) accepts it, with no «پذیرفتن», only when the portal pushed `dolphin-fixed-password = Y`
  for its organization, the PC is not in code mode (`approve-mode = password` never takes it), the heartbeat reaches
  the portal, and the connecting peer is the technician the portal authorized for this PC (`dolphin-tech-id`, not
  expired). A login that comes before the portal's word waits up to 9 s for the next heartbeat. Otherwise it is
  handled as if no password came: the accept prompt for the customer, the password box (one-time password) for the
  technician, and it is not counted as a wrong password. Audited as a permanent-password login. The session window,
  banner and «پایان» are the same as before.
- The customer can no longer set a permanent password (`disable-change-permanent-password = Y`, now in the build's
  floor with `allow-deep-link-password = N`).
- D23: a session that began with the one-time password can be taken back without a new Accept for 2 minutes after a
  drop (was 30 s). The technician app retries a dropped link by itself every 1–5 s for 2 minutes, showing «در حال
  اتصال دوباره…» instead of the error box, and says «دوباره وصل شد» when it is back; the customer window's badge says
  «دوباره وصل شد» for the same technician's session within 2 minutes of the last one.
- Portal change needed (not in this repo): push `dolphin-fixed-password` = "Y" for click-mode organizations with the
  feature on, "N" for code mode and to turn it off.

**یادداشت فارسی:** مشتری فقط برنامه را باز می‌کند و شناسه را می‌گوید؛ کارشناس دلفین بدون «پذیرفتن» وصل می‌شود،
فقط وقتی پورتال دلفین همان کارشناس را برای همین رایانه فرستاده باشد. دکمه‌ی «پایان» مثل همیشه کار می‌کند. اگر اتصال
(مثلاً با روشن و خاموش شدن VPN) قطع شود، برنامه‌ی کارشناس تا دو دقیقه خودش دوباره وصل می‌شود.

### Plan 18 Phase 2: the customer home (customer x64)

Flutter only (`flutter/lib/dolphin/`); no change to connections or networking. Widget and unit tests in
`flutter/test/dolphin/home_test.dart`, not run on the maintainer's PC (no Flutter there yet).

- DD-43: one large coloured bar at the top: «آماده برای پشتیبانی», «کارشناس در راه است» or «کارشناس وصل است», with the
  technician's photo and name when the portal pushed them. It replaces the small status pill and the «در راه است» card.
- DD-44: the ID in Persian digits, in groups of three, with a full-width «کپی شناسه»; the clipboard gets Latin digits
  without spaces. The ID is no longer selectable, so a hand copy cannot carry Persian digits.
- DD-33: the bar's dot is aqua while the server knows this PC and grey otherwise, as the portal's «در دسترس»; without the
  server the bar turns red, says «بدون اینترنت» and what to do. During a session it stays «کارشناس وصل است» with one
  quiet line instead.
- DD-8: «وضعیت شبکه» under the ID: registered with the server or not, the server address in use, this PC's IP (from
  upstream's NAT test, when it has run) and «شناسه: تازه عوض شد». No VPN line yet (Phase 6 adds it there).
- DD-32: the version at the bottom; «از اینجا شروع کنید» opens the help page in the browser; «کپی IP من», «کپی لینک
  دانلود» and «کپی راهنما»; «شناسه‌ی شما عوض شد» when the ID differs from the last one this app saw (kept locally;
  nothing on the first run). The window is 340 × 520 (was 320 × 400); the rest scrolls.
- DD-17: a first-run screen, once per Windows account: «شناسه‌ی شما این است، کپی کنید», two lines of what happens next,
  «بعدی». Remembered as a local option. A PC that already had the app sees it once after this update too.
- DD-18 (app part): nothing to build. The window shows RustDesk's one-time code, which has no time limit (it changes
  after each connection); the expiry belongs to the code entered in the portal, and the portal's pages (also inside the
  app's «درخواست‌ها و پیام‌ها») already show it.

**یادداشت فارسی:** پنجره‌ی اصلی بالای صفحه با یک نوار رنگی می‌گوید آماده است، کارشناس در راه است یا وصل است.
شناسه با رقم فارسی و سه‌رقم‌سه‌رقم نوشته می‌شود و دکمه‌ی کپی آن رقم انگلیسی کپی می‌کند. زیر شناسه وضعیت شبکه، پایین
پنجره شماره‌ی نسخه، و دکمه‌های «از اینجا شروع کنید» و کپی لینک‌ها آمده است. اولین بار پس از نصب، یک صفحه‌ی کوتاه شناسه را
نشان می‌دهد.

### Plan 18 Phase 2: the customer's window during a session (DD-36, DD-37, DD-45, DD-46)

Customer x64 (Flutter) and the technician app. The x86 (Sciter) window is unchanged. Not compiled here: the std-only
Rust (`src/dolphin_session_core.rs`) ran with rustc 1.75; the crate, the Dart analysis and the widget tests run in CI.

- DD-36: during a session the window keeps upstream's width and top-right corner and gets shorter (300 × 380, was
  300 × 490); the prompt and the ended screen get the full size back. «پایان» is pinned at the bottom, never scrolled
  away. The customer build no longer minimizes the window 3 s after a password login (upstream's hide timer).
- DD-45: keyboard and mouse, clipboard and files each have their own switch for the whole session; the technician's
  strip shows the change at once. Switching something off, pausing and resuming pass even when the
  `enable-perm-change-in-accept-window` policy is off. Turning keyboard and mouse off also lifts the technician's
  block of the customer's input.
- DD-37: «ماوس و صفحه‌کلید شما خاموش است» with who and since when («… خاموش کرد، ۳ دقیقه پیش»), shown as soon as the
  input thread has blocked the input (`dolphin_input_blocked` over the existing CM permission message).
- DD-46: «مکث» / «ادامه» for a remote-control session. During a pause the connection drops every video frame (counted
  as fetched, so capture does not stall), sound, cursor position and clipboard before they leave the PC, and applies
  nothing the technician sends that acts on the PC (input, clipboard, files, screenshot, terminal, restart,
  elevation, resolution, virtual display, block input, privacy mode); a block of input or privacy mode set by this
  connection is lifted. The technician hears "off" for keyboard, clipboard and files and gets «مشتری مکث کرد» over the
  picture (a `MessageBox` with type `dolphin-pause`, which an older technician app shows as a plain message). Pings go
  on, so the session is not cut (ADR-0013). «ادامه» restores what the customer had allowed and asks for a key frame.
  A paused session that drops and comes back within 2 minutes starts paused. No new network message.
- Not audited in the portal yet: the portal's `audit/conn` accepts only `new` and `close`; the app logs the pause
  (`Dolphin: paused by the customer`). A portal change would record it.
- Spelling: «ماوس و صفحه‌کلید» (was «موس») in the prompt, the session window and the technician's strip.

**یادداشت فارسی:** پنجره‌ی جلسه کوچک‌تر شد و دکمه‌ی «پایان» همیشه دیده می‌شود. هر اجازه (ماوس و صفحه‌کلید، کپی و
چسباندن، انتقال فایل) را در جلسه می‌شود خاموش و روشن کرد. با «مکث» کارشناس تا «ادامه» تصویری نمی‌بیند و کنترلی ندارد؛
مثلاً هنگام نوشتن رمز بانک. اگر کارشناس ماوس و صفحه‌کلید شما را خاموش کند، پنجره همان لحظه می‌گوید.
### Plan 18 Phase 2: tray, sharing, receive folder, plain errors (customer x64, technician x64)

Portal ADR-0016 (owner 2026-11-13). Not compiled here (no vcpkg or LLVM for the crate, no Flutter): the Python tests
and the std-only `src/dolphin_system_core.rs` tests ran; the crate, the Dart analysis and the widget tests run in CI.

- DD-35, ADR-0016: closing the customer window asks «در دسترس بماند (کنار ساعت)» or «بستن کامل», with «انتخاب را به
  خاطر بسپار». Staying hides the window and keeps the process, so `allow-only-conn-window-open` (a process check,
  `check_process("")`) still counts it as open and the authorized technician connects under the same rules. «بستن
  کامل» is upstream's close, which ends the app: nobody can connect. The portal's `stay-in-tray` switch: «پنهان»
  always quits without asking, «اجباری» always stays. Nothing starts with Windows: an installed app's tray, started at
  sign-in by upstream's shortcut, stays hidden until the window is opened.
- DD-47: the customer app's own tray: a dot on the icon, green ready, blue connected, grey no internet or sharing
  stopped, the state as the tooltip; a click or «باز کردن» opens the window, «بستن کامل» ends it. Hidden while
  nobody could connect. A portable app gets a tray when it hides into it; that tray ends with the app.
- DD-34 «شروع / توقف اشتراک»: a strip on the home screen. Stopped, the PC refuses every connection before any login
  (fixed password, one-time code, Accept and taking back a dropped session included); the technician reads «مشتری
  اشتراک را متوقف کرده است…». Each start of the app shares again. The heartbeat sends `dolphin_share` (`on` or
  `stopped`). The portal's `share-toggle` switch «پنهان» removes the strip and the effect.
- DD-12: files from the technician land by default in `Downloads\دریافتی دلفین` (made when first needed): the
  technician's file manager opens there when it has no folder saved for the PC. The portal's `receive-folder` switch:
  «اجباری» always opens there and refuses new files and folders anywhere else, «پنهان» is upstream (the home folder).
- DD-13: plain Persian, with what to do, for connection and file-transfer errors: new wording for upstream keys
  (`dolphin/rebrand.py` FA_ERRORS), keys upstream lacks (FA_ADD, e.g. «دلفین کانکت روی رایانه‌ی مشتری بسته است»),
  and Windows file and socket errors by code (access denied, file in use, disk full, connection lost, timeout…). A
  failed file job now says why instead of only «خطا».
- Portal change needed (not in this repo): read `dolphin_share` from the heartbeat (`on` / `stopped`) and show
  «اشتراک متوقف» on «رایانه‌ها».

**یادداشت فارسی:** با بستن پنجره، برنامه می‌پرسد «در دسترس بماند (کنار ساعت)» یا «بستن کامل». در حالت اول نماد دلفین
کنار ساعت می‌ماند و رنگش وضعیت را نشان می‌دهد. با «توقف اشتراک» هیچ کس، حتی کارشناس دلفین، نمی‌تواند وصل شود تا
«شروع اشتراک» را بزنید. فایل‌هایی که کارشناس می‌فرستد در پوشه‌ی «دریافتی دلفین» در Downloads ذخیره می‌شوند.

### Plan 18 Phase 3: the technician's session toolbar, screens, dark theme, no-picture help (technician x64)

Flutter only; no change to connections, codecs or networking. Widget and unit tests in `flutter/test/dolphin/`
(`session_toolbar_test.dart`, `monitor_picker_test.dart`, `no_picture_test.dart`, `tech_theme_test.dart`,
`technician_header_test.dart`) ran with Flutter 3.24.5 on the maintainer's PC; not yet seen in a real session.

- DD-28: a Persian quick bar at the start of the session toolbar, each button with a tooltip: Ctrl+Alt+Del, lock,
  files, «عکس صفحه» and «زبان صفحه‌کلید» (wired by the side-panel work through `DolphinToolbarHooks`; disabled with
  «(به‌زودی)» until then), «صفحه‌ها», «فقط تماشا», «نشانگر خودم», «دنبال کردن پنجره‌ی مشتری» (only with several
  screens, as upstream), «تصویر نمی‌آید؟» and «جمع کردن نوار». The latency in milliseconds with «مستقیم» or «از سرور
  دلفین» is only displayed (upstream's quality-monitor delay and connection type); it changes nothing. Each action is
  the one upstream has in its menus, called the same way; upstream's menus stay after the bar. Safe Mode comes in
  Phase 5. The toolbar pin says «ثابت کردن / رها کردن نوار ابزار» (upstream had «سجاق»).
- DD-52: «صفحه‌ها» opens a picture of the customer's screens as they are arranged, with number, resolution and
  «اصلی»; the one being viewed is blue. The pictures are shapes, not live images: a live image of every screen would
  mean capturing and sending each one (the owner's speed rule).
- DD-53: «ظاهر» in the technician header: «مثل ویندوز» (default), «روشن» or «تیره». It is upstream's `theme` option,
  so the session windows follow it. Customer screens stay light (DR-1). The staff panel inside the window is the
  portal's own page and keeps the portal's look.
- DD-16: when no picture comes 8 s after «وصل شد؛ در انتظار تصویر…», the dialog says why (locked PC, Windows sign-in
  screen, screen off) and offers «فرستادن Ctrl+Alt+Del» (when the PC can take it), «صبر می‌کنم» and «قطع»; it adds
  that the app is not installed on the customer's PC when that PC says so. A picture that shows the sign-in screen or
  froze when Windows locked looks like a still screen, so for that the same help opens from «تصویر نمی‌آید؟».

**یادداشت فارسی:** فقط برنامه‌ی کارشناس عوض شده است.

## 2.0.0-rc.5 — ۱۸ آبان ۱۴۰۵ (2026-11-09)

All three apps (one release carries all three). Plan 14 B5/B6, TB-22 and the items below. Pinned by portal 2.3.0.

- The x86 (Sciter) build failed on `ui_interface::get_id`, which exists only in the Flutter build; the callback now
  reads the ID with `ipc::get_id` (what the Flutter helper calls on Windows), and a text check guards it.

- Owner 2026-11-09: a session is never cut because the technician is idle. `allow-auto-disconnect` is now "N" in
  the compiled settings and part of the build's floor (was "Y" with 30 minutes: «Connection failed due to inactivity»).

- Portal ADR-0014 (release workflow only, no app change): a production release also pushes the three exes to the
  public package `ghcr.io/<owner>/dolphin-connect-client-files:<version>` (oras 1.3.6, one raw layer each, digests
  checked against `SHA256SUMS`), so the portal fetches them by itself instead of an admin upload. After the first
  push the owner sets the package to public once.

- ADR-0012: «انتقال فایل» starts on in the accept prompt, so copying and pasting files works without an extra step;
  the customer can untick it there or in the session bar.
- In click mode (`approve-mode = both`) the customer window shows the one-time password with «این رمز را فقط به
  کارشناس دلفین بگویید…»; code mode keeps «… پشت تلفن نخوانید». Only code mode hands the code to the portal page.

**یادداشت فارسی:** کپی و چسباندن فایل بدون روشن کردن «انتقال فایل» کار می‌کند. مشتری می‌تواند به‌جای «پذیرفتن»،
رمز یک‌بارمصرف را به کارشناس دلفین بگوید. اتصال به‌خاطر بی‌کار ماندن کارشناس قطع نمی‌شود.

## 2.0.0

First numbered release of the apps (Plan 12). Based on RustDesk 1.5.0.

- Own version number everywhere: About, the exe's properties (FileVersion 2.0.0.<build>), the file name, and the
  portal's «رایانه‌ها».
- Before it opens, every app asks the portal for a newer version. If there is one it is downloaded from the portal,
  checked (size and SHA-256), swapped in and started. If the update fails, the customer can continue with the current
  version («ادامه با همین نسخه», D19) and the next start tries again; during a session the new version is installed
  after the session ends. If the portal does not answer within 4 seconds the app opens normally. The technician app sends the technician to the panel instead.
- Apps from 1.5.0-dc.1 to dc.4 have no update check: install 2.0.0 once by hand.
- Code mode end to end: the customer window shows the one-time code only in code mode.
- The code is hidden while a technician is connected, and rotated at login and when the last session ends.
- The code reaches the request form only on the customer's press, and only for the portal page.
- The technician app's own «اتصال» field goes through the panel.
- Plain Persian replaces broken upstream strings.
- The session window: every permission can be switched, and the timer no longer drifts.
- The ended screen says who ended the session («اتصال کارشناس بسته شد») and closes after 1 minute.
- A Dolphin installer: one «نصب» button, right to left.
- D5: when the portal can't be reached, «پذیرفتن» is blocked and the phone is shown; code mode still works.
- One light Dolphin look on dark Windows, one blue (`#1462e0`), the Dolphin icon on the x86 window, and readable colours (WCAG AA).
- The update waits for a live session to end, and stops a stalled download after 30 s.
- Plain words: «کپی و چسباندن», a plain tray menu, the support phone in Persian digits, Persian window titles; one button style; the request window fits a small laptop; the request button says it needs a Dolphin username.
- New in rc.3: the owner's app icon in every size (the mark alone and sharpened at 32 px and below), and Windows
  refreshes its icon cache after an install or update, so the taskbar no longer shows the old mark; the Programs list
  shows Dolphin's version.
- rc.3: the technician app tags its own ID for the panel, so a customer app's ID is never saved as a technician's (WF-7).
- rc.3: the customer window lists the last sessions on this PC, naming only registered technicians (UN-15).
- rc.3: the technician app shows a Windows notice with a sound for a new waiting request (UN-16).
- rc.3: the end screen says what to do after a restart: open Dolphin Connect again and call back (UN-13).
- rc.4: recording is a fixed setting in the app, not a default a PC could change; the accept prompt allows a PC
  clock up to 10 minutes fast, since the portal re-sends who may connect every 5 minutes and cuts expired sessions (TB-9).
- Next build (rc.5): the tray menu no longer offers «توقف سرویس», which deleted the Windows service and left the
  app on «در حال اتصال به سرور دلفین…» for ever, even after a reinstall. A PC where it was clicked now shows «سرویس
  دلفین خاموش است» with «روشن کردن سرویس», and any install brings the service back (TB-22).
- Next build (rc.5, Plan 14): while the portal has authorized a technician and nobody is connected yet, the customer
  window shows «کارشناس دلفین در راه است» with the technician's name and photo; the accept prompt shows the photo beside
  the verified name (B5). A PC linked to an organization gets «با من تماس بگیرید»: name, phone and an optional line go to
  the portal, which opens a request for a technician to call back, no account needed (B6). Customer x64 only.

**یادداشت فارسی:** از این نسخه برنامه پیش از باز شدن، نسخه‌ی تازه را خودش از پورتال دلفین دریافت و نصب می‌کند.
اگر پورتال در دسترس نباشد، برنامه مثل همیشه باز می‌شود. نسخه‌های پیشین را یک بار دستی به ۲.۰.۰ برسانید.
در حالت رمز یک‌بارمصرف، رمز فقط در همان حالت دیده می‌شود و تا وقتی کارشناس وصل است پنهان می‌ماند؛ ظاهر برنامه
هم روی ویندوز تیره روشن و خوانا است. اگر پورتال در دسترس نباشد، «پذیرفتن» فعال نمی‌شود و شماره‌ی تماس نشان داده می‌شود.
