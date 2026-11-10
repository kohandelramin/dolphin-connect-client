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

    def test_a_release_puts_the_exes_on_ghcr_for_the_portal(self):
        # Portal ADR-0014: the portal fetches the pinned exes from this package by their SHA-256.
        release = BUILD.split("\n  release:\n", 1)[1]
        self.assertIn("      packages: write\n", release)
        self.assertIn('ORAS_VERSION: "1.3.6"', release)
        self.assertIn("ORAS_SHA256: 66fb0ad7206f3f6fa77ed5b552049d364ccf4b50b1684554f731f76302b52ca0", release)
        self.assertIn("sha256sum -c -", release)
        self.assertIn('repo="ghcr.io/${GITHUB_REPOSITORY_OWNER,,}/dolphin-connect-client-files"', release)
        for exe in ('"DolphinConnect-$v-x64.exe:$type"', '"DolphinConnect-$v-x86.exe:$type"', '"DolphinConnect-Technician-$v-x64.exe:$type"'):
            self.assertIn(exe, release)
        # the pushed digests are compared with the release's SHA256SUMS, so a wrong push fails the job
        self.assertIn("diff -u expected.txt pushed.txt", release)
        # the package push comes after the GitHub release, which stays the public record
        self.assertLess(release.index("- name: Publish release"), release.index("- name: Push the exes to ghcr.io"))

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
        std_only = ("dolphin/version_resource.rs", "src/dolphin_update_core.rs", "libs/portable/src/dolphin_wait.rs",
                    "src/dolphin_portal.rs", "src/dolphin_callback_core.rs", "src/dolphin_fixed_core.rs")
        for path in std_only:
            self.assertIn(f"rustc --edition 2021 --test {path}", CHECK)
        # rust-unit tests exactly these: a new std-only file needs a line in the job and in this tuple
        tested = re.findall(r"rustc --edition 2021 --test (\S+)", job(CHECK, "rust-unit"))
        self.assertEqual(sorted(tested), sorted(std_only))

    def test_every_exe_has_its_version_resource_checked(self):
        self.assertEqual(BUILD.count("name: Version resource (TB-4)"), 2)


class CheckWiringTest(unittest.TestCase):
    def test_a_rustc_compile_error_fails_the_job(self):
        # `rustc ... && run` does not trip errexit when rustc fails (run 40639363014 was green with 20 errors).
        step = job(CHECK, "rust-unit")
        self.assertIsNone(re.search(r"rustc[^\n]*&&", step))
        # Nor may the compile be forgiven (`|| true`) or followed by another command on its line (`; run`).
        self.assertIsNone(re.search(r"rustc[^\n]*\|\|", step))
        self.assertIsNone(re.search(r"rustc[^\n]*;", step))
        for line in re.findall(r"^\s*rustc --edition [^\n]*$", step, re.M):
            self.assertRegex(line, r'-o "\$RUNNER_TEMP/\w+"$')
        self.assertEqual(len(re.findall(r"^\s*rustc --edition ", step, re.M)), 6)
        self.assertEqual(len(re.findall(r'^\s*"\$RUNNER_TEMP/', step, re.M)), 6)

    def test_the_code_stays_hidden_until_the_session_count_is_known(self):
        home = (ROOT / "flutter" / "lib" / "dolphin" / "home.dart").read_text(encoding="utf-8")
        init = home.split("void initState()", 1)[1].split("void dispose()", 1)[0]
        self.assertNotRegex(init, r"(?m)^\s*_readConnected\(\);", "an early read is the unsynced 0")
        self.assertIn("Timer.periodic", init)
        tis = (ROOT / "src" / "ui" / "index.tis").read_text(encoding="utf-8")
        self.assertIn('var password_cache = ["","","","",true];', tis)
        self.assertIn("password_ticks < 3", tis)


class PortalDownWiringTest(unittest.TestCase):
    """D5: nothing but source text proves the Rust writer and the Dart readers still meet (no local toolchain)."""

    KEY = "dolphin-portal-down"

    def read(self, *parts):
        return ROOT.joinpath(*parts).read_text(encoding="utf-8")

    def test_sync_writes_the_option_through_dolphin_portal_when_the_portal_really_answered(self):
        sync = self.read("src", "hbbs_http", "sync.rs")
        self.assertIn("crate::dolphin_portal::portal_down_write(", sync)
        self.assertIn("crate::dolphin_portal::PORTAL_DOWN_OPTION", sync)
        self.assertIn("Ok(s) if crate::dolphin_portal::portal_answered(s)", sync)
        self.assertNotIn("response.is_ok()", sync)  # any HTTP status, a 502 page too, is an Ok

    def test_the_prompt_reads_the_option(self):
        connection = self.read("flutter", "lib", "dolphin", "connection.dart")
        self.assertIn("portalDown: opt(kDolphinPortalDownOption) == 'Y'", connection)
        verify = self.read("flutter", "lib", "dolphin", "verify.dart")
        self.assertRegex(verify, r"const kDolphinPortalDownOption = 'dolphin-portal-down';")
        self.assertIn("portalDown", verify.split("TechVerdict verifyTechnician", 1)[1])

    def test_the_key_is_the_same_in_rust_and_dart(self):
        rust = re.search(r'PORTAL_DOWN_OPTION: &str = "([^"]+)"', self.read("src", "dolphin_portal.rs")).group(1)
        dart = re.search(r"kDolphinPortalDownOption = '([^']+)'", self.read("flutter", "lib", "dolphin", "verify.dart")).group(1)
        self.assertEqual(rust, self.KEY)
        self.assertEqual(dart, self.KEY)

    def test_continue_counts_only_this_process_sessions(self):
        update = self.read("src", "dolphin_update.rs")
        body = update.split("fn can_continue_now()", 1)[1].split("\n}", 1)[0]
        self.assertIn("AUTHED_CONNS", body)
        self.assertNotIn("is_installed", body)


class SharedRustTest(unittest.TestCase):
    """The x86 build is Sciter, without the "flutter" feature, and compiles every Dolphin Rust module too."""

    def test_dolphin_modules_call_no_flutter_only_helper(self):
        # ui_interface::get_id exists only with the flutter feature; 2.0.0-rc.5's first x86 build failed on it.
        for path in sorted((ROOT / "src").glob("dolphin*.rs")):
            self.assertNotIn("ui_interface::get_id()", path.read_text(encoding="utf-8"), path.name)


class FixedPasswordWiringTest(unittest.TestCase):
    """D21: the secret reaches the two app-build steps only, and no build can quietly leave it out."""

    SECRET_ENV = "DOLPHIN_FIXED_PASSWORD: ${{ secrets.DOLPHIN_FIXED_PASSWORD }}"

    def read(self, *parts):
        return ROOT.joinpath(*parts).read_text(encoding="utf-8")

    def test_both_app_builds_get_the_secret_in_their_generation_step_only(self):
        self.assertEqual(BUILD.count("secrets.DOLPHIN_FIXED_PASSWORD"), 2)
        steps = BUILD.split("- name: Dolphin settings, version and branding\n")[1:]
        self.assertEqual(len(steps), 2)  # the x64 job (customer and technician) and the x86 job
        for step in steps:
            step = step.split("\n      - ", 1)[0]
            self.assertIn(self.SECRET_ENV, step)
            self.assertIn("python dolphin/gen_profile.py", step)
        # not in the job-wide env, where every step (and every action) would see it
        for name in ("build-windows", "build-windows-x86"):
            head = job(BUILD, name).split("    steps:\n", 1)[0]
            self.assertNotIn("DOLPHIN_FIXED_PASSWORD", head, name)

    def test_no_app_build_leaves_the_fixed_password_out(self):
        self.assertNotIn("--without-fixed-password", BUILD)

    def test_checks_and_the_analysis_never_see_the_secret(self):
        for text in (CHECK, ANALYZE, BRIDGE):
            self.assertNotIn("DOLPHIN_FIXED_PASSWORD", text)
            self.assertNotIn("secrets: inherit", text)
        self.assertNotIn("secrets: inherit", BUILD)
        gens = re.findall(r"python dolphin/gen_profile\.py[^\n]*", CHECK + ANALYZE)
        self.assertEqual(len(gens), 3)
        for line in gens:
            self.assertTrue(line.endswith("--without-fixed-password"), line)

    def test_the_secret_is_never_printed(self):
        for text in (BUILD, CHECK, ANALYZE):
            self.assertIsNone(re.search(r"(echo|printf|Write-Host|cat)[^\n]*DOLPHIN_FIXED_PASSWORD", text))
        self.assertNotIn("dolphin_fixed_generated.rs", BUILD)  # never uploaded or shown

    def test_the_customer_login_hook_and_the_technician_hook_are_in_place(self):
        conn = self.read("src", "server", "connection.rs")
        login = conn.split("let allow_logon_screen_password =", 1)[1]
        hook = login.index("self.dolphin_fixed_login(&lr.my_id, &lr.password)")
        self.assertLess(hook, login.index("password::approve_mode() == ApproveMode::Click"))
        self.assertIn("crate::client::LOGIN_MSG_PASSWORD_EMPTY", login[hook:hook + 2000])
        self.assertIn("crate::dolphin_fixed::presented(&self.hash.salt, &self.hash.challenge, presented)", conn)
        self.assertIn("crate::dolphin_fixed::gate_now(peer_id)", conn)
        client = self.read("src", "client.rs")
        body = client.split("pub async fn handle_hash(", 1)[1]
        self.assertLess(body.index("crate::dolphin_fixed::technician_password()"), body.index("// peer config password"))
        self.assertIn("PasswordSource::DolphinFixed => true,", client)
        fixed = self.read("src", "dolphin_fixed.rs")
        self.assertIn('include!("dolphin_fixed_generated.rs");', fixed)
        self.assertEqual(fixed.count("std::hint::black_box("), 3)
        self.assertIn("config::is_outgoing_only()", fixed)
        self.assertIn("config::is_incoming_only()", fixed)
        self.assertNotRegex(fixed, r"log::\w+!\([^)]*(value|secret)")

    def test_the_array_names_match_between_generator_and_module(self):
        fixed = self.read("src", "dolphin_fixed.rs")
        gen = self.read("dolphin", "gen_profile.py")
        for name in ("FIXED_MASKED", "FIXED_PAD_A", "FIXED_PAD_B"):
            self.assertIn(f'"{name}"', gen)
            self.assertIn(f"&{name}[..]", fixed)

    def test_the_option_name_is_the_one_the_portal_pushes(self):
        core = self.read("src", "dolphin_fixed_core.rs")
        self.assertIn('pub const FIXED_OPTION: &str = "dolphin-fixed-password";', core)
        tech = re.search(r'TECH_ID_OPTION: &str = "([^"]+)"', core).group(1)
        dart = re.search(r"kDolphinTechIdOption = '([^']+)'", self.read("flutter", "lib", "dolphin", "verify.dart")).group(1)
        self.assertEqual(tech, dart)

    def test_a_dropped_session_can_be_taken_back_for_two_minutes(self):
        conn = self.read("src", "server", "connection.rs")
        self.assertIn("const SESSION_TIMEOUT: Duration = Duration::from_secs(120);", conn)


class QuietReconnectWiringTest(unittest.TestCase):
    """D23: no Flutter here, so the source text proves the hook is in place and CI analyzes the file it touches."""

    def read(self, *parts):
        return ROOT.joinpath(*parts).read_text(encoding="utf-8")

    def test_the_msgbox_handler_retries_quietly_before_anything_else(self):
        model = self.read("flutter", "lib", "models", "model.dart")
        body = model.split("handleMsgBox(Map<String, dynamic> evt", 1)[1]
        hook = body.index("if (_dolphinQuietRetry(type, title, text, dialogManager)) return;")
        self.assertLess(hook, body.index("if (type == 're-input-password')"))
        self.assertIn("technician: bind.isOutgoingOnly(),", model)
        self.assertIn("_dolphinReconnected(); // Dolphin Connect (D23)", model)
        self.assertIn("import 'package:flutter_hbb/dolphin/reconnect.dart';", model)

    def test_ci_analyzes_model_dart_and_tests_the_rules(self):
        self.assertIn("lib/models/model.dart", ANALYZE)
        self.assertTrue((ROOT / "flutter" / "test" / "dolphin" / "reconnect_test.dart").is_file())

    def test_the_customer_window_marks_a_comeback(self):
        conn = self.read("flutter", "lib", "dolphin", "connection.dart")
        self.assertIn("resumed: _resumed,", conn)
        self.assertEqual(conn.count("_lastLive.remove(c.peerId);"), 2)  # «پایان» and «رد» forget it


if __name__ == "__main__":
    unittest.main()
