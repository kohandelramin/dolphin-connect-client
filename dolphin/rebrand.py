"""Rewrite user-visible "RustDesk" text and rustdesk.com links to Dolphin Connect, then fail on leftovers.

Run in CI after gen_profile.py and brand.py, before building (the rewritten tree is never committed).
Usage: python dolphin/rebrand.py
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
NAME_EN = "Dolphin Connect"
NAME_FA = "دلفین کانکت"
SITE = "https://support.dolphindev.ir"
URL = re.compile(r"https?://(?:www\.)?rustdesk\.com[^\s'\"<>)]*")
LITERAL = re.compile(r"""(?P<q>['"])(?:\\.|(?!(?P=q)).)*(?P=q)""")
PAIR = re.compile(r'\("((?:[^"\\]|\\.)*)",\s*"((?:[^"\\]|\\.)*)"\)')
# Literals that are identifiers, not text a person reads (file names, keys, protocol values). Each needs a reason.
# Empty on 1.5.0: the one functional comparison (`!= "RustDesk"` in flutter/lib/web/bridge.dart) is web-only and
# behaves the same after the rewrite.
ALLOW = {
}
# Rust strings a person can see, rewritten exactly (a literal regex would break Rust lifetimes like 'a).
RUST_TEXT = {
    "src/clipboard.rs": [
        ('"RustDesk placeholder to clear the file clipboard"', '"Dolphin Connect placeholder to clear the file clipboard"'),
    ],
    "src/auth_2fa.rs": [
        ('const ISSUER: &str = "RustDesk";', 'const ISSUER: &str = "Dolphin Connect";'),
    ],
}
SCITER_CSS = """
/* Dolphin Connect brand (dolphin/rebrand.py) */
html {
    var(accent): #1462e0;
    var(button): #1462e0;
    var(menu-hover): #dbe7fb;
    var(green-blue): #0d9488;
}
body { font-family: Vazirmatn, Tahoma, sans-serif; }
"""
# Upstream Persian written for a renderer that is not bidi-aware (UX-12), and upstream wording our users should not
# see (UX-6). Applied to src/lang/fa.rs by key, before the name rewrite; a key that is missing or not unique fails the
# build, so an upstream change cannot silently bring the old text back.
FA_OVERLAY = {
    "connecting_status": "در حال برقراری ارتباط با سرور…",
    "TCP tunneling": "تونل TCP",
    "ID/Relay Server": "سرور ID/Relay",
    "Relay Server": "سرور Relay",
    "API Server": "سرور API",
    "Connecting...": "در حال اتصال…",
    "Connected, waiting for image...": "وصل شد؛ در انتظار تصویر…",
    "Insert Ctrl + Alt + Del": "فرستادن Ctrl + Alt + Del",
    "Failed to connect to relay server": "اتصال به سرور Relay انجام نشد",
    "Failed to connect via relay server": "اتصال از راه سرور Relay انجام نشد",
    "install_tip": "برای کار راحت‌تر و جلوگیری از خطای UAC، دلفین کانکت را نصب کنید",
    "config_acc": "برای کنترل از راه دور، به دلفین کانکت مجوز «Accessibility» بدهید",
    "config_screen": "برای کنترل از راه دور، به دلفین کانکت مجوز «Screen Recording» بدهید",
    "Installing ...": "در حال نصب…",
    "Create start menu shortcuts": "میانبر در منوی Start",
    "Install {} Printer": "نصب چاپگر {}",
    "Generating ...": "در حال ساختن…",
    "Listening ...": "در انتظار…",
    "Logging in...": "در حال ورود…",
    "x11 expected": "به X11 نیاز است",
    "Always connect via relay": "همیشه از راه Relay وصل شود",
    "whitelist_tip": "فقط IPهای مجاز می‌توانند به این رایانه وصل شوند",
    "Socks5 Proxy": "پروکسی Socks5",
    "Socks5/Http(s) Proxy": "پروکسی Socks5/Http(s)",
    "Legacy mode": "حالت قدیمی (legacy)",
    "Map mode": "حالت نگاشت (map)",
    "Relay Connection": "اتصال از راه Relay",
    "Direct IP Access": "دسترسی مستقیم با IP",
    "Show RustDesk": "نمایش دلفین کانکت",
    "About RustDesk": "درباره‌ی دلفین کانکت",
    "powered_by_me": "ساخته‌شده با دلفین کانکت",
    "Please wait for the remote side to accept your session request...": "لطفاً صبر کنید تا مشتری درخواست شما را بپذیرد…",
    "RDP Settings": "تنظیمات RDP",
    "Capture screen using DirectX": "تصویربرداری از صفحه با DirectX",
    "{} Update": "به‌روزرسانی {}",
    "Use WebSocket": "استفاده از WebSocket",
    "Disable UDP": "خاموش کردن UDP",
    # What the technician reads when a connection ends (UX-6): the portal's watchdog, or the customer.
    "Closed manually by web console": "پورتال دلفین این اتصال را قطع کرد؛ از «رایانه‌ها» «اتصال» را بزنید",
    "Closed manually by the peer": "مشتری اتصال را بست",
}
LATIN_START = re.compile(r"^(?:[A-Za-z]|\.\.\.)")
PERSIAN_END = re.compile(r"[\u0600-\u06FF][^A-Za-z\u0600-\u06FF]*$")


def _rust_str(s):
    return s.replace("\\", "\\\\").replace('"', '\\"')


def apply_fa_overlay(text, overlay=None):
    """Replace the Persian value of each overlay key; report keys that are missing or not unique."""
    overlay = FA_OVERLAY if overlay is None else overlay
    problems = []
    for key, value in overlay.items():
        pattern = re.compile(r'\("' + re.escape(_rust_str(key)) + r'",\s*"(?:[^"\\]|\\.)*"\)')
        hits = pattern.findall(text)
        if len(hits) != 1:
            problems.append(f"src/lang/fa.rs: expected exactly one {key!r}, found {len(hits)}")
            continue
        replacement = f'("{_rust_str(key)}", "{_rust_str(value)}")'
        text = pattern.sub(lambda _m: replacement, text, count=1)
    return text, problems


def bidi_problems(text):
    """Values that start with a Latin word (or "...") and end in Persian: written for a renderer that reverses them."""
    problems = []
    for n, line in enumerate(text.split("\n"), 1):
        m = PAIR.search(line)
        if not m:
            continue
        value = m.group(2).strip()
        if LATIN_START.match(value) and PERSIAN_END.search(value):
            problems.append(f"src/lang/fa.rs:{n}: {value[:80]}")
    return problems



def _text(s, name):
    return URL.sub(SITE, s).replace("RustDesk", name)


def rewrite_lang(text, lang):
    value_name = NAME_FA if lang == "fa" else NAME_EN

    def pair(m):
        return f'("{_text(m.group(1), NAME_EN)}", "{_text(m.group(2), value_name)}")'

    return PAIR.sub(pair, text)


def _code_and_comment(line):
    """Split off a // comment that is not inside a string literal."""
    pos = 0
    while True:
        m = LITERAL.search(line, pos)
        c = line.find("//", pos)
        if c < 0:
            return line, ""
        if m is None or c < m.start():
            return line[:c], line[c:]
        pos = m.end()


def _rewrite_code(code):
    def lit(m):
        s = m.group(0)
        return s if s in ALLOW else _text(s, NAME_EN)

    return LITERAL.sub(lit, code)


def rewrite_literals(text):
    out = []
    for line in text.split("\n"):
        code, comment = _code_and_comment(line)
        out.append(_rewrite_code(code) + comment)
    return "\n".join(out)


def rewrite_markup(text):
    return _text(text, NAME_EN)


def _files(root):
    yield from (("code", p) for p in sorted((root / "flutter" / "lib").rglob("*.dart")))
    for pattern, kind in (("*.tis", "code"), ("*.html", "markup"), ("*.css", "markup")):
        yield from ((kind, p) for p in sorted((root / "src" / "ui").glob(pattern)))


def scan(root=ROOT):
    problems = []
    for kind, path in _files(root):
        for n, line in enumerate(path.read_text(encoding="utf-8", errors="replace").split("\n"), 1):
            if kind == "code":
                hits = [m.group(0) for m in LITERAL.finditer(_code_and_comment(line)[0])]
            else:
                hits = [line]
            for h in hits:
                if h not in ALLOW and ("RustDesk" in h or URL.search(h)):
                    problems.append(f"{path.relative_to(root).as_posix()}:{n}: {h.strip()[:120]}")
    for path in sorted((root / "src" / "lang").glob("*.rs")):
        for n, line in enumerate(path.read_text(encoding="utf-8").split("\n"), 1):
            if PAIR.search(line) and ("RustDesk" in line or URL.search(line)):
                problems.append(f"{path.relative_to(root).as_posix()}:{n}: {line.strip()[:120]}")
    return problems


def rewrite_rust(root=ROOT):
    """Exact replacements; an upstream change that moves one of these strings fails the build."""
    problems = []
    for rel, pairs in RUST_TEXT.items():
        path = root / rel
        if not path.exists():
            continue
        text = path.read_text(encoding="utf-8")
        for old, new in pairs:
            if text.count(old) != 1:
                problems.append(f"{rel}: expected exactly one {old!r}")
            text = text.replace(old, new)
        path.write_text(text, encoding="utf-8")
    return problems


def main(root=ROOT, overlay=None):
    rust_problems = rewrite_rust(root)
    if rust_problems:
        print("\n".join(rust_problems), file=sys.stderr)
        return 1
    fa = root / "src" / "lang" / "fa.rs"
    if fa.exists():
        text, overlay_problems = apply_fa_overlay(fa.read_text(encoding="utf-8"), overlay)
        if overlay_problems:
            print("\n".join(overlay_problems), file=sys.stderr)
            return 1
        fa.write_text(text, encoding="utf-8")
    for path in (root / "src" / "lang").glob("*.rs"):
        path.write_text(rewrite_lang(path.read_text(encoding="utf-8"), path.stem), encoding="utf-8")
    for kind, path in _files(root):
        text = path.read_text(encoding="utf-8")
        path.write_text(rewrite_literals(text) if kind == "code" else rewrite_markup(text), encoding="utf-8")
    css = root / "src" / "ui" / "common.css"
    if css.exists():
        css.write_text(css.read_text(encoding="utf-8") + SCITER_CSS, encoding="utf-8")
    problems = scan(root)
    if fa.exists():
        problems += bidi_problems(fa.read_text(encoding="utf-8"))
    if problems:
        print("visible RustDesk text, links or reversed Persian remain:\n" + "\n".join(problems), file=sys.stderr)
        return 1
    print("rebranded: no visible RustDesk text, links or reversed Persian remain")
    return 0


if __name__ == "__main__":
    sys.exit(main())
