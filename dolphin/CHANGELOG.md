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
