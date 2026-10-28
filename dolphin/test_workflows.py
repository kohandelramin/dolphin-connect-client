"""Text checks on the Dolphin workflows: cheap guards for rules a YAML edit could silently drop (TB-1)."""
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent
BUILD = (ROOT / ".github" / "workflows" / "dolphin-build.yml").read_text(encoding="utf-8")
CHECK = (ROOT / ".github" / "workflows" / "dolphin-check.yml").read_text(encoding="utf-8")
ANALYZE = (ROOT / ".github" / "workflows" / "dolphin-analyze.yml").read_text(encoding="utf-8")
BRIDGE = (ROOT / ".github" / "workflows" / "bridge.yml").read_text(encoding="utf-8")


def job(text, name):
    """The text of one top-level job."""
    return text.split(f"\n  {name}:\n", 1)[1].split("\n\n  ", 1)[0]

class BuildWorkflowTest(unittest.TestCase):
    def test_vcpkg_uses_a_files_cache_kept_by_actions_cache(self):
        self.assertNotIn("x-gha", BUILD)
        self.assertIn("clear;files,C:\\vcpkg-binary-cache,readwrite", BUILD)
        self.assertEqual(len(re.findall(r"uses: actions/cache@[0-9a-f]{40}", BUILD)), 2)

    def test_builds_input_defaults_to_the_customer_x64_app(self):
        block = BUILD.split("      builds:", 1)[1].split("      release-tag:", 1)[0]
        self.assertIn("default: customer-x64", block)
        for choice in ("customer-x64", "technician-x64", "customer-x86", "x64", "all"):
            self.assertIn(choice, block)

    def test_lto_is_relaxed_for_dev_builds_only(self):
        lines = BUILD.splitlines()
        self.assertNotIn("CARGO_PROFILE_RELEASE_LTO=thin", BUILD)
        hits = [i for i, line in enumerate(lines) if "CARGO_PROFILE_RELEASE_LTO=off" in line]
        self.assertEqual(len(hits), 2)  # the x64 and the x86 job
        for i in hits:
            self.assertIn("if: inputs.profile == 'dev'", "\n".join(lines[max(0, i - 6):i]))

    def test_the_fast_check_runs_on_every_push_to_dolphin_and_is_reusable(self):
        self.assertRegex(CHECK, r"\non:\n  push:\n    branches: \[dolphin\]\n  workflow_call:\n")
        for name in ("test:", "generate-bridge:", "analyze-and-test:"):
            self.assertIn(f"\n  {name}\n", CHECK)

    def test_the_build_runs_the_fast_check_first(self):
        self.assertIn("uses: ./.github/workflows/dolphin-check.yml", BUILD)
        self.assertIn("fast-only: true", BUILD)

    def test_windows_builds_wait_for_the_bridge_not_for_the_dart_analysis(self):
        x64 = job(BUILD, "build-windows")
        self.assertIn("needs: [check, guard, bridge]", x64)
        self.assertNotIn("analyze-and-test", x64)
        x86 = job(BUILD, "build-windows-x86")
        self.assertIn("needs: [check, guard]", x86)
        self.assertNotIn("analyze-and-test", x86)
        self.assertIn("needs: bridge", job(BUILD, "analyze-and-test"))
        self.assertIn("uses: ./.github/workflows/dolphin-analyze.yml", BUILD)

    def test_a_release_still_needs_every_check(self):
        needs = re.search(r"\n  release:\n    needs: \[([^\]]*)\]", BUILD).group(1)
        names = [n.strip() for n in needs.split(",")]
        for name in ("guard", "check", "analyze-and-test", "build-windows", "build-windows-x86"):
            self.assertIn(name, names)
        release = job(BUILD, "release")
        # the gate is exactly this line; a status function or continue-on-error would let a release follow a failed check
        self.assertIn("\n    if: inputs.profile == 'production' && inputs.release-tag != ''\n", release)
        for text in ("always()", "!cancelled()", "failure()", "success() ||", "continue-on-error"):
            self.assertNotIn(text, release)
        # check, bridge and analyze-and-test run on a production run too, so none of them may be skipped by an if:
        for name in ("check", "bridge", "analyze-and-test"):
            self.assertNotIn("if:", job(BUILD, name))

    def test_a_push_still_runs_the_whole_check_and_the_analysis_is_shared(self):
        self.assertIn("uses: ./.github/workflows/dolphin-analyze.yml", CHECK)
        self.assertIn("flutter analyze", ANALYZE)
        self.assertIn("flutter test test/dolphin", ANALYZE)
        # fast-only is off by default, so a push and any other caller run everything
        self.assertRegex(CHECK, r"fast-only:\n        type: boolean\n        default: false")
        for name in ("generate-bridge", "analyze-and-test"):
            self.assertIn("if: ${{ !inputs.fast-only }}", job(CHECK, name))

    def test_the_tests_and_the_std_only_rust_never_skip_on_fast_only(self):
        # fast-only skips the bridge and the Dart analysis; the Python tests and the std-only Rust run on every caller
        for name in ("test", "rust-unit"):
            self.assertNotIn("fast-only", job(CHECK, name))

    def test_generated_bridge_is_cached_on_a_key_of_its_inputs(self):
        step = BRIDGE.split("name: Generated bridge cache (Dolphin)", 1)[1].split("- name: Install prerequisites", 1)[0]
        for part in ("matrix.job.flutter-version", "FLUTTER_RUST_BRIDGE_VERSION", "CARGO_EXPAND_VERSION",
                     "RUST_VERSION", "matrix.job.os", "'src/**'", "'libs/**'", "'Cargo.lock'", "'Cargo.toml'",
                     "'build.rs'", "'flutter/pubspec.lock'", "'.github/workflows/bridge.yml'"):
            self.assertIn(part, step)
        for f in ("src/bridge_generated.rs", "src/bridge_generated.io.rs", "flutter/lib/generated_bridge.dart",
                  "flutter/lib/generated_bridge.freezed.dart", "flutter/macos/Runner/bridge_generated.h",
                  "flutter/ios/Runner/bridge_generated.h"):
            self.assertIn(f, step)
        # every generation step is skipped on a hit; the upload is not
        for name in ("Install prerequisites", "Install Rust toolchain", "Install flutter rust bridge deps",
                     "Run flutter rust bridge"):
            block = BRIDGE.split(f"- name: {name}\n", 1)[1].split("\n      - ", 1)[0]
            self.assertIn("steps.gen.outputs.cache-hit != 'true'", block, name)
        self.assertNotIn("cache-hit", BRIDGE.split("- name: Upload Artifact", 1)[1])

    def test_dev_packs_with_a_low_brotli_quality_and_production_keeps_the_default(self):
        self.assertEqual(BUILD.count("PACK_LEVEL: ${{ inputs.profile == 'dev' && '5' || '11' }}"), 2)
        self.assertEqual(BUILD.count('-l "$PACK_LEVEL"'), 2)
        gen = (ROOT / "libs" / "portable" / "generate.py").read_text(encoding="utf-8")
        self.assertIn('dest="level", type="int"', gen)
        self.assertIn("default=11", gen)

    def test_flutter_sdk_is_not_cached(self):
        # Measured slower (restore 98 s against 73-77 s to install; run 40626568964), and the cache would be saved
        # after the engine swap and the patch. Keep it off unless a measurement says otherwise.
        step = BUILD.split("name: Install flutter", 1)[1].split("- name: Replace engine", 1)[0]
        self.assertNotIn("cache:", step)

    def test_std_only_rust_files_are_tested_in_ci(self):
        std_only = ("dolphin/version_resource.rs", "src/dolphin_update_core.rs", "libs/portable/src/dolphin_wait.rs")
        for path in std_only:
            self.assertIn(f"rustc --edition 2021 --test {path}", CHECK)
        # rust-unit tests exactly these: a new std-only file needs a line in the job and in this tuple
        tested = re.findall(r"rustc --edition 2021 --test (\S+)", job(CHECK, "rust-unit"))
        self.assertEqual(sorted(tested), sorted(std_only))

    def test_every_exe_has_its_version_resource_checked(self):
        self.assertEqual(BUILD.count("name: Version resource (TB-4)"), 2)


if __name__ == "__main__":
    unittest.main()
