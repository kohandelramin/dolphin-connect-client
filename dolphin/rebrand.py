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


def main(root=ROOT):
    rust_problems = rewrite_rust(root)
    if rust_problems:
        print("\n".join(rust_problems), file=sys.stderr)
        return 1
    for path in (root / "src" / "lang").glob("*.rs"):
        path.write_text(rewrite_lang(path.read_text(encoding="utf-8"), path.stem), encoding="utf-8")
    for kind, path in _files(root):
        text = path.read_text(encoding="utf-8")
        path.write_text(rewrite_literals(text) if kind == "code" else rewrite_markup(text), encoding="utf-8")
    css = root / "src" / "ui" / "common.css"
    if css.exists():
        css.write_text(css.read_text(encoding="utf-8") + SCITER_CSS, encoding="utf-8")
    problems = scan(root)
    if problems:
        print("visible RustDesk text or links remain:\n" + "\n".join(problems), file=sys.stderr)
        return 1
    print("rebranded: no visible RustDesk text or links remain")
    return 0


if __name__ == "__main__":
    sys.exit(main())
