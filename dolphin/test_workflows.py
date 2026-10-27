"""Text checks on the Dolphin workflows: cheap guards for rules a YAML edit could silently drop (TB-1)."""
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent
BUILD = (ROOT / ".github" / "workflows" / "dolphin-build.yml").read_text(encoding="utf-8")
CHECK = (ROOT / ".github" / "workflows" / "dolphin-check.yml").read_text(encoding="utf-8")


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

    def test_thin_lto_is_for_dev_builds_only(self):
        lines = BUILD.splitlines()
        hits = [i for i, line in enumerate(lines) if "CARGO_PROFILE_RELEASE_LTO=thin" in line]
        self.assertEqual(len(hits), 2)  # the x64 and the x86 job
        for i in hits:
            self.assertIn("if: inputs.profile == 'dev'", "\n".join(lines[max(0, i - 6):i]))

    def test_the_fast_check_runs_on_every_push_to_dolphin_and_is_reusable(self):
        self.assertRegex(CHECK, r"\non:\n  push:\n    branches: \[dolphin\]\n  workflow_call:\n")
        for job in ("test:", "generate-bridge:", "analyze-and-test:"):
            self.assertIn(f"\n  {job}\n", CHECK)

    def test_the_build_runs_the_same_check_first(self):
        self.assertIn("uses: ./.github/workflows/dolphin-check.yml", BUILD)
        self.assertNotIn("\n  analyze-and-test:\n", BUILD)
        self.assertIn("needs: [check, guard]", BUILD)


    def test_std_only_rust_files_are_tested_in_ci(self):
        for path in ("dolphin/version_resource.rs",):
            self.assertIn(f"rustc --edition 2021 --test {path}", CHECK)

    def test_every_exe_has_its_version_resource_checked(self):
        self.assertEqual(BUILD.count("name: Version resource (TB-4)"), 2)


if __name__ == "__main__":
    unittest.main()
