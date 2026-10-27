"""Which apps a Dolphin build run makes and which version they carry (TB-1, TB-4).

Usage (CI):
  python dolphin/build_plan.py plan --profile dev --builds customer-x64 --tag "" --run 412 >> "$GITHUB_OUTPUT"
  python dolphin/build_plan.py pubspec --run 412     (x64 jobs: the Flutter exe's FileVersion)
"""
import argparse
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
BUILDS = ("customer-x64", "technician-x64", "customer-x86", "x64", "all")
X64 = {
    "customer-x64": ["customer"],
    "technician-x64": ["technician"],
    "customer-x86": [],
    "x64": ["customer", "technician"],
    "all": ["customer", "technician"],
}
BASE = re.compile(r"^\d+\.\d+\.\d+$")
# Release tags: the number in dolphin/version.txt, or a release candidate of it (owner decision D3: 2.0.0 first).
TAG = re.compile(r"^v(\d+\.\d+\.\d+)(-rc\.[1-9]\d*)?$")
PUBSPEC_VERSION = re.compile(r"^version: .*$", re.M)


def select(profile, builds):
    """(x64 variants, x86?). Most dev work is in flutter/lib/dolphin, which the Sciter x86 build does not use, so a
    dev run builds what was asked; a production run always builds all three, because a release is never partial."""
    if profile == "production":
        return ["customer", "technician"], True
    if builds not in BUILDS:
        raise ValueError(f"builds must be one of {', '.join(BUILDS)}, not {builds!r}")
    return X64[builds], builds in ("customer-x86", "all")


def version(base, tag, run):
    """(version, file_version). A tag gives a release (2.0.0) or a release candidate (2.0.0-rc.1); no tag gives a
    test build 2.0.0-dev.<run>, which never updates itself (src/dolphin_update_core.rs). The file version is
    X.Y.Z.<run>: Windows wants four numbers of at most 65535. RustDesk's 1.5.0 stays crate::VERSION."""
    if not BASE.match(base):
        raise ValueError(f"dolphin/version.txt must be X.Y.Z, not {base!r}")
    if not 1 <= run <= 65535:
        raise ValueError(f"run number {run} does not fit a Windows file version (1 to 65535)")
    if tag:
        m = TAG.match(tag)
        if not m or m.group(1) != base:
            raise ValueError(f"tag must be v{base} or v{base}-rc.N (dolphin/version.txt is {base}), not {tag!r}")
        v = tag[1:]
    else:
        v = f"{base}-dev.{run}"
    return v, f"{base}.{run}"


def plan(profile, builds, tag, base, run):
    if tag and profile != "production":
        raise ValueError("Releases are production builds only.")
    x64, x86 = select(profile, builds)
    v, file_version = version(base, tag, run)
    return {
        "x64": json.dumps(x64),
        "x86": "true" if x86 else "false",
        "version": v,
        "file_version": file_version,
        "prerelease": "true" if "-" in v else "false",
    }


def set_pubspec_version(text, base, run):
    """flutter/pubspec.yaml `version:` becomes X.Y.Z+<run>; Flutter writes it into the exe as FileVersion X.Y.Z.<run>."""
    new, count = PUBSPEC_VERSION.subn(f"version: {base}+{run}", text, count=1)
    if count != 1:
        raise ValueError("flutter/pubspec.yaml: no top-level version line")
    return new


def read_base(root=ROOT):
    return (root / "dolphin" / "version.txt").read_text(encoding="utf-8").strip()


def main(argv, root=ROOT):
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    p = sub.add_parser("plan")
    p.add_argument("--profile", required=True, choices=("dev", "production"))
    p.add_argument("--builds", required=True)
    p.add_argument("--tag", default="")
    p.add_argument("--run", required=True, type=int)
    s = sub.add_parser("pubspec")
    s.add_argument("--run", required=True, type=int)
    args = parser.parse_args(argv)
    try:
        base = read_base(root)
        if args.command == "pubspec":
            version(base, "", args.run)  # same range checks
            pubspec = root / "flutter" / "pubspec.yaml"
            pubspec.write_text(set_pubspec_version(pubspec.read_text(encoding="utf-8"), base, args.run), encoding="utf-8")
            print(f"flutter/pubspec.yaml: version {base}+{args.run}")
            return 0
        out = plan(args.profile, args.builds, args.tag, base, args.run)
    except ValueError as e:
        print(e, file=sys.stderr)
        return 1
    for key, value in out.items():
        print(f"{key}={value}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
