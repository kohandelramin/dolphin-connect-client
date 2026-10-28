"""Validate dolphin/settings.json and one profile, then write the Rust constants the client compiles in.

Usage: python dolphin/gen_profile.py <profile> <variant> <version>
  profile = a file name in dolphin/profiles/, without .json
  variant = customer | technician
  version = dolphin/build_plan.py's version (2.0.0, 2.0.0-rc.1, 2.0.0-dev.412)
"""
import base64
import ipaddress
import json
import pathlib
import re
import sys
from urllib.parse import urlsplit

PROFILE_KEYS = ("custom-rendezvous-server", "relay-server", "key", "api-server")
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
    ("local-override", "enable-check-update", "N"),
    ("builtin", "allow-deep-link-server-settings", "N"),
)

VARIANTS = ("customer", "technician")
# Each build's direction is part of the floor: customers can only be connected to, technicians only connect.
VARIANT_FLOOR = {"customer": {"conn-type": "incoming"}, "technician": {"conn-type": "outgoing"}}
APP_NAME = re.compile(r"[A-Za-z0-9-]+")
# What customers see: names, site, support phone, and where the source is (AGPL-3.0 source offer).
BRAND_KEYS = ("display-name-fa", "display-name-en", "site", "support-phone", "source-url")
PHONE = re.compile(r"^[0-9۰-۹+\- ]{4,20}$")

HOST = re.compile(r"^[A-Za-z0-9.-]+(:\d{1,5})?$")
# Dolphin's own version (TB-4). RustDesk's crate::VERSION (1.5.0) stays: the protocol compares it with peers.
VERSION = re.compile(r"^\d+\.\d+\.\d+(-(dev|rc)\.\d+)?$")


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
    api = urlsplit(profile["api-server"])
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
        if not isinstance(variant, dict) or not set(variant) <= {"app-name", "hard"}:
            errors.append(f"variants.{name}: only app-name and hard")
            continue
        if "app-name" in variant and not APP_NAME.fullmatch(str(variant["app-name"])):
            errors.append(f"variants.{name}.app-name: letters, digits and hyphens only")
        hard = variant.get("hard", {})
        if not isinstance(hard, dict) or not all(isinstance(k, str) and isinstance(v, str) for k, v in hard.items()):
            errors.append(f"variants.{name}.hard: an object of string values")
            continue
        for key, value in VARIANT_FLOOR[name].items():
            if hard.get(key) != value:
                errors.append(f"variants.{name}.hard.{key} must be {value!r}")
    return errors


def rust_str(value):
    if any(ord(c) < 0x20 for c in value):
        raise ValueError("control characters are not allowed in settings")
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def dart_str(value):
    if any(ord(c) < 0x20 for c in value):
        raise ValueError("control characters are not allowed in settings")
    return "'" + value.replace("\\", "\\\\").replace("'", "\\'").replace("$", "\\$") + "'"


def render_brand_dart(settings, profile, version):
    b = settings["brand"]
    site_label = b["site"].split("://", 1)[1].rstrip("/")
    lines = [
        "// Generated by dolphin/gen_profile.py from dolphin/settings.json. Do not edit.",
        "class DolphinBrand {",
        f"  static const String nameFa = {dart_str(b['display-name-fa'])};",
        f"  static const String nameEn = {dart_str(b['display-name-en'])};",
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


def _rust_map(name, values):
    lines = [f"pub const {name}: &[(&str, &str)] = &["]
    lines += [f"    ({rust_str(k)}, {rust_str(values[k])})," for k in sorted(values)]
    lines.append("];")
    return "\n".join(lines)


def render_rust(settings, profile, name, variant, version):
    override = {**settings["override"], **profile}
    chosen = settings["variants"][variant]
    hard = {**settings["hard"], **chosen.get("hard", {})}
    parts = [
        f"// Generated by dolphin/gen_profile.py from dolphin/settings.json and dolphin/profiles/{name}.json"
        f" (variant {variant}). Do not edit.",
        f"pub const PROFILE: &str = {rust_str(name)};",
        f"pub const APP_NAME: &str = {rust_str(chosen.get('app-name', settings['app-name']))};",
        f"pub const RENDEZVOUS_SERVER: &str = {rust_str(profile['custom-rendezvous-server'])};",
        f"pub const DOLPHIN_VERSION: &str = {rust_str(version)};",
        f"pub const PORTAL_URL: &str = {rust_str(portal_url(profile))};",
        f"pub const SUPPORT_PHONE: &str = {rust_str(settings['brand']['support-phone'])};",
        _rust_map("OVERRIDE_SETTINGS", override),
        _rust_map("DEFAULT_SETTINGS", settings["default"]),
        _rust_map("OVERRIDE_LOCAL_SETTINGS", settings["local-override"]),
        _rust_map("DEFAULT_LOCAL_SETTINGS", settings["local-default"]),
        _rust_map("BUILTIN_SETTINGS", settings["builtin"]),
        _rust_map("HARD_SETTINGS", hard),
    ]
    return "\n".join(parts) + "\n"


def baked_settings(settings):
    """The server settings a portal compares against its own policy (profile keys excluded)."""
    return dict(sorted({**settings["default"], **settings["override"]}.items()))


def main(argv, root=pathlib.Path(__file__).resolve().parent.parent):
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
    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    (root / "src" / "dolphin_generated.rs").write_text(render_rust(settings, profile, name, variant, version), encoding="utf-8")
    dart_dir = root / "flutter" / "lib" / "dolphin"
    dart_dir.mkdir(parents=True, exist_ok=True)
    (dart_dir / "brand.dart").write_text(render_brand_dart(settings, profile, version), encoding="utf-8")
    build = root / "dolphin" / "build"
    build.mkdir(exist_ok=True)
    (build / "baked-settings.json").write_text(json.dumps(baked_settings(settings), indent=2) + "\n", encoding="utf-8")
    print(f"profile {name}, variant {variant}: src/dolphin_generated.rs, flutter/lib/dolphin/brand.dart and dolphin/build/baked-settings.json written")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
