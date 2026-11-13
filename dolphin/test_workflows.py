"""Text checks on the Dolphin workflows: cheap guards for rules a YAML edit could silently drop (TB-1)."""
import json
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

def whole_job(text, name):
    """One top-level job with its blank lines (`job` stops at the first blank line, which is enough for its head)."""
    body = text.split(f"\n  {name}:\n", 1)[1]
    m = re.search(r"\n  [a-z0-9-]+:\n", body)
    return body[:m.start()] if m else body



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

    def test_each_build_brands_its_own_variant(self):
        # The technician app gets the blue-tile icon and its own exe name; the x86 build is the customer app only.
        x64 = whole_job(BUILD, "build-windows")
        self.assertIn('python dolphin/gen_profile.py "${{ inputs.profile }}" "${{ matrix.variant }}"', x64)
        self.assertIn('python dolphin/brand.py "${{ matrix.variant }}"\n', x64)
        x86 = whole_job(BUILD, "build-windows-x86")
        self.assertIn('python dolphin/gen_profile.py "${{ inputs.profile }}" customer', x86)
        self.assertIn("python dolphin/brand.py customer\n", x86)
        self.assertEqual(len(re.findall(r"python dolphin/brand\.py", BUILD)), 2)

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
                    "src/dolphin_portal.rs", "src/dolphin_callback_core.rs", "src/dolphin_fixed_core.rs",
                    "src/dolphin_session_core.rs",
                    "src/dolphin_system_core.rs",
                    "src/dolphin_panel_core.rs",
                    "src/dolphin_install_core.rs",
                    "src/dolphin_strategy_core.rs",
                    "src/dolphin_identity_core.rs",
                    "src/dolphin_safe_mode_core.rs",
                    "src/dolphin_wake_core.rs",
                    "src/dolphin_net_core.rs",
                    "src/dolphin_ws_core.rs",
                    "src/dolphin_frame_core.rs",
                    "src/dolphin_demo_core.rs")
        for path in std_only:
            self.assertIn(f"rustc --edition 2021 --test {path}", CHECK)
        # rust-unit tests exactly these: a new std-only file needs a line in the job and in this tuple
        tested = re.findall(r"rustc --edition 2021 --test (\S+)", job(CHECK, "rust-unit"))
        self.assertEqual(sorted(tested), sorted(std_only))

    def test_every_exe_has_its_version_resource_checked(self):
        self.assertEqual(BUILD.count("name: Version resource (TB-4)"), 2)

    def test_the_inner_x64_exe_carries_the_same_version_strings(self):
        # Plan 19: Flutter writes "X.Y.Z+<run>" into both strings unless build_plan.py rewrites Runner.rc.
        self.assertIn('python dolphin/build_plan.py pubspec --run "${{ github.run_number }}" --version "$DOLPHIN_VERSION"', BUILD)
        x64 = whole_job(BUILD, "build-windows")
        step = x64.split("name: Version resource (TB-4)", 1)[1].split("- uses:", 1)[0]
        self.assertIn("$inner.VersionInfo.FileVersion -ne $env:DOLPHIN_FILE_VERSION", step)
        self.assertIn("$inner.VersionInfo.ProductVersion -ne $env:DOLPHIN_VERSION", step)
        self.assertIn("$outer.VersionInfo.ProductVersion -ne $env:DOLPHIN_VERSION", step)

    def test_release_file_names_carry_the_version_for_every_build(self):
        # The portal derives the download names from these (installer and portable names are the portal's).
        self.assertIn('"out/${OUT_NAME}-${DOLPHIN_VERSION}-x64.exe"', BUILD)
        self.assertIn('"out/DolphinConnect-${DOLPHIN_VERSION}-x86.exe"', BUILD)
        self.assertIn('"DolphinConnect-$v-x64.exe" "DolphinConnect-$v-x86.exe" "DolphinConnect-Technician-$v-x64.exe"', BUILD)

    def test_every_app_folder_gets_the_vc_runtime_its_dlls_import_before_packing(self):
        # DD-21: a clean Windows 10 without the VC++ redistributable starts the app.
        for name, folder, arch, pack in (("build-windows", "./rustdesk", "x64", "- name: Portable exe and checksums"),
                                         ("build-windows-x86", "./Release", "x86", "- name: Portable exe and checksum\n")):
            text = whole_job(BUILD, name)
            line = f"run: python dolphin/vcruntime.py bundle {folder} --arch {arch}"
            self.assertEqual(text.count(line), 1, name)
            step = text.index("- name: VC++ runtime next to the app (DD-21)")
            self.assertLess(text.index("- name: Build"), step)
            self.assertLess(step, text.index(pack), "the packer must take the copied DLLs along")
            self.assertNotIn("continue-on-error", text[step:text.index(pack)])
        # upstream's static runtime, which keeps the list short, must stay
        cmake = (ROOT / "flutter" / "windows" / "CMakeLists.txt").read_text(encoding="utf-8")
        self.assertIn('string(REPLACE "/MD" "/MT"', cmake)
        cargo = (ROOT / ".cargo" / "config.toml").read_text(encoding="utf-8")
        self.assertEqual(cargo.count("crt-static"), 3)


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
        self.assertEqual(len(re.findall(r"^\s*rustc --edition ", step, re.M)), 18)
        self.assertEqual(len(re.findall(r'^\s*"\$RUNNER_TEMP/', step, re.M)), 18)

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



class SystemWiringTest(unittest.TestCase):
    """Plan 18 Phase 2 (DD-12, DD-13, DD-34, DD-35, DD-47): the hooks in upstream files, proven by their text, since
    neither the Rust crate nor Flutter is built here."""

    def read(self, *parts):
        return ROOT.joinpath(*parts).read_text(encoding="utf-8")

    def test_stopped_sharing_is_refused_before_the_hash_and_any_login(self):
        conn = self.read("src", "server", "connection.rs")
        body = conn.split("async fn on_open(&mut self, addr: SocketAddr) -> bool {", 1)[1]
        check = body.index("if crate::dolphin_system::sharing_stopped() {")
        self.assertLess(body.index('"The main window is not open"'), check)
        self.assertLess(check, body.index("msg_out.set_hash(self.hash.clone());"))
        self.assertIn("crate::dolphin_system::login_dir(ft.dir)", conn)

    def test_the_heartbeat_reports_sharing(self):
        self.assertIn('v["dolphin_share"] = json!(crate::dolphin_system::heartbeat_share());',
                      self.read("src", "hbbs_http", "sync.rs"))

    def test_the_cm_opens_and_guards_the_receive_folder(self):
        cm = self.read("src", "ui_cm_interface.rs")
        self.assertIn("crate::dolphin_system::cm_home().await", cm)
        self.assertIn("dolphin_read_dir_home().await", cm.split("async fn read_dir(", 1)[1][:300])
        handle = cm.split("async fn handle_fs(", 1)[1]
        self.assertLess(handle.index("crate::dolphin_system::cm_refused_write(&fs).await"), handle.index("match fs {"))

    def test_the_customer_build_gets_its_own_tray(self):
        tray = self.read("src", "tray.rs")
        handoff = tray.index("return crate::dolphin_system::run_customer_tray(rgba, w, h);")
        self.assertLess(tray.index("try_lock_tray_single_instance()"), handoff)

    def test_the_main_window_close_asks_first(self):
        tab = self.read("flutter", "lib", "desktop", "widgets", "tabbar_widget.dart")
        body = tab.split("void onWindowClose() async {", 1)[1]
        hook = body.index("await dolphinHandleMainWindowClose(context)")
        self.assertLess(hook, body.index("await rustDeskWinManager.unregisterActiveWindow(kMainWindowId);"))
        self.assertIn("tabType == DesktopTabType.main", body[:hook])

    def test_the_home_has_the_share_strip_and_errors_are_plain(self):
        self.assertIn("const DolphinShareControl()", self.read("flutter", "lib", "dolphin", "home.dart"))
        common = self.read("flutter", "lib", "common.dart")
        self.assertIn("final plain = dolphinPlainError(text);", common.split("Widget msgboxContent(", 1)[1][:400])
        files = self.read("flutter", "lib", "models", "file_model.dart")
        self.assertIn("dolphinPlainError(err)", files.split("class JobProgress {", 1)[1].split("String display() {", 1)[1][:500])

    def test_ci_analyzes_the_hooked_upstream_files(self):
        for f in ("lib/models/file_model.dart", "lib/common.dart", "lib/desktop/widgets/tabbar_widget.dart"):
            self.assertIn(f, ANALYZE)
        for t in ("presence_test.dart", "share_test.dart", "plain_errors_test.dart", "receive_folder_test.dart"):
            self.assertTrue((ROOT / "flutter" / "test" / "dolphin" / t).is_file(), t)


class ChatFilesWiringTest(unittest.TestCase):
    """Plan 18 Phase 3 (DD-29, DD-30, DD-14, DD-15): the hooks in upstream files, proven by their text, since the apps
    are not built here."""

    def read(self, *parts):
        return ROOT.joinpath(*parts).read_text(encoding="utf-8")

    def test_the_chat_is_right_to_left_with_an_empty_line(self):
        page = self.read("flutter", "lib", "common", "widgets", "chat_page.dart")
        self.assertIn("inputTextDirection: TextDirection.rtl, // Dolphin Connect (DD-29)", page)
        self.assertIn("DolphinChatText(text: message.text, at: message.createdAt)", page)
        self.assertIn("return DolphinChatFrame(", page)
        self.assertIn("empty: messages.isEmpty,", page)
        self.assertIn("chatFollowsIncoming(", self.read("flutter", "lib", "models", "chat_model.dart"))
        conn = self.read("flutter", "lib", "dolphin", "connection.dart")
        self.assertIn("gFFI.chatModel.toggleCMChatPage(MessageKey(c.peerId, c.id))", conn)
    def test_the_technician_hears_refused_or_no_answer(self):
        model = self.read("flutter", "lib", "models", "model.dart")
        body = model.split("handleMsgBox(Map<String, dynamic> evt, SessionID sessionId, String peerId) {", 1)[1]
        hook = body.index("dolphinRequestDenied(")
        self.assertLess(hook, body.index("showMsgBox(sessionId, type, title, text, link, hasRetry, dialogManager);"))
        self.assertIn("text = kDolphinRequestDeniedKey;", body[:2000])
        self.assertIn("if (!isCache) _dolphinWaitingAccept = false;", model.split("handlePeerInfo(Map<String, dynamic> evt", 1)[1][:400])
        dialog = self.read("flutter", "lib", "common", "widgets", "dialog.dart")
        wait = dialog.split("void showWaitAcceptDialog(", 1)[1].split("void showRestartRemoteDevice(", 1)[0]
        self.assertIn("? DolphinWaitAccept()", wait)
        self.assertIn("closeConnection();", wait)  # «لغو» still ends the request as before

    def test_the_panel_says_when_the_sign_in_expired(self):
        view = self.read("flutter", "lib", "dolphin", "portal_view.dart")
        self.assertIn("signInExpiredAt(url, DolphinBrand.portalUrl)", view)
        self.assertIn("_web.executeScript(kNavigationStatusScript)", view)
        self.assertIn("if (_expired) Positioned.fill(child: DolphinSignInExpired(onSignIn: _signInAgain)),", view)
        # The panel still stays on the portal: the redirect home comes first in the address listener.
        listener = view.split("_web.url.listen((url) {", 1)[1]
        self.assertLess(listener.index("if (!isPanelUrl(url, DolphinBrand.portalUrl)) _web.loadUrl(_home);"),
                        listener.index("signInExpiredAt("))

    def test_the_file_window_drops_queues_pins_and_copies(self):
        page = self.read("flutter", "lib", "desktop", "pages", "file_manager_page.dart")
        drop = page.split("void handleDragDone(DropDoneDetails details, bool isLocal) {", 1)[1].split("class FileManagerView extends", 1)[0]
        self.assertIn("final items = SelectedItems(isLocal: true);", drop)
        self.assertIn("model.localController.sendFiles(items, remote);", drop)  # local to remote, as «ارسال»
        self.assertNotIn("remoteController.sendFiles", drop)
        self.assertIn("DolphinDropMask(", page)
        self.assertIn("DolphinJobButtons(", page)
        self.assertIn("jobController.dolphinJobAction(item.id, a)", page)
        self.assertIn("DolphinPinMenu(", page)
        self.assertIn("key: kDolphinPinsKey", page)
        self.assertIn("Clipboard.setData(ClipboardData(text: entry.path));", page)
        files = self.read("flutter", "lib", "models", "file_model.dart")
        send = files.split("Future<void> sendFiles(", 1)[1]
        self.assertLess(send.index("jobController.dolphinTransfers[jobID] = DolphinTransfer("),
                        send.index("bind.sessionSendFiles("))
        self.assertIn("transferFiles(handledFileCount, fileCount)", files)

    def test_ci_analyzes_the_phase_3_hooked_files_and_runs_their_tests(self):
        for f in ("lib/common/widgets/chat_page.dart", "lib/models/chat_model.dart", "lib/common/widgets/dialog.dart",
                  "lib/desktop/pages/file_manager_page.dart"):
            self.assertIn(f, ANALYZE)
        for t in ("chat_test.dart", "file_transfer_test.dart", "request_outcome_test.dart", "signin_expired_test.dart"):
            self.assertTrue((ROOT / "flutter" / "test" / "dolphin" / t).is_file(), t)

class PanelWiringTest(unittest.TestCase):
    """Plan 18 Phase 3 (DD-49, DD-50, DD-51, DD-6): the side pane's hooks in upstream files, proven by their text,
    since neither the Rust crate nor the Windows runner is built here."""

    def read(self, *parts):
        return ROOT.joinpath(*parts).read_text(encoding="utf-8")

    def test_the_customer_pc_handles_our_plugin_requests_as_input(self):
        conn = self.read("src", "server", "connection.rs")
        self.assertIn("self.dolphin_panel_request(&p.id, &p.content);", conn)
        gate = conn.split("async fn dolphin_inbound_allowed(", 1)[1].split("if inbound_allowed(", 1)[0]
        self.assertIn("Some(misc::Union::PluginRequest(_)) => Inbound::Input,", gate)
        body = conn.split("fn dolphin_panel_request(&mut self, id: &str, content: &[u8]) {", 1)[1][:900]
        self.assertIn("if !self.is_authed_remote_conn() || self.view_camera {", body)
        self.assertIn("let input = self.peer_keyboard_enabled();", body)
        self.assertIn("let clipboard = self.clipboard_enabled();", body)
        self.assertIn("std::thread::spawn(move ||", body, "never on the connection's own loop")

    def test_the_technician_sends_them_to_one_session_only(self):
        ffi = self.read("src", "flutter_ffi.rs")
        body = ffi.split("pub fn session_set_common(session_id: SessionID, key: String, value: String) {", 1)[1][:600]
        self.assertIn("sessions::get_session_by_session_id(&session_id)", body)
        self.assertIn("if s.dolphin_panel_request(&key, &value) {", body)
        self.assertIn("pub fn dolphin_panel_request(&self, key: &str, value: &str) -> bool {",
                      self.read("src", "ui_session_interface.rs"))
        lib = self.read("src", "lib.rs")
        self.assertIn("mod dolphin_panel_core;", lib)
        self.assertIn("mod dolphin_panel;", lib)

    def test_remote_windows_can_host_the_pane(self):
        runner = self.read("flutter", "windows", "runner", "flutter_window.cpp")
        created = runner.split("DesktopMultiWindowSetWindowCreatedCallback(", 1)[1].split("});", 1)[0]
        self.assertIn("WebviewWindowsPluginRegisterWithRegistrar(", created)
        page = self.read("flutter", "lib", "desktop", "pages", "remote_page.dart")
        self.assertIn("body: DolphinSessionSide(ffi: _ffi, peerId: widget.id, child: Obx(() {", page)
        model = self.read("flutter", "lib", "models", "model.dart")
        self.assertIn("if (dolphinMsgBoxHook?.call(type, title, text) == true) return;", model)
        shot = model.split("_handleScreenshot(", 2)[2][:400]
        self.assertIn("if (dolphinScreenshotHook?.call(evt) == true) return;", shot)
        self.assertIn("size.width - leftToEdge - rightToEdge - dolphinRightInset;", model)

    def test_the_pane_has_its_tests(self):
        self.assertTrue((ROOT / "flutter" / "test" / "dolphin" / "side_panel_test.dart").is_file())


class InstallWiringTest(unittest.TestCase):
    """Plan 18 Phase 4 (DD-21): the leftover cleanup runs inside upstream's install script, proven by its text."""

    def read(self, *parts):
        return ROOT.joinpath(*parts).read_text(encoding="utf-8")

    def test_the_install_script_removes_old_leftovers_after_the_uninstall_and_before_the_copy(self):
        win = self.read("src", "platform", "windows.rs")
        body = win.split("pub fn install_me(options: &str, path: String, silent: bool, debug: bool)", 1)[1]
        body = body.split("\npub fn ", 1)[0]
        script = body.split('let cmds = format!(', 1)[1]
        self.assertLess(script.index("{uninstall_str}"), script.index("{dolphin_leftovers}"))
        self.assertLess(script.index("{dolphin_leftovers}"), script.index('md \\"{path}\\"'))
        self.assertLess(script.index("{dolphin_leftovers}"), script.index("reg add {subkey} /f\n"))
        self.assertIn("dolphin_leftovers = dolphin_leftover_cleanup(&path, &cur_exe), // Dolphin Connect (DD-21)", body)
        helper = win.split("fn dolphin_leftover_cleanup(target_dir: &str, cur_exe: &str) -> String {", 1)[1].split("\n}\n", 1)[0]
        self.assertIn("rules::leftover_cleanup(&rules::OldInstall {", helper)
        self.assertIn("KEY_READ | flag", helper)  # reads the other view only; deleting is the elevated script's job
        self.assertNotIn("delete_subkey", helper)
        self.assertNotIn("remove_dir", helper)

    def test_the_core_is_a_module_and_tested_in_ci(self):
        self.assertIn("#[cfg(windows)]\nmod dolphin_install_core;", self.read("src", "lib.rs"))
        self.assertIn("rustc --edition 2021 --test src/dolphin_install_core.rs", CHECK)


class UpdateCheckWiringTest(unittest.TestCase):
    """Plan 18 Phase 4 (DD-20): «بررسی نسخه‌ی تازه» reaches the same Rust check and update flow as the start-up."""

    def read(self, *parts):
        return ROOT.joinpath(*parts).read_text(encoding="utf-8")

    def test_the_key_meets_the_rust_check(self):
        ffi = self.read("src", "flutter_ffi.rs")
        body = ffi.split("pub fn main_get_common(key: String) -> String {", 1)[1][:1200]
        self.assertIn('if key == "dolphin-update-recheck" {\n        return crate::dolphin_update::recheck();', body)
        update = self.read("src", "dolphin_update.rs")
        recheck = update.split("pub fn recheck() -> String {", 1)[1].split("\n}\n", 1)[0]
        self.assertIn("CONTINUE.store(false, Ordering::SeqCst);", recheck)
        self.assertIn("check()", recheck)  # the same portal request and rules as at start-up
        for reason in ('open("latest")', 'open("unreachable")', 'open("disabled")'):
            self.assertIn(reason, update)
        dart = self.read("flutter", "lib", "dolphin", "update.dart")
        self.assertIn("bind.mainGetCommon(key: 'dolphin-update-recheck')", dart)
        self.assertIn("DolphinUpdateScreen(\n                  check: check, inApp: true, onClose: close", dart)
        self.assertIn("if (!widget.inApp) windowManager.setPreventClose(true);", dart)

    def test_both_apps_show_it(self):
        self.assertIn("const DolphinUpdateCheckButton(),", self.read("flutter", "lib", "dolphin", "about.dart"))
        self.assertIn("onAbout: () => showDolphinAboutDialog(context), // DD-20",
                      self.read("flutter", "lib", "dolphin", "home.dart"))
        settings = self.read("flutter", "lib", "desktop", "pages", "desktop_setting_page.dart")
        self.assertIn("Widget build(BuildContext context) => const DolphinAbout(); // Dolphin Connect", settings)
        self.assertTrue((ROOT / "flutter" / "test" / "dolphin" / "update_check_test.dart").is_file())


class PauseAuditTest(unittest.TestCase):
    """DD-46: «مکث» and «ادامه» reach the portal's connection audit."""

    def test_the_pause_posts_a_conn_audit(self):
        conn = ROOT.joinpath("src", "server", "connection.rs").read_text(encoding="utf-8")
        body = conn.split("async fn dolphin_set_paused(&mut self, paused: bool) {", 1)[1].split("\n    }\n", 1)[0]
        self.assertIn('self.post_conn_audit(json!({ "action": dc::pause_audit_action(paused) }));', body)
        self.assertLess(body.index("self.dolphin_paused = paused;"), body.index("self.post_conn_audit("))


class TrayIconSizeTest(unittest.TestCase):
    """The customer tray shows the .ico frame drawn for the tray's size, not the 256 px one shrunk by Windows."""

    def test_the_customer_tray_picks_the_frame_for_the_system_size(self):
        tray = ROOT.joinpath("src", "tray.rs").read_text(encoding="utf-8")
        branch = tray.split("if hbb_common::config::is_incoming_only() {", 1)[1].split("}", 1)[0]
        self.assertIn("crate::dolphin_system::tray_icon_rgba(icon)", branch)
        system = ROOT.joinpath("src", "dolphin_system.rs").read_text(encoding="utf-8")
        self.assertIn("SM_CXSMICON", system)
        self.assertIn("rules::ico_frame(", system)


class PrinterWiringTest(unittest.TestCase):
    """Plan 18 Phase 4 (DD-41): upstream's remote printer behind the portal's `remote-printer` switch."""

    def read(self, *parts):
        return ROOT.joinpath(*parts).read_text(encoding="utf-8")

    def test_the_customer_pc_asks_the_switch_before_any_job_leaves(self):
        conn = self.read("src", "server", "connection.rs")
        branch = conn.split("ipc::Data::PrinterData(data) => {", 1)[1].split("_ => {}", 1)[0]
        self.assertIn("crate::dolphin_system_core::SWITCH_REMOTE_PRINTER", branch)
        self.assertLess(branch.index("crate::dolphin_system_core::printer_forward("),
                        branch.index("conn.send_printer_request(data).await;"))
        self.assertIn("conn.send_remote_printing_disallowed().await;", branch)
        core = self.read("src", "dolphin_system_core.rs")
        self.assertIn('pub const SWITCH_REMOTE_PRINTER: &str = "remote-printer";', core)
        self.assertIn("SwitchMode::Hidden => false,", core.split("pub fn printer_forward(", 1)[1][:300])
        # hidden is the default on both sides (owner 2026-11-13)
        self.assertIn("DolphinSwitch.remotePrinter: SwitchMode.hidden,", self.read("flutter", "lib", "dolphin", "switches.dart"))
        self.assertNotIn("remote-printer", core.split("pub fn switch_default(", 1)[1].split("\n}\n", 1)[0])

    def test_sessions_leave_the_printer_service_alone_while_the_switch_is_hidden(self):
        # Upstream subscribes every session to the printer poll; with the switch hidden (the default) nobody may print,
        # so the poll thread is not started at all.
        conn = self.read("src", "server", "connection.rs")
        subs = conn.split("fn try_sub_monitor_services(&mut self)", 1)[1].split("s.add_monitor_connection(", 1)[0]
        self.assertIn("crate::dolphin_system_core::printer_service_wanted(", subs)
        self.assertIn("noperms.push(super::printer_service::NAME);", subs)
        core = self.read("src", "dolphin_system_core.rs")
        self.assertIn("pub fn printer_service_wanted(mode: SwitchMode) -> bool", core)

    def test_the_driver_ships_with_the_customer_app_only_pinned_by_sha256(self):
        text = whole_job(BUILD, "build-windows")
        step = text.split("- name: Remote printer driver (DD-41)\n", 1)[1].split("\n      - name:", 1)[0]
        self.assertIn("if: matrix.variant == 'customer'", step)
        self.assertIn("PRINTER_DRIVER_SHA256: c4cf4d3b48c4d9079b243edc43bb1db03b076282bc259c9f49883e9db20fa8b5", step)
        self.assertIn("PRINTER_ADAPTER_SHA256: e90e5d52c8807b4c6293c78a52479338715e0bf396b1b34802777b8c452e6781", step)
        self.assertEqual(step.count("sha256sum -c -"), 2)
        self.assertLess(step.index("sha256sum -c -"), step.index("zipfile"))
        self.assertIn("./rustdesk/drivers/RustDeskPrinterDriver", step)  # remote_printer's RD_DRIVER_INF_PATH
        self.assertNotIn("continue-on-error", step)
        self.assertNotIn("|| true", step)
        self.assertLess(text.index("- name: Remote printer driver (DD-41)"), text.index("- name: VC++ runtime next to the app (DD-21)"))
        lib = self.read("libs", "remote_printer", "src", "lib.rs")
        self.assertIn('"drivers/RustDeskPrinterDriver/RustDeskPrinterDriver.inf"', lib)

    def test_the_ui_follows_the_switch(self):
        settings = self.read("flutter", "lib", "desktop", "pages", "desktop_setting_page.dart")
        tab = settings.split("static final List<SettingsTabKey> tabKeys = [", 1)[1].split("];", 1)[0]
        self.assertIn("dolphinPrinterTabShown() /* Dolphin Connect (DD-41) */)\n      SettingsTabKey.printer,", tab)
        install = self.read("flutter", "lib", "desktop", "pages", "install_page.dart")
        self.assertIn("if (dolphinInstallWithPrinter(printer.value)) args += ' printer'; // Dolphin Connect (DD-41)", install)
        self.assertNotIn("if (printer.value) args += ' printer';", install)
        about = self.read("flutter", "lib", "dolphin", "about.dart")
        self.assertIn("if (bind.isIncomingOnly()) ...[const SizedBox(height: 10), const DolphinPrinterSection()],", about)
        for f in ("printer_test.dart",):
            self.assertTrue((ROOT / "flutter" / "test" / "dolphin" / f).is_file())


class AppNameWiringTest(unittest.TestCase):
    """Owner 2026-11-13: the technician app's shown name says «کارشناس» (settings.json variants.technician.display-name-*),
    while app-name (install paths, service, pipes, shortcuts) stays. The hooks are proven by their text: neither the
    runner nor the Rust crate is built here."""

    def read(self, *parts):
        return ROOT.joinpath(*parts).read_text(encoding="utf-8")

    def test_flutter_titles_every_window_with_the_shown_name(self):
        common = self.read("flutter", "lib", "common.dart")
        body = common.split("String getWindowName({WindowType? overrideType}) {", 1)[1].split("\n}\n", 1)[0]
        self.assertIn("final name = DolphinBrand.appNameFa;", body)
        self.assertNotIn("mainGetAppNameSync", body)

    def test_the_runner_titles_and_finds_the_main_window_by_the_same_name(self):
        main = self.read("flutter", "windows", "runner", "main.cpp")
        self.assertIn('GetProcAddress(hInstance, "get_dolphin_display_name")', main)
        lookup = main.index("HWND hwnd = ::FindWindowW(getWindowClassName(), display_name.c_str());")
        self.assertLess(main.index('GetProcAddress(hInstance, "get_rustdesk_app_name")'), lookup)
        self.assertLess(lookup, main.index("if (hwnd == NULL) hwnd = ::FindWindowW(getWindowClassName(), app_name.c_str());"))
        self.assertIn("    window_title = display_name; // Dolphin Connect", main)
        self.assertNotIn("window_title = app_name", main)
        flutter = self.read("src", "flutter.rs")
        export = flutter.split('pub unsafe extern "C" fn get_dolphin_display_name(', 1)[1].split("\n}\n", 1)[0]
        self.assertIn("crate::platform::wide_string(crate::dolphin::DISPLAY_NAME_FA)", export)
        self.assertIn("#[no_mangle]\npub unsafe extern \"C\" fn get_dolphin_display_name(", flutter)

    def test_a_link_reaches_the_running_window_by_its_shown_name_first(self):
        core = self.read("src", "core_main.rs")
        self.assertIn("[crate::dolphin::DISPLAY_NAME_FA.to_owned(), crate::get_app_name()].iter().any(|title| {", core)

    def test_settings_apps_shows_the_shown_name_and_app_name_keeps_the_rest(self):
        win = self.read("src", "platform", "windows.rs")
        self.assertIn('reg add {subkey} /f /v DisplayName /t REG_SZ /d \\"{display_name}\\"', win)
        self.assertIn("display_name = crate::dolphin::DISPLAY_NAME_EN,", win)
        self.assertIn('&format!("{app_name}.lnk")', win)  # shortcuts keep app-name

    def test_the_outer_exe_gets_the_variant_name_from_the_workflow(self):
        import json
        settings = json.loads(self.read("dolphin", "settings.json"))
        tech = settings["variants"]["technician"]["display-name-en"]
        cust = settings["brand"]["display-name-en"]
        self.assertIn(f"DOLPHIN_PRODUCT_NAME: ${{{{ matrix.variant == 'technician' && '{tech}' || '{cust}' }}}}",
                      job(BUILD, "build-windows"))
        build = self.read("libs", "portable", "build.rs")
        self.assertIn('std::env::var("DOLPHIN_PRODUCT_NAME").unwrap_or_else(|_| "Dolphin Connect".to_owned())', build)
        self.assertIn('res.set("ProductName", &name)', build)

    def test_the_dart_views_use_the_generated_names(self):
        # Plan 19: the native technician window's header (tech_ui/header.dart) replaced technician_header.dart.
        self.assertIn("Text(DolphinBrand.technicianNameFa,", self.read("flutter", "lib", "dolphin", "tech_ui", "header.dart"))
        self.assertIn("this.name = DolphinBrand.appNameFa", self.read("flutter", "lib", "dolphin", "about.dart"))
        update = self.read("flutter", "lib", "dolphin", "update.dart")
        self.assertEqual(update.count("DolphinBrand.appNameFa"), 2)
        self.assertNotIn("DolphinBrand.nameFa", update)
        self.assertTrue((ROOT / "flutter" / "test" / "dolphin" / "app_name_test.dart").is_file())
        self.assertIn("lib/common.dart", ANALYZE)


class SignedStrategyWiringTest(unittest.TestCase):
    """Plan 18 Phase 5 (DD-24): the heartbeat applies a strategy only when the portal's signature verifies."""

    def read(self, *parts):
        return ROOT.joinpath(*parts).read_text(encoding="utf-8")

    def test_the_strategy_is_checked_before_it_is_applied(self):
        sync = self.read("src", "hbbs_http", "sync.rs")
        block = sync.split('.remove("modified_at")', 1)[1].split("fn heartbeat_url()", 1)[0]
        self.assertIn("crate::dolphin_strategy::accept(&id, rsp_modified_at, &s.config_options)", block)
        self.assertIn("if let (Some(strategy), Some(true)) = (strategy, applied) {", block)
        self.assertLess(block.index("crate::dolphin_strategy::accept("), block.index("handle_config_options(strategy.config_options);"))
        self.assertEqual(sync.count("handle_config_options(strategy.config_options);"), 1)
        # A refused strategy keeps the old version, so the portal sends it again.
        self.assertIn("rsp_modified_at != modified_at && crate::dolphin_strategy::store_version(applied)", block)
        self.assertEqual(sync.count('LocalConfig::set_option("strategy_timestamp"'), 1)

    def test_the_heartbeat_reports_a_refusal(self):
        sync = self.read("src", "hbbs_http", "sync.rs")
        body = sync.split('v["modified_at"] = json!(modified_at);', 1)[1].split("let response = crate::post_request(url.clone()", 1)[0]
        self.assertIn("if let Some(sig) = crate::dolphin_strategy::heartbeat_sig() {", body)
        self.assertIn('v["dolphin_sig"] = json!(sig);', body)
        core = self.read("src", "dolphin_strategy_core.rs")
        self.assertIn('Some("bad")', core.split("pub fn heartbeat_sig(", 1)[1][:200])

    def test_the_key_and_the_signature_option_match_the_portal(self):
        hook = self.read("src", "dolphin_strategy.rs")
        self.assertIn("crate::dolphin::STRATEGY_PUBLIC_KEY", hook)
        self.assertIn("sign::verify_detached(&sig, message, &pk)", hook)
        core = self.read("src", "dolphin_strategy_core.rs")
        self.assertIn('pub const SIGNATURE_OPTION: &str = "dolphin-signature";', core)
        self.assertIn('const VERSION_LINE: &str = "dolphin-strategy-v1";', core)

    def test_the_rust_test_carries_the_portal_vector(self):
        import json
        vector = json.loads(self.read("dolphin", "strategy-signature-vector.json"))
        core = self.read("src", "dolphin_strategy_core.rs")
        self.assertIn(f'const VECTOR_ID: &str = "{vector["id"]}";', core)
        self.assertIn(f'const VECTOR_VERSION: i64 = {vector["version"]};', core)
        self.assertIn(f'const VECTOR_PUBLIC_KEY: &str = "{vector["public_key"]}";', core)
        self.assertIn(f'"{vector["signature"]}"', core)
        canonical = vector["canonical"].replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")
        self.assertIn(f'const VECTOR_CANONICAL: &str = "{canonical}";', core)
        for key, value in vector["options"].items():
            self.assertIn(f'("{key}", "{value}")', core)


class IdentityWiringTest(unittest.TestCase):
    """Plan 18 Phase 5 (DD-5): the installed server restores its ID and key pair on the same hardware."""

    def read(self, *parts):
        return ROOT.joinpath(*parts).read_text(encoding="utf-8")

    def test_the_server_process_restores_before_it_registers(self):
        core_main = self.read("src", "core_main.rs")
        branch = core_main.split('} else if args[0] == "--server" {', 1)[1].split("return None;", 1)[0]
        self.assertIn("#[cfg(windows)]\n            crate::dolphin_identity::start();", branch)
        self.assertLess(branch.index("crate::dolphin_identity::start();"), branch.index("crate::start_server(true, false);"))

    def test_only_the_installed_system_server_touches_the_backup(self):
        hook = self.read("src", "dolphin_identity.rs")
        start = hook.split("pub fn start() {", 1)[1][:400]
        self.assertIn("if !crate::platform::is_installed() || !crate::is_server() || !crate::platform::is_root() {", start)
        self.assertIn("CRYPTPROTECT_LOCAL_MACHINE", hook)
        self.assertIn('const SDDL: &str = "D:P(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)";', hook)
        self.assertIn("owned_by_system_or_admins(&path)", hook.split("fn read_backup(", 1)[1][:500])
        # No MachineGuid: a cloned disk copies it.
        self.assertNotIn("MachineGuid", hook.replace("not Windows' MachineGuid", ""))
        self.assertIn('u32::from_be_bytes(*b"RSMB")', hook)

    def test_hbb_common_is_used_through_its_public_api_only(self):
        hook = self.read("src", "dolphin_identity.rs")
        for call in ("Config::get()", "Config::set(cfg)", "Config::update_id()", "Config::get_cached_pk()"):
            self.assertIn(call, hook)
        self.assertNotIn("libs/hbb_common", hook.replace("`libs/hbb_common` stays upstream's", ""))

    def test_no_key_bytes_reach_a_log(self):
        hook = self.read("src", "dolphin_identity.rs")
        for line in hook.splitlines():
            if "log::" in line:
                self.assertNotRegex(line, r"\bsk\b|\.pk\b|sealed|plain|key_pair", line)
        self.assertIn("finish_non_exhaustive()", self.read("src", "dolphin_identity_core.rs"))


# The portal's FEATURE_SWITCHES (app/src/lib/switches.ts in the portal repo, DD-4): key -> (which app, default). Keep in
# step with the portal: a new key there needs a line here, its default in both apps, and a reader or a reason below.
PORTAL_SWITCHES = {
    "direct-route": ("both", "forced"),
    "share-toggle": ("customer", "available"),
    "stay-in-tray": ("customer", "available"),
    "receive-folder": ("both", "available"),
    "diagnostics-upload": ("customer", "available"),
    "remote-printer": ("both", "hidden"),
    "wake-on-lan": ("both", "hidden"),
    "safe-mode": ("technician", "hidden"),
    # Plan 18 Phase 6 (DD-31): the portal adds this key with the apps that read it (filed under the technician, whose
    # toolbar shows the button; enforced by the customer PC, as safe-mode).
    "remote-sound": ("technician", "available"),
    # Plan 19 (RO-4, RO-5): customer side, off unless an organization asks; enforced by the customer PC.
    "one-way-transfer": ("customer", "hidden"),
    "lock-on-end": ("customer", "hidden"),
}
# Keys with no reader in the customer app yet, and why.
SWITCHES_NOT_READ = {}


class FeatureSwitchesTest(unittest.TestCase):
    """Plan 18 Phase 5 (DD-4): every switch the portal pushes is known to the apps, with the portal's default, and read
    by the customer app where it applies. The technician app never runs the heartbeat (upstream's start_all stops an
    outgoing-only app before hbbs_http::sync::start), so it has no pushed switches and uses these defaults."""

    def read(self, *parts):
        return ROOT.joinpath(*parts).read_text(encoding="utf-8")

    def dart_defaults(self):
        dart = self.read("flutter", "lib", "dolphin", "switches.dart")
        names = dict(re.findall(r"static const (\w+) = '([^']+)';", dart))
        table = dart.split("const Map<String, SwitchMode> kSwitchDefaults = {", 1)[1].split("};", 1)[0]
        return {names[n]: mode for n, mode in re.findall(r"DolphinSwitch\.(\w+): SwitchMode\.(\w+),", table)}

    def test_the_dart_defaults_are_the_portal_defaults(self):
        self.assertEqual(self.dart_defaults(), {k: d for k, (_, d) in PORTAL_SWITCHES.items()})

    def test_the_rust_defaults_are_the_portal_defaults(self):
        core = self.read("src", "dolphin_system_core.rs")
        consts = dict(re.findall(r'pub const (SWITCH_\w+): &str = "([^"]+)";', core))
        body = core.split("pub fn switch_default(key: &str) -> SwitchMode {", 1)[1].split("\n}\n", 1)[0]
        arms = {}
        for pattern, mode in re.findall(r"\n        ([^\n]+?) => (?:\{\s*)?SwitchMode::(\w+)", body):
            for name in pattern.split("|"):
                name = name.strip()
                if name != "_":
                    arms[consts.get(name, name.strip('"'))] = mode.lower()
        self.assertIn("_ => SwitchMode::Hidden,", body)
        expected = {k: d for k, (_, d) in PORTAL_SWITCHES.items() if d != "hidden"}
        self.assertEqual(arms, expected)

    def test_each_customer_switch_has_a_reader(self):
        readers = {
            "share-toggle": [("flutter/lib/dolphin/share.dart", "mode(DolphinSwitch.shareToggle)"),
                             ("src/dolphin_system.rs", "rules::SWITCH_SHARE_TOGGLE")],
            "stay-in-tray": [("flutter/lib/dolphin/presence.dart", "mode(DolphinSwitch.stayInTray)")],
            "receive-folder": [("src/dolphin_system.rs", "rules::SWITCH_RECEIVE_FOLDER")],
            "diagnostics-upload": [("flutter/lib/dolphin/home.dart", "mode(DolphinSwitch.diagnosticsUpload)")],
            "remote-printer": [("src/server/connection.rs", "crate::dolphin_system_core::SWITCH_REMOTE_PRINTER"),
                               ("flutter/lib/dolphin/printer_hooks.dart", "mode(DolphinSwitch.remotePrinter)")],
            "wake-on-lan": [("src/dolphin_wake.rs", "rules::SWITCH_WAKE_ON_LAN")],
            "direct-route": [("src/dolphin_net.rs", "net::SWITCH_DIRECT_ROUTE) != sys::SwitchMode::Hidden")],
            "one-way-transfer": [("src/common.rs", "crate::dolphin_system_core::builtin_override(")],
            "lock-on-end": [("src/server/connection.rs", "crate::dolphin_system_core::lock_at_end_by(")],
        }
        customer = {k for k, (side, _) in PORTAL_SWITCHES.items() if side in ("customer", "both")}
        self.assertEqual(set(readers) | (customer & set(SWITCHES_NOT_READ)), customer)
        for key, places in readers.items():
            for path, snippet in places:
                self.assertIn(snippet, self.read(*path.split("/")), key)

    def test_the_safe_mode_switch_is_enforced_on_the_customer_pc(self):
        # The portal files it under the technician, but the technician app has no heartbeat (below): the customer app,
        # which has its organization's switches, offers it on login and refuses a request while it is hidden (DD-11).
        self.assertIn("rules::SWITCH_SAFE_MODE", self.read("src", "dolphin_safe_mode.rs"))

    def test_the_technician_app_has_no_heartbeat_so_it_keeps_the_defaults(self):
        rv = self.read("src", "rendezvous_mediator.rs")
        start = rv.split("pub async fn start_all() {", 1)[1]
        self.assertLess(start.index("if config::is_outgoing_only() {"), start.index("crate::hbbs_http::sync::start();"))


class WebSocketFallbackWiringTest(unittest.TestCase):
    """Plan 18 Phase 6 (DD-42): WebSocket over 443 only when the normal ports fail; the hooks in upstream files,
    proven by their text. libs/hbb_common stays upstream's: the fallback only switches upstream's own option in memory."""

    def read(self, *parts):
        return ROOT.joinpath(*parts).read_text(encoding="utf-8")

    def test_the_core_is_a_module_and_tested_in_ci(self):
        lib = self.read("src", "lib.rs")
        self.assertIn("\nmod dolphin_ws_core;\nmod dolphin_ws;\n", lib)
        self.assertIn("rustc --edition 2021 --test src/dolphin_ws_core.rs", CHECK)

    def test_the_customer_pc_falls_back_only_after_lost_udp_registrations(self):
        rv = self.read("src", "rendezvous_mediator.rs")
        udp = rv.split("pub async fn start_udp(", 1)[1].split("pub async fn start_tcp(", 1)[0]
        hook = udp.index("if crate::dolphin_ws::udp_timed_out(fails, &rz.host) {")
        self.assertLess(udp.index("fails += 1;"), hook)
        self.assertIn("Self::restart();\n                                break;", udp[hook:hook + 200])
        # upstream picks TCP (over WebSocket) from its own option, unchanged
        start = rv.split("pub async fn start(server: ServerPtr, host: String)", 1)[1][:600]
        self.assertIn("|| use_ws()", start)

    def test_a_websocket_failure_goes_back_to_the_normal_ports(self):
        rv = self.read("src", "rendezvous_mediator.rs")
        branch = rv.split("if let Err(err) = Self::start(server, host).await {", 1)[1][:400]
        self.assertIn("crate::dolphin_ws::mediator_failed();", branch)
        start_all = rv.split("pub async fn start_all() {", 1)[1].split("\n    }\n", 1)[0]
        # the return watch starts after the outgoing-only (technician) app has stopped
        self.assertLess(start_all.index("if config::is_outgoing_only() {"),
                        start_all.index("crate::dolphin_ws::start_return_watch();"))

    def test_the_technician_retries_once_over_websocket_only_when_hbbs_is_unreachable(self):
        client = self.read("src", "client.rs")
        start = client.split("    pub async fn start(\n", 1)[1].split("    async fn _start(\n", 1)[0]
        self.assertEqual(start.count("Self::_start(peer, key, token, conn_type, interface.clone()).await"), 2)
        retry = start.index("if res.is_err() && crate::dolphin_ws::retry_over_ws(started) {")
        self.assertLess(start.index("let started = crate::dolphin_ws::before_connect();"), retry)
        self.assertIn("interface.get_lch().write().unwrap().force_relay = true;", start[retry:retry + 200])
        inner = client.split("    async fn _start_inner(\n", 1)[1]
        self.assertLess(inner.index("crate::dolphin_ws::note_connect(&socket);"), inner.index("let mut socket = socket?;"))

    def test_the_fallback_is_never_stored_or_told_to_another_process(self):
        glue = self.read("src", "dolphin_ws.rs")
        self.assertIn("DEFAULT_SETTINGS.write()", glue)
        for stored in ("Config::set_option(", "Config::set_options(", "OVERWRITE_SETTINGS", "LocalConfig::set_option("):
            self.assertNotIn(stored, glue)
        ipc = self.read("src", "ipc.rs")
        options = ipc.split("Data::Options(value) => match value {", 1)[1][:400]
        self.assertIn("crate::dolphin_ws::hide_from_ipc(&mut v);", options)
        self.assertLess(options.index("hide_from_ipc"), options.index("stream.send(&Data::Options(Some(v)))"))
        socks = ipc.split("Data::SocksWs(s) => match s {", 1)[1][:600]
        self.assertIn("crate::dolphin_ws::told_option()", socks)
        self.assertNotIn("Config::get_option(OPTION_ALLOW_WEBSOCKET)", socks)

    def test_only_a_server_name_over_https_falls_back(self):
        core = self.read("src", "dolphin_ws_core.rs")
        self.assertIn('pub const OPTION: &str = "allow-websocket";', core)
        self.assertIn('api_server.starts_with("https://")', core)
        profile = json.loads(self.read("dolphin", "profiles", "production.json"))
        self.assertFalse(re.fullmatch(r"[0-9.]+(:\d+)?", profile["custom-rendezvous-server"]))
        self.assertTrue(profile["api-server"].startswith("https://"))

    def test_no_insecure_tls_fallback_is_turned_on(self):
        # upstream accepts an invalid certificate on WebSocket only with this option; the build locks it off ("N",
        # RustDesk options review 2026-11-14), and allow-websocket stays unset (DD-42 switches it on in memory only)
        import json
        override = json.loads(self.read("dolphin", "settings.json"))["override"]
        self.assertEqual(override.get("allow-insecure-tls-fallback"), "N")
        self.assertNotIn("allow-websocket", self.read("dolphin", "settings.json"))


class SoundWiringTest(unittest.TestCase):
    """Plan 18 Phase 6 (DD-31): «صدای رایانه‌ی مشتری», off at the start of every session, the organization's
    `remote-sound` switch enforced on the customer PC."""

    def read(self, *parts):
        return ROOT.joinpath(*parts).read_text(encoding="utf-8")

    def test_the_customer_pc_sends_no_sound_while_the_switch_is_hidden(self):
        conn = self.read("src", "server", "connection.rs")
        gate = conn.split("fn audio_enabled(&self) -> bool {", 1)[1].split("\n    }\n", 1)[0]
        self.assertIn("crate::dolphin_system_core::sound_offered_by(", gate)
        self.assertIn("crate::dolphin_system_core::SWITCHES_OPTION", gate)
        # every subscription to the audio service asks audio_enabled(), at login and on each change
        subs = conn.split("fn try_sub_monitor_services(&mut self)", 1)[1].split("s.add_monitor_connection(", 1)[0]
        self.assertIn("if !self.audio_enabled() {\n                    noperms.push(super::audio_service::NAME);", subs)

    def test_the_customer_pc_tells_the_technician_at_login(self):
        conn = self.read("src", "server", "connection.rs")
        self.assertIn("crate::dolphin_system_core::PLATFORM_SOUND_OFFERED.into(),", conn)
        core = self.read("src", "dolphin_system_core.rs")
        self.assertIn('pub const PLATFORM_SOUND_OFFERED: &str = "dolphin_sound_offered";', core)
        self.assertIn('pub const SWITCH_REMOTE_SOUND: &str = "remote-sound";', core)
        self.assertIn("const kDolphinSoundOffered = 'dolphin_sound_offered';", self.read("flutter", "lib", "dolphin", "sound.dart"))

    def test_every_session_starts_with_the_sound_off(self):
        client = self.read("src", "client.rs")
        init = client.split("    pub fn initialize(\n", 1)[1].split("\n    }\n", 1)[0]
        hook = init.index("crate::dolphin_system_core::session_starts_muted(conn_type == ConnType::DEFAULT_CONN)")
        self.assertLess(init.index("self.config = config;"), hook)
        self.assertIn("self.config.disable_audio.v = true;", init[hook:hook + 200])

    def test_the_toolbar_button_toggles_upstreams_session_option(self):
        hook = self.read("flutter", "lib", "dolphin", "session_toolbar_hook.dart")
        self.assertIn("sound: _sound,", hook)
        self.assertIn("bind.sessionToggleOption(sessionId: ffi.sessionId, value: kDolphinSoundToggle)", hook)
        self.assertIn("const kDolphinSoundToggle = 'disable-audio';", self.read("flutter", "lib", "dolphin", "sound.dart"))


class SafeModeWiringTest(unittest.TestCase):
    """Plan 18 Phase 5 (DD-11): the Safe Mode restart's hooks in upstream files, proven by their text."""

    def read(self, *parts):
        return ROOT.joinpath(*parts).read_text(encoding="utf-8")

    def core_const(self, name):
        return re.search(rf'pub const {name}: &str = "([^"]+)";', self.read("src", "dolphin_safe_mode_core.rs")).group(1)

    def test_never_upstreams_remote_restart(self):
        settings = self.read("dolphin", "settings.json")
        self.assertIn('"enable-remote-restart": "N",', settings.split('"override"', 1)[1])
        conn = self.read("src", "server", "connection.rs")
        body = conn.split("async fn dolphin_safe_mode_request(&mut self, content: &[u8]) {", 1)[1].split("\n    }\n", 1)[0]
        self.assertNotIn("self.restart", body)
        for name in ("dolphin_restart_tick", "dolphin_restart_cancel"):
            fn = conn.split(f"async fn {name}(&mut self) {{", 1)[1].split("\n    }\n", 1)[0]
            self.assertNotIn("self.restart", fn)
            self.assertNotIn("RestartRemoteDevice", fn)
        upstream = conn.split("Some(misc::Union::RestartRemoteDevice(_)) => {", 1)[1][:200]
        self.assertIn("if self.restart {", upstream)

    def test_the_request_rides_on_plugin_request_and_is_control_during_a_pause(self):
        conn = self.read("src", "server", "connection.rs")
        arm = conn.split("Some(misc::Union::PluginRequest(p)) => {", 1)[1][:500]
        self.assertIn("if crate::dolphin_safe_mode_core::is_request(&p.id) {", arm)
        self.assertIn("self.dolphin_safe_mode_request(&p.content).await;", arm)
        self.assertIn("self.dolphin_panel_request(&p.id, &p.content);", arm)
        gate = conn.split("async fn dolphin_inbound_allowed(", 1)[1].split("if inbound_allowed(", 1)[0]
        control = gate.index("Some(misc::Union::PluginRequest(p)) if crate::dolphin_safe_mode_core::is_request(&p.id) =>")
        self.assertLess(control, gate.index("Some(misc::Union::PluginRequest(_)) => Inbound::Input,"))
        session = self.read("src", "ui_session_interface.rs")
        self.assertIn(".or_else(|| crate::dolphin_safe_mode_core::client_request(key, value))", session)

    def test_the_customer_is_asked_first_and_the_audit_comes_after_the_steps(self):
        conn = self.read("src", "server", "connection.rs")
        req = conn.split("async fn dolphin_safe_mode_request(&mut self, content: &[u8]) {", 1)[1].split("\n    }\n", 1)[0]
        self.assertIn("if !self.is_authed_remote_conn() || self.view_camera {", req)
        self.assertIn("rules::decide(kind, &scene)", req)
        self.assertIn("name: kind.cm_notice().to_owned(),", req)
        tick = conn.split("async fn dolphin_restart_tick(&mut self) {", 1)[1].split("\n    }\n", 1)[0]
        self.assertIn("if !rules::due(started, crate::dolphin_session_core::mono_ms()) {", tick)
        prepare = tick.index("crate::dolphin_safe_mode::prepare(kind)")
        audit = tick.index('self.post_conn_audit(json!({ "action": kind.audit_action() }));')
        reboot = tick.index("crate::dolphin_safe_mode::reboot_later(kind,")
        self.assertLess(prepare, audit)
        self.assertLess(audit, reboot)
        timer = conn.split("_ = second_timer.tick() => {", 1)[1][:1200]
        self.assertIn("conn.dolphin_restart_tick().await;", timer)
        perm = conn.split("ipc::Data::SwitchPermission{name, enabled} => {", 1)[1][:500]
        self.assertIn("if &name == crate::dolphin_safe_mode_core::CM_CANCEL {", perm)
        self.assertIn("conn.dolphin_restart_cancel().await;", perm)

    def test_the_login_tells_the_technician_what_the_pc_offers(self):
        conn = self.read("src", "server", "connection.rs")
        self.assertIn("crate::dolphin_safe_mode_core::PLATFORM_ADDITION.into(),", conn)
        self.assertIn("crate::dolphin_safe_mode_core::PLATFORM_OFFERED.into(),", conn)

    def test_the_cm_window_shows_the_notice(self):
        cm = self.read("src", "ui_cm_interface.rs")
        self.assertIn("pub dolphin_restart: String,", cm)
        self.assertIn("if let Some(kind) = crate::dolphin_safe_mode_core::Kind::from_cm_notice(&name) {", cm)
        self.assertIn("if name == crate::dolphin_safe_mode_core::CM_CANCEL {", cm)
        model = self.read("flutter", "lib", "models", "server_model.dart")
        self.assertIn("dolphinRestart = json['dolphin_restart'] ?? '';", model)

    def test_the_service_cleans_up_at_start_and_the_window_asks_over_the_ipc(self):
        win = self.read("src", "platform", "windows.rs")
        svc = win.split("async fn run_service(", 1)[1]
        self.assertLess(svc.index("status_handle.set_service_status(next_status)?;"),
                        svc.index("crate::dolphin_safe_mode::on_service_start();"))
        ipc = self.read("src", "ipc.rs")
        opts = ipc.split("Data::Options(value) => match value {", 1)[1].split("Data::NatType(_)", 1)[0]
        self.assertLess(opts.index("crate::dolphin_safe_mode::ipc_take_return(&mut value);"),
                        opts.index("Config::set_options(value);"))
        ffi = self.read("src", "flutter_ffi.rs")
        self.assertIn('if key == "dolphin-safe-mode" {', ffi)
        self.assertIn('if key == "dolphin-normal-restart" {', ffi)
        lib = self.read("src", "lib.rs")
        for m in ("dolphin_safe_mode_core", "dolphin_safe_mode", "dolphin_wake_core", "dolphin_wake"):
            self.assertIn(f"\nmod {m};", lib)

    def test_the_names_match_between_rust_and_dart(self):
        dart = self.read("flutter", "lib", "dolphin", "safe_mode.dart")
        self.assertIn(f"const kDolphinSafeModeKey = '{self.core_const('REQUEST_ID')}';", dart)
        self.assertEqual(self.core_const("REQUEST_ID"), self.core_const("ANSWER_MSGTYPE"))
        self.assertIn(f"const kDolphinRestartCancel = '{self.core_const('CM_CANCEL')}';", dart)
        self.assertIn(f"const kDolphinSafeModeAddition = '{self.core_const('PLATFORM_ADDITION')}';", dart)
        self.assertIn(f"const kDolphinSafeModeOffered = '{self.core_const('PLATFORM_OFFERED')}';", dart)
        self.assertIn("pub const NOTICE_SECS: u64 = 20;", self.read("src", "dolphin_safe_mode_core.rs"))
        self.assertIn("const kDolphinRestartSecs = 20;", dart)
        self.assertEqual(self.core_const("SWITCH_SAFE_MODE"), "safe-mode")
        self.assertIn("static const safeMode = 'safe-mode';", self.read("flutter", "lib", "dolphin", "switches.dart"))
        self.assertTrue((ROOT / "flutter" / "test" / "dolphin" / "safe_mode_test.dart").is_file())


class WakeWiringTest(unittest.TestCase):
    """Plan 18 Phase 5 (DD-10): Wake-on-LAN in the heartbeat loop (src/hbbs_http/sync.rs)."""

    def read(self, *parts):
        return ROOT.joinpath(*parts).read_text(encoding="utf-8")

    def test_sysinfo_carries_the_adapters(self):
        sync = self.read("src", "hbbs_http", "sync.rs")
        upload = sync.split("if need_upload {", 1)[1].split("let v = v.to_string();", 1)[0]
        self.assertIn("crate::dolphin_wake::add_sysinfo(&mut v);", upload)

    def test_the_heartbeat_reports_the_nonce_until_answered(self):
        sync = self.read("src", "hbbs_http", "sync.rs")
        share = sync.index('v["dolphin_share"]')
        tick = sync.index("crate::dolphin_wake::tick();")
        report = sync.index("v[crate::dolphin_wake_core::HEARTBEAT_FIELD] = json!(nonce);")
        post = sync.index("let response = crate::post_request(url.clone(), v.to_string(), \"\").await;")
        answered = sync.index("crate::dolphin_wake::heartbeat_answered(")
        self.assertLess(share, tick)
        self.assertLess(tick, report)
        self.assertLess(report, post)
        self.assertLess(post, answered)
        self.assertIn("crate::dolphin_portal::portal_answered(s)", sync[answered:answered + 200])

    def test_the_request_is_read_from_the_applied_options_only(self):
        wake = self.read("src", "dolphin_wake.rs")
        self.assertIn("Config::get_option(rules::WAKE_OPTION)", wake)
        self.assertIn("rules::SWITCH_WAKE_ON_LAN) == sys::SwitchMode::Hidden", wake)
        self.assertNotIn("post_request", wake)

    def test_the_names_are_the_contracts(self):
        core = self.read("src", "dolphin_wake_core.rs")
        for const, value in (("WAKE_OPTION", "dolphin-wake"), ("SWITCH_WAKE_ON_LAN", "wake-on-lan"),
                             ("HEARTBEAT_FIELD", "dolphin_wake"), ("SYSINFO_MACS", "dolphin_macs"),
                             ("SYSINFO_LAN", "dolphin_lan")):
            self.assertIn(f'pub const {const}: &str = "{value}";', core)
        self.assertIn("pub const PORT: u16 = 9;", core)
        self.assertIn("static const wakeOnLan = 'wake-on-lan';", self.read("flutter", "lib", "dolphin", "switches.dart"))


class NetWiringTest(unittest.TestCase):
    """Plan 18 Phase 6 (DD-1): the network-change listener and the physical adapter, hooked in upstream files and
    proven by their text, since the crate needs vcpkg and Windows to build. libs/hbb_common stays upstream's."""

    def read(self, *parts):
        return ROOT.joinpath(*parts).read_text(encoding="utf-8")

    def production(self, *parts):
        return self.read(*parts).split("#[cfg(test)]\nmod tests", 1)[0]

    def test_the_mediator_takes_its_sockets_from_dolphin_net(self):
        rv = self.production("src", "rendezvous_mediator.rs")
        self.assertIn("use crate::dolphin_net::{connect_tcp, new_direct_udp_for, new_udp_for};", rv)
        self.assertIn("socket_client::is_ipv4,", rv)
        for call in ("socket_client::connect_tcp", "socket_client::new_udp_for", "socket_client::rebind_udp_for",
                     "socket_client::new_direct_udp_for", "socket_client::{self"):
            self.assertNotIn(call, rv)
        self.assertIn("crate::dolphin_net::rebind_udp_for(&rz.host).await?", rv)
        self.assertEqual(rv.count("crate::dolphin_net::connect_tcp_local(peer_addr, Some(local_addr), "), 2)
        # upstream's own tests still call upstream's socket directly, on loopback
        self.assertIn("#[cfg(test)]\nuse hbb_common::socket_client;", rv)

    def test_the_mediator_registers_again_on_a_change_only_where_it_runs(self):
        start = self.read("src", "rendezvous_mediator.rs").split("pub async fn start_all() {", 1)[1]
        outgoing = start.index("if config::is_outgoing_only() {")
        hook = start.index("crate::dolphin_net::mediator_started();")
        self.assertLess(outgoing, hook)
        self.assertLess(hook, start.index("crate::hbbs_http::sync::start();"))
        net = self.read("src", "dolphin_net.rs")
        react = net.split("fn react() {", 1)[1].split("\n}\n", 1)[0]
        self.assertIn("if enabled && MEDIATOR.load(Ordering::SeqCst) {", react)
        self.assertIn("crate::RendezvousMediator::restart();", react)
        self.assertIn("crate::test_nat_type();", react)

    def test_the_relay_nat_test_and_http_fallback_are_pinned(self):
        server = self.read("src", "server.rs").split("async fn create_relay_connection_(", 1)[1][:800]
        self.assertIn("crate::dolphin_net::connect_tcp(", server)
        common = self.read("src", "common.rs")
        nat = common.split("async fn test_nat_type_() -> ResultType<bool> {", 1)[1][:1500]
        self.assertIn("crate::dolphin_net::connect_tcp_local(server, local_addr, CONNECT_TIMEOUT)", nat)
        self.assertNotIn("socket_client::connect_tcp", nat)
        self.assertIn("crate::dolphin_net::connect_tcp(&*tcp_addr, CONNECT_TIMEOUT)", common)

    def test_the_technician_takes_its_sockets_from_dolphin_net(self):
        client = self.read("src", "client.rs")
        head = client.split("pub use super::lang::*;", 1)[0]
        self.assertIn("use crate::dolphin_net::{connect_tcp, connect_tcp_local, new_direct_udp_for_unverified};", head)
        self.assertIn("socket_client::ipv4_to_ipv6,", head)
        self.assertNotIn("socket_client::{connect_tcp", head)

    def test_a_session_whose_address_went_reconnects_at_once(self):
        io = self.read("src", "client", "io_loop.rs")
        seen = io.index("let mut dolphin_net_seen = crate::dolphin_net::generation();")
        loop = io.index("loop {", seen)
        check = io.index("if crate::dolphin_net::session_path_gone(peer.local_addr(), &mut dolphin_net_seen) {")
        self.assertLess(seen, loop)
        self.assertLess(loop, check)
        self.assertIn('self.handler.msgbox("error", "Connection Error", "Reset by the peer", "");\n',
                      io[check:check + 300])
        # the quiet retry takes it (ADR-0015): a Connection Error whose text is not one of the ends never retried
        dart = self.read("flutter", "lib", "dolphin", "reconnect.dart")
        ends = re.findall(r"^  '([^']+)',", dart.split("const _notTransient = [", 1)[1].split("];", 1)[0], re.M)
        self.assertTrue(ends)
        self.assertFalse([e for e in ends if e in "reset by the peer"])

    def test_the_switch_turns_both_parts_off(self):
        net = self.read("src", "dolphin_net.rs")
        pinning = net.split("fn pinning() -> Option<net::Choices> {", 1)[1].split("\n}\n", 1)[0]
        self.assertIn("if !on() ||", pinning)
        gone = net.split("pub fn session_path_gone(", 1)[1].split("\n}\n", 1)[0]
        self.assertIn("if !on() {", gone)
        core = self.read("src", "dolphin_net_core.rs")
        self.assertEqual(core.count('pub const SWITCH_DIRECT_ROUTE: &str = "direct-route";'), 1)
        self.assertIn('"direct-route" => SwitchMode::Forced,', self.read("src", "dolphin_system_core.rs"))
        switches = self.read("flutter", "lib", "dolphin", "switches.dart")
        self.assertIn("DolphinSwitch.directRoute: SwitchMode.forced,", switches)

    def test_the_option_and_the_notifications(self):
        net = self.read("src", "dolphin_net.rs")
        for name in ("NotifyRouteChange2(AF_UNSPEC", "NotifyUnicastIpAddressChange(AF_UNSPEC", "GetIpForwardTable2",
                     "GetUnicastIpAddressTable", "GetIfTable2", "IP_UNICAST_IF", "IPV6_UNICAST_IF",
                     "net::unicast_if_value(index, v6)"):
            self.assertIn(name, net)
        cargo = self.read("Cargo.toml")
        for feature in ("Win32_NetworkManagement_IpHelper", "Win32_NetworkManagement_Ndis", "Win32_Networking_WinSock"):
            self.assertIn(f'"{feature}",', cargo)

    def test_no_speed_setting_is_touched(self):
        # Approved scope only: no codec, quality or relay/punch timing (DD-2 and DD-3 wait for the owner's numbers).
        net = self.read("src", "dolphin_net.rs")
        self.assertIsNone(re.search(r"codec|quality|PUNCH_|SEC30|CONNECT_TIMEOUT|keep_alive|REG_INTERVAL", net, re.I))
        self.assertNotIn("libs/hbb_common", net.replace("`libs/hbb_common` stays upstream's", ""))


class DemoWiringTest(unittest.TestCase):
    """Plan 19 (D1–D2): «ارائه دمو». Its hooks in upstream files, proven by their text; the rules are tested in
    src/dolphin_demo_core.rs and flutter/test/dolphin/demo_test.dart."""

    def read(self, *parts):
        return ROOT.joinpath(*parts).read_text(encoding="utf-8")

    def core_const(self, name):
        return re.search(rf'pub const {name}: &str = "([^"]+)";', self.read("src", "dolphin_demo_core.rs")).group(1)

    def dart_const(self, name):
        return re.search(rf"const {name} = '([^']+)';", self.read("flutter", "lib", "dolphin", "demo.dart")).group(1)

    def test_the_core_is_a_module_and_tested_in_ci(self):
        self.assertIn("\nmod dolphin_demo_core;\nmod dolphin_demo;\n", self.read("src", "lib.rs"))
        self.assertIn("rustc --edition 2021 --test src/dolphin_demo_core.rs", CHECK)

    def test_both_apps_speak_the_same_names(self):
        for rust, dart in (("REQUEST_ID", "kDolphinDemoKey"), ("ANSWER_MSGTYPE", "kDolphinDemoKey"),
                           ("SESSION_START", "kDolphinDemoKey"), ("SESSION_CANCEL", "kDolphinDemoCancelKey"),
                           ("INTENT_KEY", "kDolphinDemoIntentKey"), ("PLATFORM_ADDITION", "kDolphinDemoAddition"),
                           ("PLATFORM_SCREENS", "kDolphinDemoScreensAddition"), ("CM_ANSWER", "kDolphinDemoAnswer")):
            self.assertEqual(self.core_const(rust), self.dart_const(dart), rust)
        self.assertIn("const kDolphinDemoAskSecs = 60;", self.read("flutter", "lib", "dolphin", "demo.dart"))
        self.assertIn("pub const ASK_SECS: u64 = 60;", self.read("src", "dolphin_demo_core.rs"))
        # The customer PC's audit: the portal records engine.demo_viewed for this action.
        self.assertEqual(self.core_const("AUDIT_ACTION"), "demo")

    def test_the_technician_app_is_never_logged_into(self):
        conn = self.read("src", "server", "connection.rs")
        msg = conn.split("async fn on_message(&mut self, msg: Message) -> bool {", 1)[1]
        gate = msg.index("if let Some(keep) = self.dolphin_demo_gate(&msg).await {")
        # after the close reason, before upstream reads any LoginRequest (password, code, approval)
        self.assertLess(msg.index('self.on_close("Peer close", true).await;'), gate)
        self.assertLess(gate, msg.index("if let Some(message::Union::LoginRequest(lr)) = msg.union {"))
        body = conn.split("async fn dolphin_demo_gate(&mut self, msg: &Message) -> Option<bool> {", 1)[1]
        body = body.split("\n    }\n", 1)[0]
        self.assertIn("rules::pre_login(hbb_common::config::is_outgoing_only(), kind) == Gate::Refuse", body)
        self.assertIn("return Some(false);", body)
        self.assertIn("let all = self.dolphin_demo?;", body)
        self.assertIn("if rules::inbound_allowed(kind, all) {", body)

    def test_only_the_awaited_demo_switches_back_and_it_only_watches(self):
        conn = self.read("src", "server", "connection.rs")
        branch = conn.split("} else if let Some(message::Union::SwitchSidesResponse(_s)) = msg.union {", 1)[1][:3200]
        claim = branch.index("if !self.dolphin_demo_claim(&lr, &_s.uuid).await {")
        self.assertLess(claim, branch.index("let uuid_old = SWITCH_SIDES_UUID.lock().unwrap().remove(&lr.my_id);"))
        self.assertLess(branch.index("self.from_switch = true;"), branch.index("self.dolphin_demo_scope_login();"))
        self.assertLess(branch.index("self.dolphin_demo_scope_login();"),
                        branch.index("if !self.send_logon_response_and_keep_alive().await {"))
        body = conn.split("async fn dolphin_demo_claim(&mut self, lr: &LoginRequest, uuid: &[u8]) -> bool {", 1)[1]
        body = body.split("\n    }\n", 1)[0]
        self.assertIn("if !hbb_common::config::is_outgoing_only() {", body)
        self.assertIn("crate::dolphin_demo::claim(&lr.my_id, &u)", body)
        for off in ("keyboard", "clipboard", "audio", "file", "restart", "recording", "block_input", "privacy_mode",
                    "lock_after_session_end"):
            self.assertIn(f"self.{off} = false;", body)
        self.assertLess(body.index("self.lock_after_session_end = false;"), body.index("insert_switch_sides_uuid("))
        scope = conn.split("fn dolphin_demo_scope_login(&mut self) {", 1)[1].split("\n    }\n", 1)[0]
        self.assertIn("Self::scoped_view_camera_option(&option).0", scope)
        # the technician's own window cannot hand the demo a permission
        perm = conn.split("ipc::Data::SwitchPermission{name, enabled} => {", 1)[1][:2000]
        self.assertLess(perm.index("if conn.dolphin_demo.is_some() {"), perm.index('} else if &name == "keyboard" {'))
        self.assertIn("if conn.dolphin_demo.is_some() {\n                                continue;", perm)
        end = conn.split('conn.on_close("End", true).await;', 1)[1][:300]
        self.assertIn("crate::dolphin_demo::ended();", end)

    def test_the_technician_app_is_reachable_only_while_its_demo_waits(self):
        rz = self.read("src", "rendezvous_mediator.rs")
        start_all = rz.split("pub async fn start_all() {", 1)[1].split("crate::hbbs_http::sync::start();", 1)[0]
        self.assertIn("Self::dolphin_demo_listen(&mut dolphin_demo_server).await;", start_all)
        listen = rz.split("async fn dolphin_demo_listen(server: &mut Option<ServerPtr>) {", 1)[1].split("\n    }\n", 1)[0]
        self.assertIn("if !crate::dolphin_demo::listening() {", listen)
        self.assertIn("while crate::dolphin_demo::listening() && !SHOULD_EXIT.load(Ordering::SeqCst) {", listen)
        for never in ("direct_server", "lan::start_listening", "hbbs_http::sync::start", "start_auto_update"):
            self.assertNotIn(never, listen)

    def test_the_customer_is_asked_first(self):
        conn = self.read("src", "server", "connection.rs")
        arm = conn.split("Some(misc::Union::PluginRequest(p)) if crate::dolphin_demo_core::is_request(&p.id) => {", 1)
        self.assertIn("self.dolphin_demo_request(&p.content).await;", arm[1][:200])
        # before upstream's own arm, which would hand it to the side pane's paste
        self.assertIn("Some(misc::Union::PluginRequest(p)) => {", arm[1])
        req = conn.split("async fn dolphin_demo_request(&mut self, content: &[u8]) {", 1)[1].split("\n    }\n", 1)[0]
        self.assertIn("if !self.is_authed_remote_conn() || self.view_camera {", req)
        self.assertIn('ui: cfg!(feature = "flutter"),', req)
        self.assertNotIn("launch_view", req)
        ans = conn.split("async fn dolphin_demo_answer(&mut self, see: bool) -> bool {", 1)[1].split("\n    }\n", 1)[0]
        self.assertLess(ans.index("} else if crate::dolphin_demo::launch_view(&self.lr.my_id, &uuid) {"),
                        ans.index('self.post_conn_audit(json!({ "action": rules::AUDIT_ACTION }));'))
        perm = conn.split("ipc::Data::SwitchPermission{name, enabled} => {", 1)[1][:2000]
        self.assertIn("if &name == crate::dolphin_demo_core::CM_ANSWER {", perm)
        timer = conn.split("_ = second_timer.tick() => {", 1)[1][:1400]
        self.assertIn("if !conn.dolphin_demo_tick().await {", timer)
        cm = self.read("src", "ui_cm_interface.rs")
        self.assertIn("pub dolphin_demo_ask: bool,", cm)
        sw = cm.split("pub fn switch_permission(id: i32, name: String, enabled: bool) {", 1)[1][:600]
        self.assertIn("if name == crate::dolphin_demo_core::CM_ANSWER {", sw)
        model = self.read("flutter", "lib", "models", "server_model.dart")
        self.assertIn("dolphinDemoAsk = json['dolphin_demo_ask'] ?? false;", model)
        view = self.read("flutter", "lib", "dolphin", "connection.dart")
        self.assertIn("canSee: acceptAllowed(verdict),", view)
        self.assertIn("if (acceptAllowed(_verdict())) answer(true);", view)
        # the x86 build says at login that it cannot, so the technician knows before asking
        self.assertIn('platform_additions.insert(crate::dolphin_demo_core::PLATFORM_ADDITION.into(), '
                      'json!(cfg!(feature = "flutter")));', conn)

    def test_the_flutter_hooks(self):
        model = self.read("flutter", "lib", "models", "model.dart")
        box = model.split("handleMsgBox(Map<String, dynamic> evt, SessionID sessionId, String peerId) {", 1)[1]
        self.assertLess(box.index("if (dolphinDemoMsgBox(parent.target, type, title, text)) return;"),
                        box.index("if (_dolphinQuietRetry(type, title, text, dialogManager)) return;"))
        self.assertIn("dolphinDemoOnPeerInfo(parent.target);", model)
        remote = self.read("flutter", "lib", "desktop", "pages", "remote_page.dart")
        self.assertIn("? DolphinDemoWindowStrip(ffi: _ffi, peerId: widget.id)", remote)
        server = self.read("flutter", "lib", "desktop", "pages", "server_page.dart")
        self.assertIn("if (bind.isOutgoingOnly()) return const DolphinDemoBarHost();", server)
        self.assertIn("dolphinDemoWindowOpened(widget.ffi);", self.read("flutter", "lib", "dolphin", "side_pane.dart"))
        session = self.read("src", "ui_session_interface.rs")
        self.assertIn("crate::dolphin_demo::session_request(&self.get_id(), key, value)", session)
        ffi = self.read("src", "flutter_ffi.rs")
        self.assertIn("if _key == crate::dolphin_demo_core::INTENT_KEY {", ffi)
        self.assertIn("} else if key == crate::dolphin_demo_core::INTENT_KEY {", ffi)


if __name__ == "__main__":
    unittest.main()


class ThemeTokensWiringTest(unittest.TestCase):
    """Plan 19: one token set for both apps; the customer app takes the portal's `dolphin-theme` from the heartbeat."""

    def read(self, *parts):
        return ROOT.joinpath(*parts).read_text(encoding="utf-8")

    def test_the_palettes_read_the_tokens(self):
        theme = self.read("flutter", "lib", "dolphin", "theme.dart")
        tech = self.read("flutter", "lib", "dolphin", "tech_theme.dart")
        # Plan 19 C5: the customer's own light or dark; the technician app never applies one, so it stays light.
        self.assertIn("static DolphinThemeTokens get _t => dolphinCustomerTokens;", theme)
        self.assertIn(
            "DolphinThemeTokens get dolphinCustomerTokens => DolphinTheme.of(DolphinCustomerTheme.brightness.value);", theme)
        self.assertIn("static final ValueNotifier<Brightness> brightness = ValueNotifier(Brightness.light);", theme)
        self.assertNotIn("static const azure", theme)
        self.assertIn("static DolphinTechPalette get dark => DolphinTechPalette.fromTokens(DolphinTheme.dark);", tech)
        # no hard-coded brand colour left in the views
        for path in ROOT.joinpath("flutter", "lib", "dolphin").glob("*.dart"):
            if path.name in ("theme_tokens.dart", "brand.dart"):
                continue
            self.assertNotIn("Color(0xFF", path.read_text(encoding="utf-8"), path.name)

    def test_the_customer_app_reads_the_option_and_hands_it_to_the_session_window(self):
        tokens = self.read("flutter", "lib", "dolphin", "theme_tokens.dart")
        self.assertIn("const kDolphinThemeOption = 'dolphin-theme';", tokens)
        home = self.read("flutter", "lib", "dolphin", "home.dart")
        self.assertEqual(home.count("syncThemeFromPortal();"), 2)  # at start and on the 2 s read
        self.assertIn("themeFromMainWindow();", self.read("flutter", "lib", "dolphin", "connection.dart"))
        self.assertIn("ThemeOverrideResult applyThemeOverrides(Object? json)", tokens)


class CustomerLookWiringTest(unittest.TestCase):
    """Plan 19 C1–C7: the customer app's new look. The hooks in upstream files and the Rust side, proven by their
    text (the views themselves are tested in flutter/test/dolphin/customer_look_test.dart)."""

    def read(self, *parts):
        return ROOT.joinpath(*parts).read_text(encoding="utf-8")

    def test_the_frame_core_is_a_module_and_tested_in_ci(self):
        lib = self.read("src", "lib.rs")
        self.assertIn("#[cfg(windows)]\nmod dolphin_frame_core;\n#[cfg(windows)]\nmod dolphin_frame;\n", lib)
        self.assertIn("rustc --edition 2021 --test src/dolphin_frame_core.rs", CHECK)
        ffi = self.read("src", "flutter_ffi.rs")
        self.assertIn('if _key == "dolphin-frame" {\n        crate::dolphin_frame::set(&_value);', ffi)

    def test_the_frame_is_click_through_and_never_activated(self):
        frame = self.read("src", "dolphin_frame.rs")
        for flag in ["WS_EX_TOPMOST", "WS_EX_TOOLWINDOW", "WS_EX_NOACTIVATE", "WS_EX_LAYERED", "WS_EX_TRANSPARENT",
                     "HTTRANSPARENT", "MA_NOACTIVATE", "WS_POPUP"]:
            self.assertIn(flag, frame)

    def test_the_session_window_guards_every_press_and_sends_the_frame(self):
        conn = self.read("flutter", "lib", "dolphin", "connection.dart")
        for hook in ["onAccept: (grant) => _local(() {", "onDeny: () => _local(() {", "onToggle: (name, enabled) => _local(() {",
                     "onEnd: () => _local(() {", "onFrame: (on) => _local(() {", "await bind.cmCheckClickTime(connId: connId);",
                     "bind.mainSetCommon(key: kDolphinFrameCommon, value: cmd);",
                     "bind.cmSwitchPermission(connId: c.id, name: 'audio', enabled: g.audio);"]:
            self.assertIn(hook, conn)

    def test_the_tray_menu_is_the_approved_one(self):
        core = self.read("src", "dolphin_system_core.rs")
        for text in ["باز کردن دلفین کانکت", "توقف اشتراک", "شروع اشتراک", "بستن کامل", "● در دسترس — آماده برای پشتیبانی"]:
            self.assertIn(text, core)
        tray = self.read("src", "dolphin_system.rs")
        self.assertIn("menu.append_items(&[&state_i, &open_i, &PredefinedMenuItem::separator(), &quit_i]).ok();", tray)
        self.assertIn("set_share_off(rules::tray_share_press_stops(shown_state));", tray)

    def test_the_prompt_and_windows_have_the_approved_sizes(self):
        consts = self.read("flutter", "lib", "consts.dart")
        self.assertIn("const Size kConnectionManagerWindowSizeClosedChat = Size(320, 520);", consts)
        sizes = self.read("flutter", "lib", "dolphin", "window_sizes.dart")
        self.assertIn("const kDolphinHomeWindowSize = Size(380, 580);", sizes)
        self.assertIn("const kDolphinSessionWindowSize = Size(300, 380);",
                      self.read("flutter", "lib", "dolphin", "session_controls.dart"))


class StartUpdatePopupWiringTest(unittest.TestCase):
    """Plan 19: every start asks the portal (TB-20's check). Customer: required popup before the app (D10).
    Technician: the app opens and «به‌روزرسانی» / «بعداً» shows over it once per start."""

    def read(self, *parts):
        return ROOT.joinpath(*parts).read_text(encoding="utf-8")

    def test_every_start_asks_and_the_answer_picks_the_popup(self):
        main = self.read("flutter", "lib", "main.dart")
        self.assertIn("if (await runDolphinUpdateIfNeeded(() => _openMainApp(startService))) return;", main)
        update = self.read("flutter", "lib", "dolphin", "update.dart")
        self.assertIn("await bind.mainGetCommon(key: 'dolphin-update-check')", update)
        self.assertIn("switch (startUpdateAction(check, technician: bind.isOutgoingOnly())) {", update)
        self.assertIn("dolphinPendingTechUpdate = check;", update)

    def test_the_technician_home_shows_the_popup_after_its_first_frame(self):
        # Plan 19: the native technician window (tech_ui/technician_app.dart) replaced technician_home.dart; its
        # «به‌روزرسانی» downloads through the app API when signed in.
        home = self.read("flutter", "lib", "dolphin", "tech_ui", "technician_app.dart")
        self.assertIn("if (mounted) showPendingTechUpdate(context, onUpdate: _update);", home)
        self.assertIn("addPostFrameCallback", home)
        # «بعداً» stores nothing: the pending answer lives in memory for this start only
        update = self.read("flutter", "lib", "dolphin", "update.dart")
        body = update.split("Future<void> showPendingTechUpdate(BuildContext context,", 1)[1]
        self.assertNotIn("mainSetLocalOption", body)
        self.assertNotIn("mainSetOption", body)


class OneWayAndLockWiringTest(unittest.TestCase):
    """Plan 19 (RO-4, RO-5): the portal's switches reach upstream's own enforcement; nothing is stored."""

    def read(self, *parts):
        return ROOT.joinpath(*parts).read_text(encoding="utf-8")

    def test_one_way_answers_through_upstreams_builtin_option_reader(self):
        common = self.read("src", "common.rs")
        body = common.split("pub fn get_builtin_option(key: &str) -> String {", 1)[1].split("\n}\n", 1)[0]
        self.assertLess(body.index("crate::dolphin_system_core::is_one_way_key(key)"), body.index("config::BUILTIN_SETTINGS"))
        conn = self.read("src", "server", "connection.rs")
        # upstream's own checks, unchanged, are what the switch turns on
        self.assertIn("crate::get_builtin_option(keys::OPTION_ONE_WAY_FILE_TRANSFER) == \"Y\"", conn)
        self.assertIn("crate::get_builtin_option(keys::OPTION_ONE_WAY_CLIPBOARD_REDIRECTION) != \"Y\"", conn)
        keys = self.read("libs", "base", "src", "config", "keys.rs")
        self.assertIn('OPTION_ONE_WAY_FILE_TRANSFER: &str = "one-way-file-transfer";', keys)
        self.assertIn('OPTION_ONE_WAY_CLIPBOARD_REDIRECTION: &str = "one-way-clipboard-redirection";', keys)

    def test_lock_on_end_keeps_upstreams_other_conditions(self):
        conn = self.read("src", "server", "connection.rs")
        close = conn.split("async fn on_close(&mut self, reason: &str, lock: bool) {", 1)[1][:3000]
        block = close.split("if lock\n", 1)[1].split("lock_screen().await;", 1)[0]
        self.assertIn("crate::dolphin_system_core::lock_at_end_by(", block)
        self.assertIn("self.lock_after_session_end,", block)
        self.assertIn("&& self.keyboard", block)
        self.assertIn("!raii::AuthedConnID::session_reconnected(", block)


class GhcrReleaseOrderTest(unittest.TestCase):
    """Portal ADR-0017: the portal follows the newest version tag by itself, so the release job tags a version only
    after every pushed exe matches SHA256SUMS, and pushes SHA256SUMS as a layer for the portal to check."""

    def test_push_under_staging_check_then_tag(self):
        build = ROOT.joinpath(".github", "workflows", "dolphin-build.yml").read_text(encoding="utf-8")
        step = build.split("- name: Push the exes to ghcr.io", 1)[1].split("\n      - ", 1)[0]
        self.assertIn('staging="staging-${GITHUB_RUN_ID}"', step)
        self.assertIn('oras push "$repo:$staging"', step)
        self.assertNotIn('oras push "$repo:$v"', step)
        self.assertIn('"SHA256SUMS:text/plain"', step)
        self.assertLess(step.index("diff -u expected.txt pushed.txt"), step.index('oras tag "$repo:$staging" "$v"'))
