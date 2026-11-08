#!/usr/bin/env python3
"""Configure a Mac for the hosted LiftRank demo; never deploy or fetch AI secrets."""

import argparse
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.error
import urllib.parse
import urllib.request


ROOT = Path(__file__).resolve().parents[1]
PROJECT = "liftrank-514018"
API_URL = "https://liftrank-social-937516211756.us-central1.run.app"
SIMULATOR_CONFIG = Path("LiftRank/Resources/SocialConfig.plist")
DEVICE_CONFIG = Path("configuration/SocialConfig.device.plist")
SIGNING_CONFIG = Path("configuration/Signing.local.xcconfig")


class SetupError(Exception):
    pass


def run(command, **kwargs):
    try:
        return subprocess.run(command, check=True, capture_output=True, text=True,
                              timeout=120, **kwargs)
    except (OSError, subprocess.SubprocessError):
        # CLI output can contain configuration or authentication details.
        raise SetupError(f"{Path(command[0]).name} {command[1]} failed. "
                         "Check the tool installation, network and account access.") from None


def ask(label, default, non_interactive):
    if non_interactive or not sys.stdin.isatty():
        if default:
            return default
        raise SetupError(f"Missing {label}. Supply the corresponding command-line option; see --help.")
    return input(label + (f" [{default}]" if default else "") + ": ").strip() or default


def validate_bundle(value):
    if not re.fullmatch(r"[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+", value or ""):
        raise SetupError("Bundle ID must contain dot-separated letters, numbers or hyphens.")
    return value


def validate_team(value):
    if not re.fullmatch(r"[A-Z0-9]{10}", value or ""):
        raise SetupError("Apple Team ID must be 10 uppercase letters/numbers. Use the Team ID, not an email.")
    return value


def https_url(value, label):
    try:
        url = urllib.parse.urlsplit(value)
        valid = (url.scheme == "https" and url.hostname and not url.username and not url.password
                 and not url.query and not url.fragment and not any(c.isspace() for c in value))
        _ = url.port
    except ValueError:
        valid = False
    if not valid:
        raise SetupError(f"{label} must be an HTTPS URL without credentials, query or fragment.")
    return value.rstrip("/")


def setting(path, key):
    if not path.exists():
        return None
    matches = re.findall(r"^" + re.escape(key) + r"\s*=\s*([^\r\n]+)", path.read_text(), re.M)
    return matches[-1].split("//", 1)[0].strip() if matches else None


def prerequisites(root):
    if sys.platform != "darwin":
        raise SetupError("The demo app needs macOS and Xcode. See docs/NEW_MAC_SETUP.md.")
    version = run(["xcodebuild", "-version"]).stdout.splitlines()
    if not version or not version[0].startswith("Xcode "):
        raise SetupError("Open Xcode once, install its components, and select its developer directory.")
    print(version[0] + " detected. Xcode 26+ enables live iPhone HealthKit sessions.")
    node = run(["node", "--version"]).stdout.strip()
    if not re.match(r"v\d+\.", node) or int(node[1:].split(".")[0]) < 22:
        raise SetupError("Install Node.js 22 or newer; Node 22 LTS is recommended for this repository.")
    local_cli = root / "backend/node_modules/.bin/firebase"
    cli = str(local_cli) if local_cli.is_file() else shutil.which("firebase")
    if not cli:
        raise SetupError("Install the pinned Firebase CLI: npm ci --prefix backend; then rerun setup.")
    return cli


class Firebase:
    def __init__(self, executable, root):
        self.executable = executable
        self.root = root

    def call(self, *arguments):
        result = run([self.executable, *arguments, "--project", PROJECT, "--json", "--non-interactive"],
                     cwd=self.root)
        try:
            payload = json.loads(result.stdout)
            if not isinstance(payload, dict) or payload.get("status") != "success":
                raise ValueError()
            return payload.get("result")
        except (ValueError, TypeError):
            raise SetupError("Firebase did not return valid successful JSON. "
                             "Run npm ci --prefix backend and verify your Firebase login/project access.") from None

    def authenticate(self, non_interactive):
        if self.call("login:list"):
            return
        if non_interactive or not sys.stdin.isatty():
            raise SetupError("Sign in first: backend/node_modules/.bin/firebase login")
        print("Opening Firebase sign-in. Use a Google account with access to " + PROJECT + ".")
        # The official CLI handles browser login; we never read or copy its token store.
        try:
            subprocess.run([self.executable, "login"], cwd=self.root, check=True)
        except (OSError, subprocess.SubprocessError):
            raise SetupError("Firebase sign-in did not finish. Run firebase login and retry.") from None
        if not self.call("login:list"):
            raise SetupError("No Firebase account is signed in.")

    def configuration(self, app, bundle_id, api_url):
        result = self.call("apps:sdkconfig", "IOS", app["appId"])
        try:
            raw = plistlib.loads(result["fileContents"].encode("utf-8"))
        except (KeyError, TypeError, AttributeError, ValueError, plistlib.InvalidFileException):
            raise SetupError("Firebase returned an invalid iOS configuration.") from None
        return social_config(raw, bundle_id, app["appId"], api_url)


def find_app(apps, bundle_id):
    matches = [app for app in apps if isinstance(app, dict) and app.get("bundleId") == bundle_id
               and app.get("state", "ACTIVE") == "ACTIVE"]
    if len(matches) != 1 or not isinstance(matches[0].get("appId"), str):
        raise SetupError(f"Expected one registered Firebase iOS app for {bundle_id}. "
                         f"In Firebase Console → {PROJECT} → Project settings → Your apps, "
                         "register this exact bundle ID (or choose an existing one), then rerun. "
                         "This script does not create cloud apps.")
    return matches[0]


def social_config(raw, bundle_id, app_id, api_url):
    if not isinstance(raw, dict) or any(raw.get(key) != expected for key, expected in (
        ("PROJECT_ID", PROJECT), ("BUNDLE_ID", bundle_id), ("GOOGLE_APP_ID", app_id)
    )):
        raise SetupError("Downloaded Firebase project, app or bundle ID does not match the requested app.")
    mapping = {"PROJECT_ID": "PROJECT_ID", "API_KEY": "API_KEY", "APP_ID": "GOOGLE_APP_ID",
               "SENDER_ID": "GCM_SENDER_ID", "DATABASE_URL": "DATABASE_URL", "STORAGE_BUCKET": "STORAGE_BUCKET"}
    output = {"API_URL": https_url(api_url, "API URL")}
    for target, source in mapping.items():
        value = raw.get(source)
        if not isinstance(value, str) or not value.strip() or value.startswith("REPLACE-"):
            raise SetupError(f"Firebase configuration is missing {source}. "
                             "Ask the project owner to verify its Realtime Database/Storage configuration.")
        output[target] = value
    output["DATABASE_URL"] = https_url(output["DATABASE_URL"], "Database URL")
    return plistlib.dumps(output, sort_keys=False)


def signing_config(team, bundle):
    validate_team(team)
    validate_bundle(bundle)
    return ("// Generated by scripts/setup-demo; local settings stay out of Git.\n"
            f"DEVELOPMENT_TEAM = {team}\n"
            f"LIFTRANK_APP_BUNDLE_IDENTIFIER[sdk=iphoneos*] = {bundle}\n"
            f"LIFTRANK_APP_BUNDLE_IDENTIFIER[sdk=watchos*] = {bundle}\n"
            f"LIFTRANK_TEST_BUNDLE_IDENTIFIER[sdk=iphoneos*] = {bundle}.tests\n"
            f"LIFTRANK_UI_TEST_BUNDLE_IDENTIFIER[sdk=iphoneos*] = {bundle}.social-uitests\n"
            "LIFTRANK_SOCIAL_CONFIG_PATH[sdk=iphoneos*] = $(SRCROOT)/configuration/SocialConfig.device.plist\n").encode()


def check_health(api_url):
    try:
        with urllib.request.urlopen(api_url + "/health", timeout=20) as response:
            healthy = (response.status == 200 and response.url.startswith("https://")
                       and json.loads(response.read(4096)).get("status") == "ok")
        if not healthy:
            raise ValueError()
    except (OSError, urllib.error.URLError, ValueError, AttributeError):
        raise SetupError("The demo backend health check failed. Check your network or --api-url "
                         "and ask the project owner to check Cloud Run. No setup files were changed.") from None
    print("Demo backend /health: OK (does not test sign-in, multiplayer or AI inference).")


def ensure_local_paths(root, files):
    for relative in files:
        path = root / relative
        if path.is_symlink() or not path.resolve().is_relative_to(root.resolve()):
            raise SetupError(f"Refusing a linked configuration path: {relative}")
        if path.exists() and not path.is_file():
            raise SetupError(f"Configuration path is not a file: {relative}")
        if run(["git", "ls-files", "--", str(relative)], cwd=root).stdout.strip():
            raise SetupError(f"Refusing to write tracked configuration: {relative}")
        try:
            run(["git", "check-ignore", "-q", "--", str(relative)], cwd=root)
        except SetupError:
            raise SetupError(f"Configuration must be ignored by Git: {relative}") from None


def atomic_write(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(dir=path.parent, prefix=".setup-demo-", delete=False) as stream:
            temporary = Path(stream.name)
            stream.write(data)
        os.replace(temporary, path)  # mkstemp creates owner-only files (0600).
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def save_files(root, files, check=False, replace=False, non_interactive=False):
    ensure_local_paths(root, files)
    originals = {relative: (root / relative).read_bytes() if (root / relative).exists() else None for relative in files}
    changes = {relative: data for relative, data in files.items() if originals[relative] != data}
    if check:
        for relative in files:
            state = "would create" if originals[relative] is None else "would update" if relative in changes else "up to date"
            print(f"{relative}: {state}")
        print("Check complete; no setup files written.")
        return
    overwrites = [str(path) for path in changes if originals[path] is not None]
    if overwrites and not replace:
        print("Existing files differ: " + ", ".join(overwrites))
        if ask("Replace these local files? Type yes", "no", non_interactive).lower() != "yes":
            raise SetupError("Existing settings preserved. Review with --check, or rerun with --replace.")
    written = []
    try:
        for relative, data in changes.items():
            atomic_write(root / relative, data)
            written.append(relative)
    except OSError:
        for relative in reversed(written):
            if originals[relative] is None:
                (root / relative).unlink(missing_ok=True)
            else:
                atomic_write(root / relative, originals[relative])
        raise SetupError("Could not write configuration; previous file contents were restored.") from None
    for relative in files:
        print(f"{relative}: {'saved' if relative in changes else 'up to date'}")


def parser():
    result = argparse.ArgumentParser(prog="./scripts/setup-demo", description=__doc__)
    result.add_argument("--simulator-only", action="store_true", help="Configure the simulator; leave device/signing files untouched")
    result.add_argument("--team-id", help="Apple Team ID (10 uppercase letters/numbers)")
    result.add_argument("--bundle-id", help="Registered physical iPhone bundle ID; reused from local signing settings on later runs")
    result.add_argument("--api-url", default=API_URL, help="Hosted API base URL (HTTPS); defaults to the existing demo backend")
    result.add_argument("--check", action="store_true", help="Fetch/validate config and check health without writing setup files")
    result.add_argument("--replace", action="store_true", help="Replace differing local setup files without prompting")
    result.add_argument("--non-interactive", action="store_true", help="Require existing Firebase login and explicit/saved signing choices")
    return result


def setup(args, root=ROOT):
    if args.simulator_only and (args.team_id or args.bundle_id):
        raise SetupError("Use --simulator-only without --team-id or --bundle-id.")
    api_url = https_url(args.api_url, "API URL")
    client = Firebase(prerequisites(root), root)
    client.authenticate(args.non_interactive)
    apps = client.call("apps:list", "IOS")
    if not isinstance(apps, list):
        raise SetupError("Firebase returned no app list. Check access to " + PROJECT + ".")
    simulator_bundle = validate_bundle(setting(root / "configuration/Build.xcconfig", "LIFTRANK_APP_BUNDLE_IDENTIFIER"))
    # Unconditional local overrides also affect simulator builds; do not silently pick another app.
    override = setting(root / SIGNING_CONFIG, "LIFTRANK_APP_BUNDLE_IDENTIFIER")
    if override and override != simulator_bundle:
        raise SetupError("Local signing overrides the simulator bundle ID. Use SDK-conditional device settings "
                         "as shown in configuration/Signing.local.xcconfig.example.")
    files = {SIMULATOR_CONFIG: client.configuration(find_app(apps, simulator_bundle), simulator_bundle, api_url)}
    if not args.simulator_only:
        saved_bundle = setting(root / SIGNING_CONFIG, "LIFTRANK_APP_BUNDLE_IDENTIFIER[sdk=iphoneos*]")
        saved_team = setting(root / SIGNING_CONFIG, "DEVELOPMENT_TEAM")
        if not (args.bundle_id or saved_bundle):
            print("Registered iOS bundle IDs: " + ", ".join(sorted({app.get("bundleId", "") for app in apps if isinstance(app, dict)})))
        bundle = validate_bundle(args.bundle_id or saved_bundle or ask("iPhone bundle ID (--bundle-id)", "", args.non_interactive))
        device_app = find_app(apps, bundle)
        team = validate_team(args.team_id or saved_team or ask("Apple Team ID (--team-id)", "", args.non_interactive))
        files[DEVICE_CONFIG] = client.configuration(device_app, bundle, api_url)
        files[SIGNING_CONFIG] = signing_config(team, bundle)
    check_health(api_url)
    save_files(root, files, args.check, args.replace, args.non_interactive)
    if not args.check:
        print("Open LiftRank.xcodeproj → LiftRank scheme → choose your device → Run.")
        print("Sign in to your Apple account in Xcode for a physical iPhone. See docs/NEW_MAC_SETUP.md.")


def main():
    try:
        setup(parser().parse_args())
        return 0
    except (SetupError, OSError) as error:
        # OSError text may include paths/configuration; only our controlled messages are shown.
        print("Setup failed: " + (str(error) if isinstance(error, SetupError) else "Unable to read/write local files. Check permissions."), file=sys.stderr)
        return 1
    except (KeyboardInterrupt, EOFError):
        print("\nSetup cancelled.", file=sys.stderr)
        return 130


if __name__ == "__main__":
    sys.exit(main())
