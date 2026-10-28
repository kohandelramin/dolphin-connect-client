# Dolphin Connect apps — changelog

Versions follow SemVer (`dolphin/version.txt`; owner decision D3). Customer x64, customer x86 and technician x64 are
released together. Each entry has a short Persian note for customers.

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

**یادداشت فارسی:** از این نسخه برنامه پیش از باز شدن، نسخه‌ی تازه را خودش از پورتال دلفین دریافت و نصب می‌کند.
اگر پورتال در دسترس نباشد، برنامه مثل همیشه باز می‌شود. نسخه‌های پیشین را یک بار دستی به ۲.۰.۰ برسانید.
در حالت رمز یک‌بارمصرف، رمز فقط در همان حالت دیده می‌شود و تا وقتی کارشناس وصل است پنهان می‌ماند؛ ظاهر برنامه
هم روی ویندوز تیره روشن و خوانا است. اگر پورتال در دسترس نباشد، «پذیرفتن» فعال نمی‌شود و شماره‌ی تماس نشان داده می‌شود.
