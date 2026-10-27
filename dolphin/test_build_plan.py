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

    def test_production_always_builds_all_three(self):
        for builds in b.BUILDS:
            self.assertEqual(b.select("production", builds), (["customer", "technician"], True))

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
            out = io.StringIO()
            with contextlib.redirect_stdout(out):
                self.assertEqual(b.main(["plan", "--profile", "dev", "--builds", "customer-x86", "--run", "7"], root), 0)
            self.assertEqual(out.getvalue().splitlines(), ["x64=[]", "x86=true", "version=2.0.0-dev.7", "file_version=2.0.0.7", "prerelease=true"])
            with contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(b.main(["pubspec", "--run", "7"], root), 0)
            self.assertEqual((root / "flutter" / "pubspec.yaml").read_text(encoding="utf-8"), "version: 2.0.0+7\n")
            with contextlib.redirect_stderr(io.StringIO()):
                self.assertEqual(b.main(["plan", "--profile", "dev", "--builds", "all", "--tag", "v2.0.0", "--run", "7"], root), 1)
                self.assertEqual(b.main(["plan", "--profile", "dev", "--builds", "nope", "--run", "7"], root), 1)

    def test_the_committed_version_is_semver(self):
        self.assertRegex(b.read_base(), r"^\d+\.\d+\.\d+$")


if __name__ == "__main__":
    unittest.main()
