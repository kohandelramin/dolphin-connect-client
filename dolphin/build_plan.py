"""Which apps a Dolphin build run makes and which version they carry (TB-1, TB-4).

Usage (CI):
  python dolphin/build_plan.py plan --profile dev --builds customer-x64 --tag "" --run 412 >> "$GITHUB_OUTPUT"
  python dolphin/build_plan.py pubspec --run 412 --version 2.1.0-rc.1
      (x64 jobs: the Flutter exe's numbers, and its FileVersion / ProductVersion strings in Runner.rc)
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
# flutter/windows/runner/Runner.rc writes FLUTTER_VERSION ("2.1.0+412", from pubspec) into both version strings, so the
# inner exe of an x64 build said "2.1.0+412" where the downloaded (packer) exe says FileVersion 2.1.0.412 and
# ProductVersion 2.1.0-rc.1. These two lines get the same literal strings as the packer (Plan 19, version accuracy).
RC_VERSION_LINE = re.compile(r'^([ \t]*VALUE "(FileVersion|ProductVersion)", )VERSION_AS_STRING( "\\0"\r?)$', re.M)


def select(profile, builds, tag=""):
    """(x64 variants, x86?). Most dev work is in flutter/lib/dolphin, which the Sciter x86 build does not use, so a
    test run builds what was asked; a release (a tag) always builds all three, because a release is never partial."""
    if profile == "production" and tag:
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
    x64, x86 = select(profile, builds, tag)
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


def set_rc_versions(text, version, file_version):
    """Runner.rc's FileVersion string becomes X.Y.Z.<run> and ProductVersion our version (2.1.0-rc.1), as the packer's."""
    values = {"FileVersion": file_version, "ProductVersion": version}
    new, count = RC_VERSION_LINE.subn(lambda m: f'{m.group(1)}"{values[m.group(2)]}"{m.group(3)}', text)
    if count != 2:
        raise ValueError(f"Runner.rc: expected the FileVersion and ProductVersion lines, found {count}")
    return new


def check_build_version(base, run, version):
    """The version a job was given belongs to this version.txt and run: X.Y.Z, X.Y.Z-rc.N or X.Y.Z-dev.<run>."""
    m = re.match(r"^(\d+\.\d+\.\d+)(-rc\.[1-9]\d*|-dev\.(\d+))?$", version)
    if not m or m.group(1) != base or (m.group(3) is not None and int(m.group(3)) != run):
        raise ValueError(f"version {version!r} is not {base}, {base}-rc.N or {base}-dev.{run}")


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
    s.add_argument("--version", required=True)
    args = parser.parse_args(argv)
    try:
        base = read_base(root)
        if args.command == "pubspec":
            _, file_version = version(base, "", args.run)  # same range checks
            check_build_version(base, args.run, args.version)
            pubspec = root / "flutter" / "pubspec.yaml"
            rc = root / "flutter" / "windows" / "runner" / "Runner.rc"
            # newline="": Runner.rc keeps its CRLF line ends. open(), not read_text with a newline argument: the Windows runner's
            # Python is older than 3.13 (run 43567939887).
            with rc.open(encoding="utf-8", newline="") as f:
                new_rc = set_rc_versions(f.read(), args.version, file_version)
            pubspec.write_text(set_pubspec_version(pubspec.read_text(encoding="utf-8"), base, args.run), encoding="utf-8")
            with rc.open("w", encoding="utf-8", newline="") as f:
                f.write(new_rc)
            print(f"flutter/pubspec.yaml: version {base}+{args.run}; Runner.rc: FileVersion {file_version}, ProductVersion {args.version}")
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
