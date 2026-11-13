"""Validate dolphin/settings.json and one profile, then write the Rust constants the client compiles in.

Usage: python dolphin/gen_profile.py <profile> <variant> <version> [--without-fixed-password]
  profile = a file name in dolphin/profiles/, without .json
  variant = customer | technician
  version = dolphin/build_plan.py's version (2.0.0, 2.0.0-rc.1, 2.0.0-dev.412)
  --without-fixed-password = leave the fixed password out (checks and Dart analysis only, never an app build)

The fixed password (owner decision D21) comes from the environment variable DOLPHIN_FIXED_PASSWORD (a GitHub Actions
secret), never from git or the command line. A production build without it fails; a dev build leaves the feature out.
"""
import base64
import hashlib
import hmac
import os
import ipaddress
import json
import pathlib
import re
import sys
from urllib.parse import urlsplit

# The server settings go into OVERRIDE_SETTINGS; the profile's other keys are compiled in as their own constants.
SERVER_KEYS = ("custom-rendezvous-server", "relay-server", "key", "api-server")
# DD-24: the portal's strategy-signing public key (base64 of the raw 32-byte Ed25519 key, app/scripts/gen-signing-key.ts
# in the portal). Empty means the app applies pushed settings unchecked: dev builds only.
STRATEGY_KEY = "strategy-public-key"
PROFILE_KEYS = (*SERVER_KEYS, STRATEGY_KEY)
SECTIONS = ("override", "default", "local-override", "local-default", "builtin", "hard")

# Values no build may loosen: (section, key, value). Mirrors app/src/lib/engine/policy.ts in the portal
# plus the controls only the build can enforce (no update check, no deep-link re-pointing). Installation
# is allowed since ADR-0010 (portal repo); the window-open rule still holds for an installed client.
FLOOR = (
    ("override", "verification-method", "use-temporary-password"),
    ("override", "allow-only-conn-window-open", "Y"),
    ("override", "allow-remote-config-modification", "N"),
    ("override", "enable-tunnel", "N"),
    ("override", "direct-server", "N"),
    ("override", "allow-auto-update", "N"),
    # TB-9: recording stays off on the PC whatever is changed there (approved decision 6); opt-in needs a new build.
    ("override", "enable-record-session", "N"),
    ("local-override", "enable-check-update", "N"),
    # Owner 2026-11-09: a session is never cut because the technician is idle (portal policy.ts pushes the same).
    ("override", "allow-auto-disconnect", "N"),
    ("builtin", "allow-deep-link-server-settings", "N"),
    # D21: a deep link never carries a password, and nobody sets a permanent password on the PC (the fixed password is
    # Dolphin's own path, src/dolphin_fixed.rs, switched per organization by the portal).
    ("builtin", "allow-deep-link-password", "N"),
    ("builtin", "disable-change-permanent-password", "Y"),
)

VARIANTS = ("customer", "technician")
# Each build's direction is part of the floor: customers can only be connected to, technicians only connect.
VARIANT_FLOOR = {"customer": {"conn-type": "incoming"}, "technician": {"conn-type": "outgoing"}}
# A variant may have its own shown name (owner 2026-11-13: «دلفین کانکت کارشناس»). Only the shown name: app-name is what
# RustDesk uses in install paths, service and pipe names.
VARIANT_NAME_KEYS = ("display-name-fa", "display-name-en")
# Plan 19 (RO-6, RO-7): a variant may add its own local (per Windows account) and built-in settings, merged over the
# shared ones; the security floor still holds after the merge. Server settings (override/default) stay shared.
VARIANT_SECTIONS = ("local-override", "local-default", "builtin")
VARIANT_KEYS = {"app-name", "hard", *VARIANT_NAME_KEYS, *VARIANT_SECTIONS}
APP_NAME = re.compile(r"[A-Za-z0-9-]+")
# What customers see: names, site, support phone, and where the source is (AGPL-3.0 source offer).
BRAND_KEYS = ("display-name-fa", "display-name-en", "site", "support-phone", "source-url")
PHONE = re.compile(r"^[0-9۰-۹+\- ]{4,20}$")

HOST = re.compile(r"^[A-Za-z0-9.-]+(:\d{1,5})?$")
# Dolphin's own version (TB-4). RustDesk's crate::VERSION (1.5.0) stays: the protocol compares it with peers.
VERSION = re.compile(r"^\d+\.\d+\.\d+(-(dev|rc)\.\d+)?$")

# D21: one fixed password for every app, from a GitHub Actions secret. The apps never carry the owner's value itself:
# both use HMAC-SHA256(value, FIXED_CONTEXT) in hex as the RustDesk password, so a value extracted from an exe is good
# for Dolphin Connect only, not wherever else the same password may be used.
FIXED_ENV = "DOLPHIN_FIXED_PASSWORD"
FIXED_CONTEXT = b"dolphin-connect fixed password v1"
FIXED_MIN_LENGTH = 8
WITHOUT_FIXED = "--without-fixed-password"


def portal_url(profile):
    """The portal the apps talk to: the API server without its /rd path."""
    # The WebView reports its address normalised (lower-case host, no default port) and the apps compare by prefix,
    # so write it that way here or the bridge would never match.
    u = urlsplit(profile["api-server"].removesuffix("/rd").rstrip("/"))
    host = u.hostname or ""
    if ":" in host:
        host = f"[{host}]"
    default = {"https": 443, "http": 80}.get(u.scheme.lower())
    port = f":{u.port}" if u.port and u.port != default else ""
    return f"{u.scheme.lower()}://{host}{port}{u.path}"


def _private_host(host):
    if host == "localhost":
        return True
    try:
        ip = ipaddress.ip_address(host)
    except ValueError:
        return False
    return ip.is_loopback or ip.is_private


def validate_profile(profile, name):
    errors = []
    if set(profile) != set(PROFILE_KEYS):
        errors.append(f"profile {name}: keys must be exactly {', '.join(PROFILE_KEYS)}")
        return errors
    if not HOST.match(profile["custom-rendezvous-server"]):
        errors.append("custom-rendezvous-server: host or host:port, no scheme")
    relay = profile["relay-server"]
    if not HOST.match(relay) or ":" not in relay:
        errors.append("relay-server: host:port")
    try:
        if len(base64.b64decode(profile["key"], validate=True)) != 32:
            raise ValueError
    except ValueError:
        errors.append("key: the server's base64 ed25519 public key (id_ed25519.pub); empty until hbbs has run")
    strategy_key = profile[STRATEGY_KEY]
    try:
        if not isinstance(strategy_key, str) or (strategy_key and len(base64.b64decode(strategy_key, validate=True)) != 32):
            raise ValueError
    except ValueError:
        errors.append(f"{STRATEGY_KEY}: base64 of the raw 32-byte Ed25519 public key (the portal's gen-signing-key.ts), or empty")
    api = urlsplit(profile["api-server"])
    try:
        api.port  # raises ValueError for a port that is not a number or out of range
    except ValueError:
        errors.append("api-server: the port must be a number from 0 to 65535")
        return errors
    if profile["api-server"].endswith("/") or not api.hostname:
        errors.append("api-server: absolute URL without a trailing slash")
    elif api.scheme != "https" and not (api.scheme == "http" and _private_host(api.hostname)):
        errors.append("api-server: https, or http only on a loopback or private address")
    return errors


def validate_brand(brand):
    if not isinstance(brand, dict) or set(brand) != set(BRAND_KEYS) or not all(isinstance(v, str) for v in brand.values()):
        return [f"brand: exactly {', '.join(BRAND_KEYS)}, all strings"]
    errors = []
    for key in ("display-name-fa", "display-name-en"):
        if not brand[key].strip():
            errors.append(f"brand.{key}: required")
    for key in ("site", "source-url"):
        if not brand[key].startswith("https://"):
            errors.append(f"brand.{key}: an https:// URL")
    if brand["support-phone"] and not PHONE.match(brand["support-phone"]):
        errors.append("brand.support-phone: digits, spaces, + and - only (4 to 20)")
    return errors


def validate_settings(settings):
    errors = []
    if not APP_NAME.fullmatch(str(settings.get("app-name", ""))):
        errors.append("app-name: letters, digits and hyphens only (RustDesk uses it in paths and pipe names)")
    if set(settings) != {"app-name", "brand", "variants", *SECTIONS}:
        errors.append(f"settings: top-level keys must be app-name, brand, variants and {', '.join(SECTIONS)}")
        return errors
    errors += validate_brand(settings["brand"])
    for section in SECTIONS:
        values = settings[section]
        if not isinstance(values, dict) or not all(isinstance(k, str) and isinstance(v, str) for k, v in values.items()):
            errors.append(f"{section}: an object of string values")
            continue
        for key in PROFILE_KEYS:
            if key in values:
                errors.append(f"{section}.{key}: server settings come from the profile only")
    for section, key, value in FLOOR:
        if settings.get(section, {}).get(key) != value:
            errors.append(f"{section}.{key} must be {value!r}")
    variants = settings["variants"]
    if not isinstance(variants, dict) or set(variants) != set(VARIANTS):
        errors.append(f"variants: exactly {', '.join(VARIANTS)}")
        return errors
    for name, variant in variants.items():
        if not isinstance(variant, dict) or not set(variant) <= VARIANT_KEYS:
            errors.append(f"variants.{name}: only {', '.join(sorted(VARIANT_KEYS))}")
            continue
        if "app-name" in variant and not APP_NAME.fullmatch(str(variant["app-name"])):
            errors.append(f"variants.{name}.app-name: letters, digits and hyphens only")
        names = [k for k in VARIANT_NAME_KEYS if k in variant]
        if names and len(names) != len(VARIANT_NAME_KEYS):
            errors.append(f"variants.{name}: display-name-fa and display-name-en together, or neither")
        for key in names:
            value = variant[key]
            if not isinstance(value, str) or not value.strip() or any(ord(c) < 0x20 for c in value):
                errors.append(f"variants.{name}.{key}: a non-empty name without control characters")
        hard = variant.get("hard", {})
        if not isinstance(hard, dict) or not all(isinstance(k, str) and isinstance(v, str) for k, v in hard.items()):
            errors.append(f"variants.{name}.hard: an object of string values")
            continue
        for key, value in VARIANT_FLOOR[name].items():
            if hard.get(key) != value:
                errors.append(f"variants.{name}.hard.{key} must be {value!r}")
        for section in VARIANT_SECTIONS:
            values = variant.get(section, {})
            if not isinstance(values, dict) or not all(isinstance(k, str) and isinstance(v, str) for k, v in values.items()):
                errors.append(f"variants.{name}.{section}: an object of string values")
                continue
            for key in PROFILE_KEYS:
                if key in values:
                    errors.append(f"variants.{name}.{section}.{key}: server settings come from the profile only")
            for floor_section, key, value in FLOOR:
                if floor_section == section and key in values and values[key] != value:
                    errors.append(f"variants.{name}.{section}.{key} must be {value!r}")
    return errors


def rust_str(value):
    if any(ord(c) < 0x20 for c in value):
        raise ValueError("control characters are not allowed in settings")
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def dart_str(value):
    if any(ord(c) < 0x20 for c in value):
        raise ValueError("control characters are not allowed in settings")
    return "'" + value.replace("\\", "\\\\").replace("'", "\\'").replace("$", "\\$") + "'"


def display_names(settings, variant):
    """The name this build shows (Persian, English): the variant's own, else the brand's."""
    chosen, b = settings["variants"][variant], settings["brand"]
    return (chosen.get("display-name-fa", b["display-name-fa"]), chosen.get("display-name-en", b["display-name-en"]))


def render_brand_dart(settings, profile, version, variant="customer"):
    b = settings["brand"]
    site_label = b["site"].split("://", 1)[1].rstrip("/")
    app_fa, app_en = display_names(settings, variant)
    lines = [
        "// Generated by dolphin/gen_profile.py from dolphin/settings.json. Do not edit.",
        "class DolphinBrand {",
        # The product: the same in both apps (texts about Dolphin Connect itself).
        f"  static const String nameFa = {dart_str(b['display-name-fa'])};",
        f"  static const String nameEn = {dart_str(b['display-name-en'])};",
        # This build's own name ({variant}): window titles, About.
        f"  static const String appNameFa = {dart_str(app_fa)};",
        f"  static const String appNameEn = {dart_str(app_en)};",
        # The technician app's name, for its header (only the technician app shows it).
        f"  static const String technicianNameFa = {dart_str(display_names(settings, 'technician')[0])};",
        f"  static const String site = {dart_str(b['site'])};",
        f"  static const String siteLabel = {dart_str(site_label)};",
        f"  static const String supportPhone = {dart_str(b['support-phone'])};",
        f"  static const String sourceUrl = {dart_str(b['source-url'])};",
        # The staff panel the technician app shows, and where the apps ask for updates.
        f"  static const String portalUrl = {dart_str(portal_url(profile))};",
        f"  static const String version = {dart_str(version)};",
        "}",
    ]
    return "\n".join(lines) + "\n"


def variant_section(settings, variant, section):
    """One settings section for a build: the shared values with the variant's own over them (VARIANT_SECTIONS)."""
    return {**settings[section], **settings["variants"][variant].get(section, {})}


def _rust_map(name, values):
    lines = [f"pub const {name}: &[(&str, &str)] = &["]
    lines += [f"    ({rust_str(k)}, {rust_str(values[k])})," for k in sorted(values)]
    lines.append("];")
    return "\n".join(lines)


def render_rust(settings, profile, name, variant, version):
    override = {**settings["override"], **{k: profile[k] for k in SERVER_KEYS}}
    chosen = settings["variants"][variant]
    hard = {**settings["hard"], **chosen.get("hard", {})}
    parts = [
        f"// Generated by dolphin/gen_profile.py from dolphin/settings.json and dolphin/profiles/{name}.json"
        f" (variant {variant}). Do not edit.",
        f"pub const PROFILE: &str = {rust_str(name)};",
        f"pub const APP_NAME: &str = {rust_str(chosen.get('app-name', settings['app-name']))};",
        # The shown name (window title, Settings > Apps); APP_NAME stays for paths, service and pipe names.
        f"pub const DISPLAY_NAME_FA: &str = {rust_str(display_names(settings, variant)[0])};",
        f"pub const DISPLAY_NAME_EN: &str = {rust_str(display_names(settings, variant)[1])};",
        f"pub const RENDEZVOUS_SERVER: &str = {rust_str(profile['custom-rendezvous-server'])};",
        f"pub const DOLPHIN_VERSION: &str = {rust_str(version)};",
        f"pub const PORTAL_URL: &str = {rust_str(portal_url(profile))};",
        f"pub const SUPPORT_PHONE: &str = {rust_str(settings['brand']['support-phone'])};",
        # DD-24: checked by src/dolphin_strategy.rs; empty = no check (dev).
        f"pub const STRATEGY_PUBLIC_KEY: &str = {rust_str(profile.get(STRATEGY_KEY, ''))};",
        _rust_map("OVERRIDE_SETTINGS", override),
        _rust_map("DEFAULT_SETTINGS", settings["default"]),
        _rust_map("OVERRIDE_LOCAL_SETTINGS", variant_section(settings, variant, "local-override")),
        _rust_map("DEFAULT_LOCAL_SETTINGS", variant_section(settings, variant, "local-default")),
        _rust_map("BUILTIN_SETTINGS", variant_section(settings, variant, "builtin")),
        _rust_map("HARD_SETTINGS", hard),
    ]
    return "\n".join(parts) + "\n"


def validate_fixed_password(value):
    errors = []
    if len(value) < FIXED_MIN_LENGTH:
        errors.append(f"{FIXED_ENV}: at least {FIXED_MIN_LENGTH} characters")
    if any(ord(c) < 0x20 or ord(c) == 0x7F for c in value) or value != value.strip():
        errors.append(f"{FIXED_ENV}: no control characters and no spaces at either end")
    return errors


def fixed_secret(value):
    """What both apps use as the RustDesk password: derived, so the owner's value itself is in no exe."""
    return hmac.new(value.encode("utf-8"), FIXED_CONTEXT, hashlib.sha256).hexdigest()


def _rust_bytes(name, data):
    body = ", ".join(f"0x{b:02x}" for b in data)
    return f"pub static {name}: [u8; {len(data)}] = [{body}];"


def render_fixed_rust(secret, rand=os.urandom):
    """src/dolphin_fixed_generated.rs (git-ignored). With no secret the arrays are empty and the feature is off.

    This is obfuscation, not encryption: the app has to recover the value to use it, so the key is in the same exe.
    It only keeps the value out of a strings dump: masked = secret ^ pad_a ^ pad_b, three arrays with fresh random
    pads on every build, recombined at run time through black_box so the compiler cannot fold them back.
    """
    data = secret.encode("ascii") if secret else b""
    pad_a, pad_b = rand(len(data)), rand(len(data))
    masked = bytes(d ^ a ^ b for d, a, b in zip(data, pad_a, pad_b))
    lines = [
        "// Generated by dolphin/gen_profile.py (owner decision D21). Do not edit; git-ignored, never commit it.",
        "// Obfuscated, not encrypted: the app recovers the value at run time (src/dolphin_fixed.rs).",
        _rust_bytes("FIXED_MASKED", masked),
        _rust_bytes("FIXED_PAD_A", pad_a),
        _rust_bytes("FIXED_PAD_B", pad_b),
    ]
    return "\n".join(lines) + "\n"


def baked_settings(settings):
    """The server settings a portal compares against its own policy (profile keys excluded)."""
    return dict(sorted({**settings["default"], **settings["override"]}.items()))


def main(argv, root=pathlib.Path(__file__).resolve().parent.parent, env=None):
    env = os.environ if env is None else env
    without_fixed = WITHOUT_FIXED in argv
    argv = [a for a in argv if a != WITHOUT_FIXED]
    if len(argv) != 3:
        print(__doc__, file=sys.stderr)
        return 2
    name, variant, version = argv
    settings = json.loads((root / "dolphin" / "settings.json").read_text(encoding="utf-8"))
    profile_path = root / "dolphin" / "profiles" / f"{name}.json"
    if not re.fullmatch(r"[a-z]+", name) or not profile_path.is_file():
        print(f"unknown profile: {name}", file=sys.stderr)
        return 1
    if variant not in VARIANTS:
        print(f"unknown variant: {variant} (use {' or '.join(VARIANTS)})", file=sys.stderr)
        return 1
    if not VERSION.match(version):
        print(f"version: X.Y.Z, X.Y.Z-dev.N or X.Y.Z-rc.N, not {version!r}", file=sys.stderr)
        return 1
    profile = json.loads(profile_path.read_text(encoding="utf-8"))
    errors = validate_settings(settings) + validate_profile(profile, name)
    if not errors and name == "production" and not settings["brand"]["support-phone"]:
        errors.append("brand.support-phone: required for production builds (shown in the customer window)")
    # DD-24: a production app must refuse settings the portal did not sign. The owner makes the pair with the portal's
    # app/scripts/gen-signing-key.ts: the private key goes to Coolify, the public key into dolphin/profiles/production.json.
    if not errors and name == "production" and not profile[STRATEGY_KEY]:
        errors.append(f"{STRATEGY_KEY}: required for production builds (the portal's app/scripts/gen-signing-key.ts, DD-24)")
    # D21. Never print the value or anything derived from it.
    fixed_value = env.get(FIXED_ENV, "")
    secret = None
    if without_fixed:
        fixed_note = "fixed password: left out on purpose (--without-fixed-password; checks only, not an app build)"
    elif fixed_value:
        errors += validate_fixed_password(fixed_value)
        secret = fixed_secret(fixed_value)
        fixed_note = "fixed password: built in (obfuscated)"
    elif name == "production":
        errors.append(f"{FIXED_ENV}: required for production builds (a GitHub Actions secret of the fork)")
    else:
        fixed_note = f"fixed password: {FIXED_ENV} is not set, so this {name} build has no fixed password (feature off)"
    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    (root / "src" / "dolphin_generated.rs").write_text(render_rust(settings, profile, name, variant, version), encoding="utf-8")
    (root / "src" / "dolphin_fixed_generated.rs").write_text(render_fixed_rust(secret), encoding="utf-8")
    print(fixed_note)
    dart_dir = root / "flutter" / "lib" / "dolphin"
    dart_dir.mkdir(parents=True, exist_ok=True)
    (dart_dir / "brand.dart").write_text(render_brand_dart(settings, profile, version, variant), encoding="utf-8")
    build = root / "dolphin" / "build"
    build.mkdir(exist_ok=True)
    (build / "baked-settings.json").write_text(json.dumps(baked_settings(settings), indent=2) + "\n", encoding="utf-8")
    print(f"profile {name}, variant {variant}: src/dolphin_generated.rs, flutter/lib/dolphin/brand.dart and dolphin/build/baked-settings.json written")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
