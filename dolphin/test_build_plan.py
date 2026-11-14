import contextlib
import io
import json
import pathlib
import tempfile
import unittest

import build_plan as b


class SelectTest(unittest.TestCase):
    def test_a_dev_run_builds_only_the_customer_x64_app_by_default(self):
        self.assertEqual(b.select("dev", "customer-x64"), (["customer"], False))

    def test_each_choice_selects_its_builds(self):
        self.assertEqual(b.select("dev", "technician-x64"), (["technician"], False))
        self.assertEqual(b.select("dev", "customer-x86"), ([], True))
        self.assertEqual(b.select("dev", "x64"), (["customer", "technician"], False))
        self.assertEqual(b.select("dev", "all"), (["customer", "technician"], True))

    def test_a_production_release_always_builds_all_three(self):
        for builds in b.BUILDS:
            self.assertEqual(b.select("production", builds, "v2.2.0"), (["customer", "technician"], True))
            self.assertEqual(b.plan("production", builds, "v2.2.0-rc.1", "2.2.0", 7)["x86"], "true")

    def test_a_production_test_build_builds_what_was_asked(self):
        # No tag: an artifact for the owner's PCs (version X.Y.Z-dev.<run>, never offered by the portal), so the
        # technician can be built while the customer app is still being coded (owner, 2026-11-14).
        self.assertEqual(b.select("production", "technician-x64", ""), (["technician"], False))
        self.assertEqual(b.select("production", "customer-x64", ""), (["customer"], False))
        self.assertEqual(b.select("production", "all", ""), (["customer", "technician"], True))
        p = b.plan("production", "technician-x64", "", "2.2.0", 31)
        self.assertEqual((p["x64"], p["x86"], p["version"]), ('["technician"]', "false", "2.2.0-dev.31"))

    def test_an_unknown_choice_is_refused(self):
        with self.assertRaises(ValueError):
            b.select("dev", "everything")


class VersionTest(unittest.TestCase):
    def test_a_test_build_is_a_dev_prerelease_of_the_next_number(self):
        self.assertEqual(b.version("2.0.0", "", 412), ("2.0.0-dev.412", "2.0.0.412"))

    def test_tags_give_a_release_or_a_release_candidate(self):
        self.assertEqual(b.version("2.0.0", "v2.0.0", 413), ("2.0.0", "2.0.0.413"))
        self.assertEqual(b.version("2.0.0", "v2.0.0-rc.1", 414), ("2.0.0-rc.1", "2.0.0.414"))

    def test_a_tag_must_match_version_txt(self):
        for tag in ("v2.0.1", "2.0.0", "v2.0", "1.5.0-dc.5", "v2.0.0-beta.1", "v2.0.0-rc.0", "v2.0.0-rc.01"):
            with self.assertRaises(ValueError, msg=tag):
                b.version("2.0.0", tag, 1)

    def test_the_run_number_must_fit_a_windows_file_version(self):
        with self.assertRaises(ValueError):
            b.version("2.0.0", "", 65536)
        with self.assertRaises(ValueError):
            b.version("2.0.0", "", 0)
        with self.assertRaises(ValueError):
            b.version("2.0", "", 1)


class PlanTest(unittest.TestCase):
    def test_outputs_are_github_output_values(self):
        out = b.plan("dev", "x64", "", "2.0.0", 9)
        self.assertEqual(json.loads(out["x64"]), ["customer", "technician"])
        self.assertEqual([out["x86"], out["version"], out["file_version"], out["prerelease"]], ["false", "2.0.0-dev.9", "2.0.0.9", "true"])
        self.assertEqual(b.plan("production", "customer-x64", "v2.0.0", "2.0.0", 10)["prerelease"], "false")
        self.assertEqual(b.plan("production", "customer-x64", "v2.0.0-rc.2", "2.0.0", 11)["prerelease"], "true")

    def test_a_release_tag_needs_the_production_profile(self):
        with self.assertRaises(ValueError):
            b.plan("dev", "all", "v2.0.0", "2.0.0", 1)

    def test_pubspec_gets_the_number_flutter_turns_into_the_file_version(self):
        text = "name: flutter_hbb\nversion: 1.5.0+68\ndependencies:\n  x:\n    version: ^1.0.0\n"
        self.assertEqual(b.set_pubspec_version(text, "2.0.0", 412), "name: flutter_hbb\nversion: 2.0.0+412\ndependencies:\n  x:\n    version: ^1.0.0\n")
        with self.assertRaises(ValueError):
            b.set_pubspec_version("name: x\n", "2.0.0", 1)

    def test_main_reads_version_txt_and_prints_key_value_lines(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            (root / "dolphin").mkdir()
            (root / "dolphin" / "version.txt").write_text("2.0.0\n", encoding="utf-8")
            (root / "flutter").mkdir()
            (root / "flutter" / "pubspec.yaml").write_text("version: 1.5.0+68\n", encoding="utf-8")
            (root / "flutter" / "windows" / "runner").mkdir(parents=True)
            rc = root / "flutter" / "windows" / "runner" / "Runner.rc"
            rc.write_bytes(RC_LINES.encode("utf-8"))
            out = io.StringIO()
            with contextlib.redirect_stdout(out):
                self.assertEqual(b.main(["plan", "--profile", "dev", "--builds", "customer-x86", "--run", "7"], root), 0)
            self.assertEqual(out.getvalue().splitlines(), ["x64=[]", "x86=true", "version=2.0.0-dev.7", "file_version=2.0.0.7", "prerelease=true"])
            with contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(b.main(["pubspec", "--run", "7", "--version", "2.0.0-rc.1"], root), 0)
            self.assertEqual((root / "flutter" / "pubspec.yaml").read_text(encoding="utf-8"), "version: 2.0.0+7\n")
            # CRLF kept; both strings literal, as the packer's (FileVersion X.Y.Z.<run>, ProductVersion our version)
            self.assertEqual(rc.read_bytes().decode("utf-8"), RC_LINES.replace(
                'VALUE "FileVersion", VERSION_AS_STRING', 'VALUE "FileVersion", "2.0.0.7"').replace(
                'VALUE "ProductVersion", VERSION_AS_STRING', 'VALUE "ProductVersion", "2.0.0-rc.1"'))
            with contextlib.redirect_stderr(io.StringIO()):
                # a version of another number or another run never reaches the exe
                self.assertEqual(b.main(["pubspec", "--run", "7", "--version", "2.0.1"], root), 1)
                self.assertEqual(b.main(["pubspec", "--run", "7", "--version", "2.0.0-dev.8"], root), 1)
            with contextlib.redirect_stderr(io.StringIO()):
                self.assertEqual(b.main(["plan", "--profile", "dev", "--builds", "all", "--tag", "v2.0.0", "--run", "7"], root), 1)
                self.assertEqual(b.main(["plan", "--profile", "dev", "--builds", "nope", "--run", "7"], root), 1)

    def test_the_committed_version_is_semver(self):
        self.assertRegex(b.read_base(), r"^\d+\.\d+\.\d+$")


class VersionAccuracyTest(unittest.TestCase):
    """Plan 19: one version (dolphin/version.txt) everywhere, for the customer x64, customer x86 and technician builds."""

    def test_the_inner_flutter_exe_gets_the_packers_strings(self):
        out = b.set_rc_versions(RC_LINES, "2.1.0-rc.1", "2.1.0.412")
        self.assertIn('VALUE "FileVersion", "2.1.0.412" "\\0"\r\n', out)
        self.assertIn('VALUE "ProductVersion", "2.1.0-rc.1" "\\0"\r\n', out)
        self.assertNotIn("VERSION_AS_STRING", out)
        with self.assertRaises(ValueError):
            b.set_rc_versions("no version block", "2.1.0", "2.1.0.1")

    def test_the_real_runner_rc_has_both_lines(self):
        rc = (b.ROOT / "flutter" / "windows" / "runner" / "Runner.rc").read_text(encoding="utf-8", newline="")
        self.assertEqual(len(b.RC_VERSION_LINE.findall(rc)), 2)

    def test_a_job_version_belongs_to_version_txt_and_the_run(self):
        for ok in ("2.1.0", "2.1.0-rc.1", "2.1.0-rc.12", "2.1.0-dev.412"):
            b.check_build_version("2.1.0", 412, ok)
        for bad in ("2.1.1", "2.1.0-rc.0", "2.1.0-dev.411", "2.1.0-beta.1", "v2.1.0", "2.1.0+412", ""):
            with self.assertRaises(ValueError, msg=bad):
                b.check_build_version("2.1.0", 412, bad)

    def test_the_committed_placeholders_carry_version_txt(self):
        # The generated files in git (overwritten in CI) say <version.txt>-dev.0, so a local check or analysis run
        # shows this release line and never an old number.
        base = b.read_base()
        rust = (b.ROOT / "src" / "dolphin_generated.rs").read_text(encoding="utf-8")
        dart = (b.ROOT / "flutter" / "lib" / "dolphin" / "brand.dart").read_text(encoding="utf-8")
        self.assertIn(f'pub const DOLPHIN_VERSION: &str = "{base}-dev.0";', rust)
        self.assertIn(f"static const String version = '{base}-dev.0';", dart)

    def test_the_release_candidate_sorts_between_the_dev_builds_and_the_release(self):
        # What build_plan makes is what the update check orders (src/dolphin_update_core.rs is_newer, same list):
        # 2.1.0-dev.N < 2.1.0-rc.1 < 2.1.0 < 2.1.1-dev.N (version.txt raised after a release) < 2.1.1.
        made = [b.version("2.1.0", "", 9)[0], b.version("2.1.0", "v2.1.0-rc.1", 10)[0], b.version("2.1.0", "v2.1.0", 11)[0],
                b.version("2.1.1", "", 12)[0], b.version("2.1.1", "v2.1.1", 13)[0]]
        self.assertEqual(made, ["2.1.0-dev.9", "2.1.0-rc.1", "2.1.0", "2.1.1-dev.12", "2.1.1"])
        core = (b.ROOT / "src" / "dolphin_update_core.rs").read_text(encoding="utf-8")
        self.assertIn('"2.1.0-dev.9", "2.1.0-rc.1", "2.1.0", "2.1.1-dev.12", "2.1.1"', core)


RC_LINES = (
    'BEGIN\r\n'
    '            VALUE "FileDescription", "RustDesk Remote Desktop" "\\0"\r\n'
    '            VALUE "FileVersion", VERSION_AS_STRING "\\0"\r\n'
    '            VALUE "ProductVersion", VERSION_AS_STRING "\\0"\r\n'
    'END\r\n'
)


if __name__ == "__main__":
    unittest.main()
