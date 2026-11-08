"""Offline setup regressions: real file/Git boundaries, synthetic Firebase responses."""

import contextlib
import io
import json
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import setup_demo as setup


SIM_BUNDLE = "com.liftrank.app"
PHONE_BUNDLE = "com.example.liftrank.demo"
TEAM = "ABC123DE45"
APPS = [{"bundleId": SIM_BUNDLE, "appId": "1:123:ios:sim", "state": "ACTIVE"},
        {"bundleId": PHONE_BUNDLE, "appId": "1:123:ios:phone", "state": "ACTIVE"}]


def sdk_config(bundle=SIM_BUNDLE, app_id="1:123:ios:sim"):
    return {"PROJECT_ID": setup.PROJECT, "BUNDLE_ID": bundle, "GOOGLE_APP_ID": app_id,
            "API_KEY": "synthetic-client-key", "GCM_SENDER_ID": "123",
            "DATABASE_URL": "https://example-default-rtdb.firebaseio.com",
            "STORAGE_BUCKET": "example.firebasestorage.app"}


def firebase_result(*arguments):
    if arguments[0] == "login:list":
        return [{"user": {"email": "demo@example.invalid"}}]
    if arguments[0] == "apps:list":
        return APPS
    if arguments[0] == "apps:sdkconfig":
        app = next(app for app in APPS if app["appId"] == arguments[2])
        return {"fileContents": plistlib.dumps(sdk_config(app["bundleId"], app["appId"])).decode()}
    raise AssertionError("Unexpected Firebase operation")


class SetupTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="LiftRank setup test ")
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        subprocess.run(["git", "init", "-q", str(self.root)], check=True)
        (self.root / ".gitignore").write_text("SocialConfig.plist\nconfiguration/SocialConfig.device.plist\nconfiguration/Signing.local.xcconfig\n.setup-demo-*\n")
        (self.root / "configuration").mkdir()
        (self.root / "configuration/Build.xcconfig").write_text(f"LIFTRANK_APP_BUNDLE_IDENTIFIER = {SIM_BUNDLE}\n")
        self.output = io.StringIO()
        redirect = contextlib.redirect_stdout(self.output)
        redirect.__enter__()
        self.addCleanup(redirect.__exit__, None, None, None)

    def execute(self, *flags):
        args = setup.parser().parse_args(list(flags))
        with patch.object(setup, "prerequisites", return_value="firebase"), \
             patch.object(setup.Firebase, "call", side_effect=firebase_result), \
             patch.object(setup, "check_health"):
            setup.setup(args, self.root)

    def write(self, relative, content):
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content)
        return path

    def test_fresh_phone_and_simulator_setup_and_repeat(self):
        self.execute("--team-id", TEAM, "--bundle-id", PHONE_BUNDLE, "--non-interactive")
        simulator = plistlib.loads((self.root / setup.SIMULATOR_CONFIG).read_bytes())
        phone = plistlib.loads((self.root / setup.DEVICE_CONFIG).read_bytes())
        self.assertEqual(simulator["APP_ID"], APPS[0]["appId"])
        self.assertEqual(phone["APP_ID"], APPS[1]["appId"])
        self.assertEqual(simulator["API_URL"], setup.API_URL)
        self.assertNotIn("EMULATOR_HOST", simulator)
        signing = (self.root / setup.SIGNING_CONFIG).read_text()
        self.assertIn(f"[sdk=watchos*] = {PHONE_BUNDLE}", signing)
        before = {p: (self.root / p).stat().st_mtime_ns for p in (setup.SIMULATOR_CONFIG, setup.DEVICE_CONFIG, setup.SIGNING_CONFIG)}
        self.execute("--non-interactive")  # Saved choices; no input or file rewrite.
        self.assertEqual(before, {p: (self.root / p).stat().st_mtime_ns for p in before})
        self.assertTrue(all((self.root / p).stat().st_mode & 0o777 == 0o600 for p in before))
        status = subprocess.check_output(["git", "status", "--short"], cwd=self.root, text=True)
        self.assertNotIn("SocialConfig", status)
        self.assertNotIn("synthetic-client-key", self.output.getvalue())

    def test_simulator_only_preserves_device_files(self):
        device = self.write(setup.DEVICE_CONFIG, b"existing device configuration")
        signing = self.write(setup.SIGNING_CONFIG, b"// existing custom settings\n")
        self.execute("--simulator-only", "--non-interactive")
        self.assertEqual(device.read_bytes(), b"existing device configuration")
        self.assertEqual(signing.read_bytes(), b"// existing custom settings\n")
        self.assertTrue((self.root / setup.SIMULATOR_CONFIG).is_file())

    def test_check_does_not_create_or_update_files(self):
        path = self.write(setup.SIMULATOR_CONFIG, b"existing emulator settings")
        self.execute("--check", "--team-id", TEAM, "--bundle-id", PHONE_BUNDLE, "--non-interactive")
        self.assertEqual(path.read_bytes(), b"existing emulator settings")
        self.assertFalse((self.root / setup.DEVICE_CONFIG).exists())
        self.assertFalse((self.root / setup.SIGNING_CONFIG).exists())

    def test_existing_config_requires_replace_and_no_partial_files(self):
        path = self.write(setup.SIMULATOR_CONFIG, b"keep existing settings")
        with self.assertRaisesRegex(setup.SetupError, "preserved"):
            self.execute("--team-id", TEAM, "--bundle-id", PHONE_BUNDLE, "--non-interactive")
        self.assertEqual(path.read_bytes(), b"keep existing settings")
        self.assertFalse((self.root / setup.DEVICE_CONFIG).exists())
        self.execute("--simulator-only", "--replace", "--non-interactive")
        self.assertEqual(plistlib.loads(path.read_bytes())["PROJECT_ID"], setup.PROJECT)

    def test_sdk_identity_mismatch_and_missing_fields_are_rejected(self):
        for key, value in [("PROJECT_ID", "another-project"), ("BUNDLE_ID", PHONE_BUNDLE),
                           ("GOOGLE_APP_ID", "wrong-app"), ("DATABASE_URL", ""), ("API_KEY", "")]:
            with self.subTest(key=key), self.assertRaises(setup.SetupError):
                raw = sdk_config()
                raw[key] = value
                setup.social_config(raw, SIM_BUNDLE, APPS[0]["appId"], setup.API_URL)

    def test_unknown_or_duplicate_app_does_not_guess(self):
        for apps, bundle in [(APPS, "com.missing.demo"), ([APPS[0], APPS[0]], SIM_BUNDLE)]:
            with self.subTest(bundle=bundle), self.assertRaisesRegex(setup.SetupError, "register this exact bundle ID"):
                setup.find_app(apps, bundle)

    def test_unattended_setup_requires_identity_choices_and_login(self):
        with self.assertRaisesRegex(setup.SetupError, "Missing iPhone bundle ID"):
            self.execute("--non-interactive")
        with patch.object(setup.Firebase, "call", return_value=None), self.assertRaisesRegex(setup.SetupError, "Sign in first"):
            setup.Firebase("firebase", self.root).authenticate(True)
        self.assertFalse((self.root / setup.SIMULATOR_CONFIG).exists())

    def test_backend_failure_leaves_existing_settings_unchanged(self):
        path = self.write(setup.SIMULATOR_CONFIG, b"existing settings")
        with patch.object(setup, "prerequisites", return_value="firebase"), \
             patch.object(setup.Firebase, "call", side_effect=firebase_result), \
             patch.object(setup.urllib.request, "urlopen", side_effect=OSError("network failed")), \
             self.assertRaisesRegex(setup.SetupError, "health check failed"):
            setup.setup(setup.parser().parse_args(["--simulator-only", "--replace"]), self.root)
        self.assertEqual(path.read_bytes(), b"existing settings")

    def test_unignored_tracked_and_linked_destinations_are_rejected(self):
        path = self.write(setup.SIMULATOR_CONFIG, b"existing settings")
        subprocess.run(["git", "add", "-f", str(setup.SIMULATOR_CONFIG)], cwd=self.root, check=True)
        with self.assertRaisesRegex(setup.SetupError, "tracked"):
            setup.save_files(self.root, {setup.SIMULATOR_CONFIG: b"replacement"}, replace=True)
        with self.assertRaisesRegex(setup.SetupError, "ignored"):
            setup.save_files(self.root, {Path("public.plist"): b"configuration"})
        destination = self.root / setup.DEVICE_CONFIG
        destination.symlink_to(path)
        with self.assertRaisesRegex(setup.SetupError, "linked"):
            setup.save_files(self.root, {setup.DEVICE_CONFIG: b"replacement"}, replace=True)

    def test_failed_second_write_rolls_back_first(self):
        path = self.write(setup.SIMULATOR_CONFIG, b"original")
        actual_write = setup.atomic_write

        def fail_device(destination, data):
            if destination == self.root / setup.DEVICE_CONFIG:
                raise OSError("disk error")
            actual_write(destination, data)

        with patch.object(setup, "atomic_write", side_effect=fail_device), self.assertRaisesRegex(setup.SetupError, "restored"):
            setup.save_files(self.root, {setup.SIMULATOR_CONFIG: b"new", setup.DEVICE_CONFIG: b"new device"}, replace=True)
        self.assertEqual(path.read_bytes(), b"original")
        self.assertFalse((self.root / setup.DEVICE_CONFIG).exists())
        self.assertEqual(list(self.root.rglob(".setup-demo-*")), [])

    def test_unsafe_identifiers_and_urls_are_rejected(self):
        for team, bundle in [("ABC\nKEY=X", PHONE_BUNDLE), (TEAM, "com.test.$(OTHER)")]:
            with self.assertRaises(setup.SetupError):
                setup.signing_config(team, bundle)
        for url in ["http://localhost", "https://user:secret@example.com", "https://example.com?key=secret", "https://example.com/#token"]:
            with self.assertRaises(setup.SetupError):
                setup.https_url(url, "API URL")

    def test_cli_json_errors_never_print_response_secrets(self):
        cli = setup.Firebase("firebase", self.root)
        for output in ["invalid secret-token", json.dumps({"status": "error", "error": "secret-token"})]:
            with patch.object(setup, "run", return_value=subprocess.CompletedProcess([], 0, output)), self.assertRaises(setup.SetupError) as caught:
                cli.call("apps:list", "IOS")
            self.assertNotIn("secret-token", str(caught.exception))

    def test_entrypoint_works_outside_checkout(self):
        result = subprocess.run([str(setup.ROOT / "scripts/setup-demo"), "--help"], cwd=self.root,
                                capture_output=True, text=True, check=True)
        self.assertIn("--simulator-only", result.stdout)


if __name__ == "__main__":
    unittest.main()
