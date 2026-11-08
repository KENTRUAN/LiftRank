# Live social gym setup

See [nearby workout spaces](../docs/GYM_SPACES.md) for the unified workout flow, Wilson preset, private invitations, new APIs and coordinated backend/rules rollout.

See [feature documentation](../docs/FEATURE_BRANCH.md) for the complete implemented behavior and main-integration decisions. [AI APIs and workout fine-tuning](../docs/AI_SETUP.md) lists provider boundaries, required keys, training commands and budget controls.

The iOS client uses Firebase anonymous Auth, Realtime Database and Storage. The TypeScript API runs on Cloud Run; **no VM is needed**. The intended development project is `liftrank-514018`.

For a **new Mac using the already deployed demo**, follow [New Mac setup](../docs/NEW_MAC_SETUP.md): run `npm ci --prefix backend` and `./scripts/setup-demo` from the repository root. This fetches Firebase client configuration and generates ignored local signing settings. It does not deploy anything, start emulators, retrieve provider secrets or require Google Cloud CLI. The cloud-provisioning steps below are for project maintainers, not laptop onboarding.

Without `SocialConfig.plist`, the app opens normally and offers an explicitly labeled offline sample. Cloud configuration is required for real multiplayer. Existing SwiftData workout records and offline rank cards are unchanged.

The development API is deployed at `https://liftrank-social-937516211756.us-central1.run.app`. Its public `/health` route reports readiness; all feature routes require Firebase authentication. This checkout's ignored local app configuration points to that deployment. Provider secrets are held in Secret Manager. The source upload allowlist in `.gcloudignore` excludes local configuration, credentials, tests and dependencies.

For a physical iPhone, `configuration/Build.xcconfig` optionally loads the ignored `configuration/Signing.local.xcconfig`. The setup script generates this file and `configuration/SocialConfig.device.plist` from your Apple Team ID and a registered device bundle ID. Alternatively, copy the adjacent `.example` files and configure them manually. Register a new device bundle ID as another iOS app in the same Firebase project before fetching its configuration. The SDK-conditional settings apply to physical-device builds; simulator identifiers and configuration keep their existing defaults. Run `xcodegen generate` only after changing the project specification; setup does not require project regeneration. Xcode's normal **LiftRank → your iPhone → Run** action then uses the saved local settings.

## Local multiplayer

Use Node 22 and Java 21 (the current Firebase 14 emulator also works with Java 20).

```sh
cd backend
npm ci
cp .env.example .env
npx firebase emulators:start --project demo-liftrank --only auth,database
```

In a second terminal, start the API:

```sh
cd backend
npm run dev
```

From the repository root:

```sh
cp configuration/SocialConfig.emulator.example.plist LiftRank/Resources/SocialConfig.plist
xcodegen generate
```

Run two iOS simulators. In each, open **Community**, choose a different nickname, accept profile sharing once, create a guest profile and enter **live Demo Gym**. Returning guests restore their approved profile without another setup prompt. Use Community settings to edit it. Anonymous accounts persist per simulator. For two physical phones on the same Wi-Fi, replace both `127.0.0.1` values in the plist with the Mac's LAN IP. The emulator configuration is development-only; never ship it. Both services listen on local network interfaces for this test.

Use a signed simulator build for interactive Firebase login: normal Xcode Run, or `xcodebuild build ... CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-`. The unsigned CI build can run unit tests but cannot persist Firebase guest credentials in the simulator Keychain. Debug launches may set `LIFTRANK_DEMO=1`, `LIFTRANK_GYM=live`, and `LIFTRANK_GYM_NAME=Jordan` to enter the emulator Demo Gym automatically; this shortcut only works when an emulator host is configured. `LIFTRANK_GYM=sample` opens the offline sample.

Prefer the installed iOS 18.2 runtime for live simulator rehearsals. Apple's [iOS 18.4 simulator HTTP/3 regression](https://developer.apple.com/forums/thread/777999) can cause requests to work on the first launch and fail after reopening. LiftRank's API uses an ephemeral URL session, which avoids persistent private-response caches and this failure in its own requests; third-party SDK sessions remain controlled by their SDKs. Do not weaken TLS settings to work around simulator behavior.

Presets, room movement, profiles, friend requests, private messages, room chat, blocking and reports work locally. Places, image generation and Tinker need live provider credentials. Generic images and social drafts require a separate `GEMINI_API_KEY`; without it, presets and manual messages remain available. Source selfies are never written to the database or Storage.

## Google Cloud / Firebase setup

1. Sign into Firebase CLI (`npx firebase login`) and Google Cloud CLI (`gcloud auth login`). Confirm access to `liftrank-514018`. If it is only a GCP project, add Firebase in the Firebase console.
2. Verify billing and hackathon-credit eligibility for Firebase/Cloud Run and Gemini Developer API and **Google Maps Platform separately**. Enable Cloud Run, Cloud Build, Artifact Registry, Secret Manager and Places API (New); enable Gemini Developer API separately when supplying its key.
3. In Firebase Authentication, enable **Anonymous** sign-in. Create a Realtime Database in locked mode and a Storage bucket. Record their actual URL/name. Register an iOS app with bundle ID `com.liftrank.app` and obtain its Firebase configuration.
4. Create a dedicated runtime service account named `liftrank-social`. Grant `roles/firebasedatabase.admin` on this development project, and `roles/storage.objectAdmin` on the avatar bucket. Cloud Run uses this account's application-default credentials; do not download service-account private keys.
5. Create Secret Manager secrets `liftrank-places-key` and `liftrank-tinker-key`, populate them using the consoles, and grant the runtime service account Secret Accessor on those two secrets. Restrict the Maps key to Places API (New). Set API quotas in the provider consoles.
6. Deploy the included access rules from this directory:

```sh
npx firebase deploy --project liftrank-514018 --only database,storage
```

7. Deploy the API, substituting the database URL and bucket actually created above:

```sh
gcloud run deploy liftrank-social \
  --project liftrank-514018 \
  --region us-central1 \
  --source . \
  --service-account liftrank-social@liftrank-514018.iam.gserviceaccount.com \
  --allow-unauthenticated \
  --max-instances 2 \
  --memory 512Mi \
  --timeout 180 \
  --set-env-vars 'GOOGLE_CLOUD_PROJECT=liftrank-514018,FIREBASE_DATABASE_URL=YOUR_DATABASE_URL,FIREBASE_STORAGE_BUCKET=YOUR_BUCKET,AVATAR_GLOBAL_LIMIT=30,COMPANION_GLOBAL_LIMIT=300,SEARCH_GLOBAL_LIMIT=2000' \
  --set-secrets 'GOOGLE_PLACES_API_KEY=liftrank-places-key:latest,TINKER_API_KEY=liftrank-tinker-key:latest'
```

The Cloud Run endpoint accepts public HTTPS connections, but every route except `/health` verifies a Firebase ID token. Only server operations mutate profiles, memberships, friendship state, messages, reports and quotas. Realtime rules allow clients to write their own bounded virtual position under an active membership.

8. Copy `configuration/SocialConfig.cloud.example.plist` to `LiftRank/Resources/SocialConfig.plist`. Fill in the Cloud Run URL and values from Firebase's `GoogleService-Info.plist`: `API_KEY`, `GOOGLE_APP_ID` → `APP_ID`, `GCM_SENDER_ID` → `SENDER_ID`, `DATABASE_URL`, and `STORAGE_BUCKET`. Do not include `EMULATOR_HOST`. Run `xcodegen generate` again. These local configuration files are ignored by Git.
9. Before inviting public users, supply your published Terms and Privacy links covering the selected providers, review reports in the restricted `reports` node, and validate actual project quotas. This prototype targets an invited hackathon group; guest identity and client-supplied GPS are not account recovery or anti-spoofing systems.

## Behavior and data boundaries

- The current app offers one shared preset Demo Gym, plus a separately labeled offline sample. No location permission is needed for this flow. Places routes and real-gym check-in validation remain implemented for future discovery; gym scanning is not implemented.
- Live gym entry starts/resumes the existing unpublished SwiftData workout; tab switches, re-entry and backgrounding do not create another workout. Starting always creates a blank session, followed by a separate optional preset choice. Start set / End set drives automatic Training / Resting state; confirmed weight/reps fills planned strength sets or appends extra sets. Only confirming a strength set records it. Cardio uses a separate activity timer, started from a gym cardio machine or the Cardio tab. End saves exact elapsed seconds to one immutable cardio record, without a manual duration form or strength controls. Switching an existing strength workout to cardio requires finishing it first; an empty gym draft converts without creating a duplicate session. Leaving preserves the unfinished workout; publishing uses the existing scoring/reward pipeline. The offline sample does not create workout records.
- Community is a main tab with Gym and persistent Messages sections. In-room incoming requests, private-message banners and the Inbox sheet keep social actions inside the room. Latest-message listeners exist only for accepted friendships and are removed on revocation. Read markers are stored locally per Firebase guest. Profile sharing is asked once, and later editing is explicit in Profile/Community settings.
- Initial real-gym check-in: client location ≤60 seconds old, accuracy ≤100 m, distance ≤500 m, verified by the server against fresh Places details. No background GPS or coordinates in presence payloads. The location is a check-in gate, not proof against a modified client.
- One room per identity, at most 10 leased members per room. Membership expires after 90 seconds; foreground clients renew every 15 seconds. Scene avatars older than 45 seconds disappear. Returning from background or a lost connection requires a new check-in.
- Movement uses a 12×10 virtual grid, updates at most 5 Hz while moving, and interpolates on receiving clients. Stations are virtual equipment reservations, not physical bookings. Lifting stations allow one owner and one explicitly accepted work-in/training partner; cardio allows one member. Reservations survive rest and release on switching, leaving or disconnecting. Stale reservations are pruned by the next server mutation; clients hide stale occupants immediately.
- Friend requests require both identities to have fresh presence matching unexpired memberships in the same room; arbitrary account IDs cannot bypass this gate. Existing offline rank cards are read-only, with no code-based adding. Private chat requires mutual acceptance. Blocking or removing a friend revokes the chat and deletes its server history. Private histories retain the newest 200 messages; room chat retains 50. Muting is local to the guest account. Reports are server-only and retain the reported message for review.
- Profiles include nickname, interests, approved avatar and selected rank/cosmetics. Explicit activity opt-in adds bounded recent workout summaries, seven-day muscle scores and six monthly activity totals; individually selected public routines expose planned sets/reps. The server strips nested measurements, actual weights/reps and notes. Public profiles can be read by their owner, active gym peers or existing connections; blocks override access. Anonymous mode is separate from activity sharing: the server assigns a new room alias, the client renders a generic avatar, profile reads by others and new friend requests/acceptances are denied. Existing conversations remain available. The AI trainer receives the exercise catalog, remaining todo counts/reps/rest, completed exercise counts, explicitly requested schedule and goal only on an explicit chat send; introduction generation receives only public profile interests.
- Trainer conversations persist locally and appear as a recipient in Messages as well as Home and the room. Structured replies may replace remaining todos or create/update/delete requested calendar days. Tinker replies use a forced tool with an explicit keep/replace/clear action, distinguishing ordinary conversation from todo deletion. Numeric strings are normalized and every set is validated. One bounded repair attempt may correct an invalid response; each provider attempt consumes quota. Validation occurs before changes; a changed or in-progress workout rejects stale edits. Cardio conversations cannot add strength todos or alter the timer. Recorded sets cannot be changed or deleted. A free-form workout has no checklist, and Home has no Today section without an explicitly requested AI plan.
- Outdoor cardio has a private MapKit minimap with a local route. Location updates run only while the app is in the foreground; background/locked-screen route recording and HealthKit route export are not implemented. Location denial leaves workout timing usable. These route coordinates are never included in social snapshots or trainer context.
- Image previews are returned to the device; only approval writes an avatar to Storage. Selfies are processed in request memory. Replacing an approved image deletes its prior asset. Image assets are readable to authenticated app members; request photos are not.
- Daily limits: 3 image generations / guest, 30 trainer attempts / guest and 30 generic-text attempts / guest. Project-wide defaults: 30 images, 300 trainer calls, 300 generic text calls and 2,000 Places requests. Failed provider attempts consume quota to prevent retry storms. Server limits reject requests; billing alerts alone are not hard caps. Guest identities can be recreated, so project-wide limits remain necessary.
- Tinker and Gemini model IDs are separate server environment settings. Workout inference supports an evaluated `tinker://.../sampler_weights/...` checkpoint through the Anthropic-compatible API. Generic introduction drafts and avatar previews use your separate Gemini Developer API key; see [AI setup](../docs/AI_SETUP.md).
- Persist only Google Place IDs. Names, addresses and locations are fetched live and displayed with Google Maps and returned provider attribution. The room drawing is LiftRank's own design.

## Validation

```sh
npm run build
npm test
npm run test:rules
npm run test:integration
```

Run emulator commands sequentially because they use the same ports. Backend integration tests create three distinct authenticated guests, exercise the room and friendship lifecycle, retry messages, and verify unauthorized interactions fail. Rules tests independently attack direct database access.

The integration suite also races eleven admissions and verifies exactly ten distinct spawn positions. Expired returning members cannot bypass capacity.

The iOS unit suite includes shared Home/gym session reuse, planned-set completion, extra sets, kg/lb conversion, cardio distance/minutes, invalid-input rejection, existing-record preservation and normal workout publication/rewards. The two-simulator UI rehearsal also exercises the Community tab, in-room Accept & chat, Inbox, unread-message banner, equipment logging, tab switching, background re-entry and profile restoration after relaunch.

For an opt-in cloud rehearsal, run this from the repository root after configuring the cloud plist and signing into gcloud:

```sh
python3 backend/scripts/cloud-smoke.py
```

This creates three temporary guests, checks real database access rules, friendship/private chat, blocking, station updates, Wilson check-in validation and nearby spaces, then deletes its accounts and assets. Space checks cover public requests/approval, private visibility, host succession, nearby friend invitations and last-member closure. Locations are synthetic; this does not replace a physical proximity rehearsal. Default checks make no AI or Places calls. `--greeting` adds one live read-only Home welcome, `--places` adds optional Google Places search, and `--trainer` verifies structured todo edits and a complete week using four trainer requests (validation repairs may consume extra attempts). To test ordinary English/Chinese chat, full-catalog todo edits, deletion and a seven-day plan directly with the configured provider, run `node --env-file=backend/.env backend/scripts/trainer-rehearsal.mjs` from the repository root. This opt-in provider diagnostic uses synthetic context and does not mutate the database; provider usage is billed normally. Run cloud smoke separately from simulator rehearsal because they share the preset gym equipment. `--ai` spends one avatar generation and two companion requests and verifies that introductions stay unsent. Project quota usage remains recorded after cleanup.

From the repository root:

```sh
python3 scripts/lint.py --swift
xcodebuild test -project LiftRank.xcodeproj -scheme LiftRank \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.4' \
  -parallel-testing-enabled NO -test-timeouts-enabled YES \
  -maximum-test-execution-time-allowance 60 \
  -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO
```

For the live rehearsal, use two separate devices/accounts: join the same gym, walk around obstacles, select stations, open each other's profiles, request/accept friendship, exchange messages, disconnect/rejoin, approve a generated avatar and ask the trainer about today's plan. Confirm a third account cannot read the private chat. Check location denial, AI/provider failures and quota errors. Do not describe emulator-only verification as a completed two-phone cloud rehearsal.

An opt-in native UI suite, `LiftRankSocialRehearsal`, performs the two-user flow against the backend configured in the app. It is separate from the regular `LiftRank` scheme so CI cannot accidentally publish profiles or call a live service. Build it with signing enabled:

```sh
xcodebuild build-for-testing -project LiftRank.xcodeproj -scheme LiftRankSocialRehearsal \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.2' \
  -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-
```

Find the generated `LiftRankSocialRehearsal_*.xctestrun` under `build/DerivedData/Build/Products`. In two terminals, run `xcodebuild test-without-building -xctestrun PATH -destination 'platform=iOS Simulator,id=DEVICE_ID' -parallel-testing-enabled NO -only-testing:LiftRankSocialUITests/SocialGymRehearsal/testJordan` and the corresponding `testTaylor` command on a different simulator. Start them together. The suite uses clearly named `QA Jordan` and `QA Taylor` guest profiles and keeps them for repeat runs; use dedicated development simulators. It captures screenshots in each result bundle.

Verified in this development project: live authenticated multiplayer and message privacy, Places search and rejected check-ins, Tinker workout context and unsent introduction drafts, and Gemini generation/approval with prior-avatar preservation on a failed request. Two iOS simulators also exchanged friend requests and private messages, saw each other's station changes, and verified background removal and rejoin through the deployed service. A physical two-phone rehearsal, real-location successful check-in, and team-specific billing-credit eligibility still need validation before the hackathon demo is considered fully rehearsed.

Inspect Cloud Run request error rates/latency without logging bodies or auth headers. Budget caps, report review and account recovery need deliberate expansion before a public launch.

Latest unified-training verification (2026-11-07): 24 iOS XCTest cases passed, including blank starts, optional preset application, set lifecycle, persistence across store reopening and shared-summary privacy. Both live simulator UI tests passed against the deployed backend: shared muscle-map profiles, friend acceptance, private messages, persistent Messages section, visible Start/End controls, Home/gym session reuse, background cleanup and relaunch. Backend verification passed 8 core tests, 7 emulator-rule tests and 4 authenticated integration tests. The iPhone build was installed and launched on the connected development phone; the Watch companion built, installed and opened in watchOS Simulator. Actual paired-Watch sensor collection and Health permission flows still require a hardware rehearsal.

### November 7 interaction update

The current regression suite has 31 iOS unit tests, 12 backend unit tests, 9 database rule tests and 5 emulator API integration tests. The native live rehearsal adds owner-approved work-ins, `testAnonymousAndTrainerInbox` (including a live trainer todo edit), and `testOutdoorBlankWorkout` for the minimap and absent checklist. Trainer context omits completed-only exercises, and failed replies offer an explicit retry without duplicating the user message. Community badges include unread messages, incoming friend requests and work-in requests. Avatar borders/halos use orange for Training and cyan for Resting; a short set-complete label appears after a successful save.

Verified for this update: all 31 iOS unit tests and all 12 backend unit, 9 rule, and 5 emulator integration tests passed. The four native UI scenarios passed across dedicated simulators: Jordan/Taylor multiplayer with work-in approval and chat, anonymous identity with a live trainer edit, and a blank outdoor workout with a rendered minimap. Cloud Run revision `liftrank-social-00006-g7x` serves the updated backend. The signed iPhone build was installed and opened without resetting local records. Actual outdoor route accuracy and live Watch hardware tracking still require a field rehearsal.


### Trainer reliability and automatic cardio timing (2026-11-07)

The trainer now uses a named Tinker tool, explicit keep/replace/clear actions, validation and at most one quota-counted repair. Live full-catalog checks passed for a greeting, a workout question, adding todos, clearing todos and a Chinese seven-day schedule. The deployed authenticated endpoint also passed todo-edit and weekly-schedule checks. AI errors leave the local workout intact.

Cardio starts a separate one-activity timer from the Cardio tab or gym machine. End creates one saved duration record, including partial minutes, and ends Apple tracking. The workout and timer survive minimizing/reopening. A populated strength workout must be finished before switching; empty gym drafts convert in place with a new tracking identifier. Cardio screens have no strength exercise picker, checklist, preset chooser or manual duration input. Timed history is read-only and its training summary is counted once. Outdoor routing remains foreground-only.

Verification: repository lint and Swift syntax checks, 36 iOS unit tests, 14 backend unit tests, 9 database rule tests and 5 emulator API integration tests passed. Three native simulator scenarios passed on the final build: ordinary trainer chat plus a requested todo edit, gym cardio Start/End, and outdoor cardio Start/End with the minimap. Live cloud smoke checks passed for social privacy, equipment ownership, proximity rejection and trainer edits. Cloud Run revision `liftrank-social-00007-pt7` serves this backend. The signed update is installed on the connected development iPhone without resetting its records; launch requires the phone to be unlocked. Actual paired-Watch tracking and outdoor route accuracy still require a hardware/field rehearsal.


### Cardio pause/resume and Live Activities (2026-11-07)

Cardio persists start and pause/resume dates in SwiftData. Its active duration subtracts pauses, including a pause that is still open when End is pressed. Timer rendering uses those dates rather than foreground ticks, so backgrounding, locking and reopening preserve elapsed time. Repeated pause/resume requests are idempotent; recorded cardio remains immutable. Pausing also stops foreground route collection and prevents the distance calculation from bridging a paused interval.

A WidgetKit extension presents the activity and elapsed timer on the Lock Screen and Dynamic Island. Its `LiveActivityIntent` runs in the app process and uses the same saved workout as in-app controls. Updates occur on state transitions, not every second; SwiftUI renders the running clock. The manager restores an existing activity, ends duplicates/finished sessions and respects system/user dismissal. The activity opens the active cardio screen via a scoped URL. iOS limits and user Live Activity settings still apply; the local timer works independently. Outdoor GPS remains foreground-only.

Apple tracking receives pause/resume control on iPhone or Watch. Canonical pause events are added to the Health workout builder when saving cardio, avoiding duplicate automatic pause events and keeping saved duration aligned with local active time. Actual paired-Watch sensor behavior still needs a hardware rehearsal.

Trainer improvements were deferred at the user's request. Messages continue through the existing Tinker integration; no command parser, new provider configuration or cloud deployment is included in this update.

Verified: 40 iOS unit tests passed, including pause/resume, ending while paused, duplicate controls, reopening a persistent store and route-distance exclusions. Native simulator checks passed for gym cardio, paused-state restoration after process termination, timing while backgrounded, Lock Screen presentation via Notification Center, Dynamic Island Pause/Resume and the Open link. The 14 existing backend unit tests also passed after the trainer work was deferred. Repository lint and Swift syntax checks passed; iPhone and embedded Watch/widget builds succeeded. The signed update was installed and launched on the connected iPhone without resetting records. Physical locked-device Health permissions and paired-Watch sensors remain manual hardware checks.


### Dedicated workout AI and separate generic AI (November 7–8, 2026)

The trainer now has its own `TINKER_TRAINER_MODEL` checkpoint setting and an optional fine-tuned-only guard. Generic social introduction drafts and avatar generation require a separate `GEMINI_API_KEY`; neither falls back to Tinker or implicit Vertex service-account access. Introduction requests pass only shared names/interests. Trainer, generic text and image quotas are independent. After integration with main, optional analysis/nutrition/meal-photo/summary and local avatar tools use developer configuration in `Config/AI.xcconfig`. Old Keychain data is not erased. Workout planning remains exclusively on Tinker; general AI nutrition responses cannot contain workout edits.

An actual Inkling-Small LoRA workout model is now deployed with `TINKER_REQUIRE_FINE_TUNED=true`. It trained on 219 synthetic examples and passed all 33 development evaluation cases. Tinker's missing-required-tool error uses the existing single, quota-counted validation repair; repair requests retain older chat turns as context so plain-text history does not suppress the required structured reply. Other provider failures remain explicit and never switch to generic AI.

See [API setup](../docs/AI_SETUP.md) for required credentials and renewal commands, and [training results](training/RESULTS.md) for the current revision, exact checkpoint paths, verification, limitations and spending. The private release expires December 8, 2026 at 00:48 UTC (December 7 at 7:48 PM New York time). The observed Tinker balance decreased from $119.91 to $112.12 after training; the pilot stayed within its stricter $20 reservation ceiling. No paid storage or automatic renewal was enabled. Generic Gemini features remain unconfigured until the team supplies its separate key.
