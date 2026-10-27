"""Which apps a Dolphin build run makes (TB-1).

Usage (CI, guard job): python dolphin/build_plan.py plan --profile dev --builds customer-x64 --tag "" >> "$GITHUB_OUTPUT"
"""
import argparse
import json
import sys

BUILDS = ("customer-x64", "technician-x64", "customer-x86", "x64", "all")
X64 = {
    "customer-x64": ["customer"],
    "technician-x64": ["technician"],
    "customer-x86": [],
    "x64": ["customer", "technician"],
    "all": ["customer", "technician"],
}


def select(profile, builds):
    """(x64 variants, x86?). Most dev work is in flutter/lib/dolphin, which the Sciter x86 build does not use, so a
    dev run builds what was asked; a production run always builds all three, because a release is never partial."""
    if profile == "production":
        return ["customer", "technician"], True
    if builds not in BUILDS:
        raise ValueError(f"builds must be one of {', '.join(BUILDS)}, not {builds!r}")
    return X64[builds], builds in ("customer-x86", "all")


def plan(profile, builds, tag):
    if tag and profile != "production":
        raise ValueError("Releases are production builds only.")
    x64, x86 = select(profile, builds)
    return {"x64": json.dumps(x64), "x86": "true" if x86 else "false"}


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    p = sub.add_parser("plan")
    p.add_argument("--profile", required=True, choices=("dev", "production"))
    p.add_argument("--builds", required=True)
    p.add_argument("--tag", default="")
    args = parser.parse_args(argv)
    try:
        out = plan(args.profile, args.builds, args.tag)
    except ValueError as e:
        print(e, file=sys.stderr)
        return 1
    for key, value in out.items():
        print(f"{key}={value}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
