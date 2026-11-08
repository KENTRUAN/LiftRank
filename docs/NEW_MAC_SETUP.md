# Run the hosted LiftRank demo on a new Mac

This guide connects a fresh checkout to the existing `liftrank-514018` development project. You do not need files from the old Mac, a VM, a local backend, Java, Google Cloud CLI, or Tinker/Gemini keys. The setup script downloads Firebase **client** configuration and generates local Xcode settings; provider credentials remain on the server.

## 1. Install tools and get access

- Install **Xcode**, open it once, accept its license and install the requested platform components. Install an iOS Simulator runtime through Xcode Settings. Use Xcode 26+ for live iPhone HealthKit sessions and a version compatible with your physical phone's iOS. Xcode 16.4 can build the app using the save-on-finish iPhone Health path.
- Install **Node.js 22 or newer** (Node 22 is the repository's CI baseline) and **Python 3.9 or newer**. Verify with `node --version` and `python3 --version`. The Python setup helper uses only the standard library.
- Get GitHub access to `KENTRUAN/LiftRank` and Google account access to the **existing** Firebase project `liftrank-514018`. The project owner must grant permission to list its iOS apps and retrieve their SDK configuration. The script does not grant access or create a project.
- For a physical iPhone, sign into your Apple account in **Xcode → Settings → Apple Accounts**. Obtain its **10-character Team ID** from your Apple developer membership or an existing development configuration. This is different from your Apple account email and team display name. Apple signing accounts/certificates are managed by Xcode, not Firebase.

If command-line tools point at Command Line Tools instead of the full Xcode installation, run:

```sh
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
xcodebuild -version
```

## 2. Clone and install the pinned Firebase CLI

```sh
git clone https://github.com/KENTRUAN/LiftRank.git
cd LiftRank
npm ci --prefix backend
```

Until the setup-script PR is merged, check out `codex/demo-setup-script`; afterward it is available on `main`. Make any code changes on a new `codex/` feature branch.

`npm ci` installs the Firebase CLI version from the lockfile along with the backend's development dependencies. It does not start or deploy a backend. The script prefers `backend/node_modules/.bin/firebase`; it can also use an already installed `firebase` command. No XcodeGen installation is needed to use the committed Xcode project.

## 3. Run setup

For **an iPhone and a simulator**:

```sh
./scripts/setup-demo
```

On first use, the official Firebase CLI opens Google sign-in if no account is signed in. Select the account that has project access. The script lists registered iOS bundle IDs and asks for the physical iPhone bundle ID and Apple Team ID. It reuses those saved choices on later runs.

If your Apple team already uses a registered app, select its matching bundle ID. A teammate using a new bundle ID must first register it in **Firebase Console → liftrank-514018 → Project settings → Your apps → Add app → iOS**. Enter exactly the bundle ID they will sign in Xcode, such as `com.yourname.liftrank.dev`; do not register the Watch/widget identifiers as separate Firebase apps. Firebase registration does not register the identifier with Apple—Xcode's automatic signing handles that separately, subject to your Apple account's permissions. The setup script never creates cloud resources.

For **simulators only**, skip Apple signing questions:

```sh
./scripts/setup-demo --simulator-only
```

For an unattended run after Firebase login, provide the actual values (the examples below are placeholders):

```sh
./scripts/setup-demo --team-id ABC123DE45 --bundle-id com.yourname.liftrank.dev --non-interactive
```

Setup validates the Firebase project/app/bundle IDs, requires the database and bucket settings, and checks the public backend `/health` endpoint. Then it writes:

| Local file | Purpose |
| --- | --- |
| `LiftRank/Resources/SocialConfig.plist` | Simulator app (`com.liftrank.app`) connected to the hosted project |
| `configuration/SocialConfig.device.plist` | Cloud configuration for your registered physical iPhone app |
| `configuration/Signing.local.xcconfig` | Apple team and device-only app/Watch/test bundle settings |

All three paths stay ignored by Git. Simulator-only setup leaves the device/signing files untouched. The helper reads the simulator bundle ID from `configuration/Build.xcconfig`. It does not download Apple certificates or copy server secrets into the app. Generated files use owner-only permissions, and configuration values are not printed.

## 4. Open and run

```sh
open LiftRank.xcodeproj
```

Wait for Xcode to resolve Firebase Swift packages. Choose the **LiftRank** scheme and an iPhone simulator, then **Product → Run**. Use normal Xcode Run for interactive Firebase sign-in; the unsigned CI build is intended for unit tests and cannot persist simulator guest credentials in Keychain.

For your physical phone, connect and unlock it, trust the Mac, and enable **Settings → Privacy & Security → Developer Mode** if prompted. Choose the iPhone as Xcode's run destination and press Run. If iOS reports an untrusted developer, use **Settings → General → VPN & Device Management** to trust the developer account. The local signing settings cover the app, embedded Watch app and Live Activity; keep automatic signing enabled. See [Apple's device setup](https://developer.apple.com/documentation/xcode/running-your-app-on-simulated-or-physical-devices).

Allow Health permissions when demonstrating Apple workout saving, Location for the outdoor minimap, and Live Activities for Lock Screen/Dynamic Island controls. An actual paired Watch is needed to rehearse Watch sensors. The new simulator starts with a new guest and local workout history; setup does not migrate existing user data.

## 5. Rehearse with two identities

1. Run LiftRank on the simulator and iPhone (or two separate simulators). Both need internet access; they do not need to share a Wi-Fi network when using the hosted backend.
2. On each, open **Community**, choose a different nickname, complete sharing setup and use **Public** mode.
3. Enter **Demo Gym**, not the offline sample. Verify both avatars appear and movement is visible.
4. Send/accept a friend request, exchange a private message, and try an equipment work-in request.
5. Start/end a strength set and confirm weight/reps. Finish that workout before starting cardio; demonstrate Pause/Resume and the locked-screen timer on the phone.
6. In Messages, ask **AI trainer** to add an exercise to a blank strength workout. This uses the server's Tinker model and its normal request quota.

The setup health check proves only API reachability. It does not validate multiplayer permissions, sign-in, paid AI calls, device provisioning or Watch sensors; rehearse those explicitly.

## Refresh and troubleshooting

Run setup again after changes to Firebase configuration or your signing identity. Identical files are left untouched. Changed existing files require confirmation; unattended runs must supply `--replace`. File validation, downloads and the health check finish before any configuration is written. A write failure restores prior file contents where possible.

```sh
# Fetch/validate both configurations using saved signing choices, without writing them:
./scripts/setup-demo --check

# Check just the simulator on a fresh checkout:
./scripts/setup-demo --simulator-only --check

# Deliberately replace differing settings, including a previous emulator configuration:
./scripts/setup-demo --replace
```

`--check` may still initiate Firebase login in interactive mode; it never writes the three setup files. Add `--non-interactive` to require an existing login and avoid prompts. `--api-url https://...` explicitly selects a replacement HTTPS backend endpoint if the hosted service moves; it must serve the same Firebase development project. The default endpoint is `https://liftrank-social-937516211756.us-central1.run.app`.

| Problem | Next step |
| --- | --- |
| Firebase sign-in expired | Run `backend/node_modules/.bin/firebase login --reauth`, then rerun setup. |
| Wrong Google account / access denied | Use `backend/node_modules/.bin/firebase login:add` and `login:use EMAIL`, then ask the project owner to verify access. |
| Bundle ID not registered | Register that exact iOS bundle ID in the existing Firebase project, or select the correct existing one. |
| Missing database/bucket configuration | Ask the project owner to check the Firebase project's Realtime Database and Storage setup. The script does not guess their names. |
| `/health` fails | Check internet access and the API URL; ask the maintainer to check Cloud Run. Existing setup files remain intact. |
| Python certificate verification failure | Repair the Python installation's trusted certificates (python.org macOS installers include `Install Certificates.command`); do not disable TLS checks. |
| Xcode signing error | Verify your Apple account/team, bundle ID, connected device and automatic signing for app/Watch/widget targets. |
| Only offline sample appears | Rerun setup, rebuild the app, and check the correct simulator/device configuration was generated. |
| Trainer or generated-avatar error | Check the separate provider setup and quota; the setup helper does not configure or test those providers. |

Tinker workout AI is configured on the server. Generated gym avatars/introduction drafts require a separate backend Gemini credential; nutrition, meal analysis and other general AI use separate `Config/AI.local.xcconfig` settings. Those optional features are not enabled by this script. Preset avatars and manual social messages work without them. See [AI setup and checkpoint expiry](AI_SETUP.md).

Firebase retrieval uses the documented [`apps:list` and `apps:sdkconfig` commands](https://firebase.google.com/docs/cli). To validate the setup helper locally without any cloud calls:

```sh
python3 -B -m unittest discover -s scripts -p 'test_setup_demo.py' -v
```
