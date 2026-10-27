import contextlib
import io
import json
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


class PlanTest(unittest.TestCase):
    def test_outputs_are_github_output_values(self):
        out = b.plan("dev", "x64", "")
        self.assertEqual(json.loads(out["x64"]), ["customer", "technician"])
        self.assertEqual(out["x86"], "false")

    def test_a_release_tag_needs_the_production_profile(self):
        with self.assertRaises(ValueError):
            b.plan("dev", "all", "1.5.0-dc.5")

    def test_main_prints_key_value_lines_and_fails_cleanly(self):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            self.assertEqual(b.main(["plan", "--profile", "dev", "--builds", "customer-x86"]), 0)
        self.assertEqual(out.getvalue().splitlines(), ["x64=[]", "x86=true"])
        with contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(b.main(["plan", "--profile", "dev", "--builds", "nope"]), 1)


if __name__ == "__main__":
    unittest.main()
