# LiftRank social gym and unified training

This document describes the feature work carried from `codex/training-ai-provider-boundaries` into `codex/social-gym-main-integration`. It covers the implemented app, backend and AI integration, with prototype limits separated from working behavior. See [backend setup](../backend/README.md), [AI configuration](AI_SETUP.md), and [fine-tuning results](../backend/training/RESULTS.md) for operational details.

## What a user can do

### Community and the gym

- Open Community directly from the bottom bar. The five destinations are Workout, Ranks, Community, Nutrition and Profile. Rewards and cosmetics live in Profile; older Rewards navigation still resolves there.
- Set up a shared nickname, avatar and profile consent once. Returning guests restore their profile. Community settings controls subsequent edits, Public/Anonymous mode and optional activity sharing independently.
- Enter the clearly labeled live Demo Gym with other authenticated guests, or use an explicitly offline sample without cloud configuration. The current gym directory and floor layout are presets. Real-gym Places search and proximity validation exist behind the backend, but are not exposed in the current app flow.
- Walk through a SpriteKit isometric room with obstacle avoidance, depth ordering and interpolated multiplayer avatars. Tap a member for their shared training profile or equipment to use it.
- Reserve strength equipment. Another member can ask to work in or train together, and joins only after the current user accepts. Cardio equipment is exclusive. Disconnects and leaving release occupancy.
- Start/end a set from visible controls. Training uses orange avatar borders; Resting uses cyan. Recording a set briefly displays a completion label. These states follow training activity rather than a manual chat-status dropdown.

### Local social connections

- Friend requests require both people to be present in the same room with fresh memberships. There is no friend-code, QR-code or account-ID adding flow. Demo Gym is the explicit development exception to physical proximity.
- Receive and accept requests, open profiles and chat in sheets inside the gym. Community's Messages section retains friends and conversations after leaving. Tab badges and in-room banners surface unread messages, incoming requests and work-in requests.
- Request, cancel, accept, decline, remove and block friendships. Private messaging unlocks after acceptance. Checked-in members also have basic room text chat, reporting and muting.
- Anonymous mode uses a generic avatar and hides the profile and new-connection actions. Public identity does not require sharing workout activity. Previously stored offline friend/rank cards remain local, read-only snapshots rather than authenticated accounts.
- Shared profiles use the actual rank engine: GSR/rank, cosmetics, interests and station, plus opted-in recent workout memories, seven-day muscle scores, six-month activity, streak and selected public routines. Measurements, set weights, actual reps and private notes are excluded from those public summaries.

### One workout, from Home or the gym

- Starting from Home or entering the live gym creates/resumes one blank SwiftData session. A separate step offers an optional preset and Apple workout settings. The offline sample never creates a workout.
- Blank sessions have no training checklist. A checklist appears after selecting a preset or explicitly asking the trainer to create remaining todos. Home shows a daily plan only when the user requested one, including a requested multi-day schedule.
- Logging at a strength station asks for weight and reps, fills a planned set when applicable, and supports extra sets. Completed sets are immutable. Publication continues through existing scoring, PRs, history and rewards.
- Leaving the room, changing tabs or minimizing the app preserves the workout. Stale trainer replies cannot overwrite a changed session or a running set.

### Cardio and Apple integration

- Indoor, outdoor and gym-machine cardio use a single-activity timer with Start, Pause/Resume and End. There are no strength exercise/preset controls or manual duration fields in this flow.
- Persisted dates and pause intervals determine active duration. The clock survives backgrounding, phone locking and reopening, including a paused state. End saves one duration record and keeps recorded cardio read-only.
- Outdoor cardio has a private MapKit minimap and local route. Route collection is foreground-only; elapsed timing continues in the background. Paused intervals do not create connecting distance jumps.
- A WidgetKit Live Activity shows cardio on the Lock Screen and supported Dynamic Islands. Pause/Resume controls update the same saved session; Open returns to its screen. Availability depends on device and user settings.
- The LiftRank Watch companion can own a live HealthKit workout and mirror metrics/control to iPhone. Without the companion, iOS 26+ supports a live phone workout; iOS 17–25 saves the locally tracked workout when it finishes. LiftRank does not launch Apple's built-in Workout app remotely.
- Stable workout identifiers and import exclusions prevent duplicate local/Health records. Health failures preserve local data and provide retry. Real paired-Watch sensors and outdoor route accuracy still need hardware/field rehearsal.

### AI roles

- The private AI trainer is a persistent Messages recipient and is accessible from training screens. It can answer workout questions, replace/delete remaining todos, and create/update/delete explicitly requested daily or weekly plans.
- Tinker is reserved for workout AI. A real Inkling-Small LoRA model is deployed, trained on 219 synthetic examples and passing 33 development evaluation cases. These are contract/regression checks, not independent coaching-quality validation.
- Replies use a named structured tool, exercise-catalog validation, completed-set protection and one quota-counted repair. The specific missing-tool HTTP 422 response also enters that repair path. Older chat turns become untrusted context on repair so plain-text history does not suppress the structured reply.
- Avatar image previews and editable social introductions use a separate Gemini key. Neither falls back to Tinker. Presets/manual messages remain usable without that key; no introduction sends automatically.
- Main's player portrait/customizable rank figure and the separately approved gym avatar both retain their editors. The private trainer uses main's customizable coach name/appearance, and speech recognition fills an editable message draft. Appearance commands stay in the separate avatar editor.
- General AI keeps body analysis, nutrition, meal-photo recognition and summary commentary. Its four-week nutrition response is validated to exclude workouts and is stored separately. Existing combined/strength programs remain readable, with saved strength days available in optional preset selection. Older general-assistant conversations remain accessible in assistant settings.
- Selfie/text avatar generation supports preview and approval, reusable animated bodies, colors and cosmetics. Only approved assets replace the avatar; source photos are not persisted. The current Gemini adapter remains unconfigured pending a separately supplied key.
- Training artifacts, costs, release model identifiers and the finite checkpoint expiry are documented in [training results](../backend/training/RESULTS.md). Provider credentials never belong in Git or the app's source.

## Code and data map

| Area | Main files | Responsibility |
| --- | --- | --- |
| Navigation and app lifecycle | `LiftRank/App/RootView.swift`, `AppState.swift`, `LiftRankApp.swift` | Main tabs, navigation compatibility, lifecycle services |
| Community UI | `LiftRank/Features/Gym/GymHubView.swift`, `GymRoomView.swift`, `GymSocialViews.swift` | Room, Messages, profiles, requests and sheets |
| Scene and presence | `GymScene.swift`, `GymStore.swift`, `GymModels.swift`, `GymServices.swift` | Scene movement, membership, Firebase subscriptions and API boundaries |
| Shared profile summaries | `GymTrainingProfile.swift`, `GymProfileHighlightsView.swift`, `GymProfileSettingsView.swift` | Consent and restricted publication from local records |
| Strength session | `LiftRank/Engine/WorkoutSession.swift`, `WorkoutPublisher.swift`, `Features/Gym/GymEquipmentSheet.swift` | Canonical session and set lifecycle, station logging, publication |
| Trainer edits | `LiftRank/Engine/TrainerPlanEditor.swift`, `Features/AI/TrainerConversationView.swift` | Local chat, bounded plan edits, stale-reply rejection |
| Cardio | `LiftRank/Engine/CardioWorkoutSession.swift`, `Features/Cardio/TimedCardioWorkoutView.swift`, `OutdoorWorkoutMap.swift` | Durable timer, pauses, recording and private route |
| Apple services | `Features/Workout/TrainingHealthManager.swift`, `LiftRankWatch/`, `LiftRankLiveActivity/`, `Shared/` | Health ownership, Watch bridge, activity clock and intents |
| Backend | `backend/src/server.ts`, `core.ts`, `equipment.ts` | Authenticated room/social mutations, admission, proximity, equipment and quotas |
| AI providers | `backend/src/providers.ts`, `trainer.ts`, `backend/training/` | Provider separation, output validation, synthetic training and evaluation |
| General AI and saved programs | `Features/AI/AIService.swift`, `AIProgram.swift`, `BodyAnalysisView.swift`, `Config/AI.xcconfig` | Developer-configured general AI, nutrition-only generation, legacy program preservation |
| Access control | `backend/database.rules.json`, `storage.rules` | Read boundaries, membership/ownership enforcement, server-only mutations |
| Build and configuration | `project.yml`, `configuration/`, `.github/workflows/ios.yml` | Generated Xcode project, local config templates, native/backend CI |

SwiftData remains the source of local workouts, health records, plans and trainer messages. Firebase anonymous Auth provides cloud identities; Realtime Database holds presence/social data, and Storage holds approved avatar assets. Cloud Run hosts the TypeScript API. No VM is required. Local `Friend` records and `LR1` codes are never cloud credentials.

Movement publishes at most five times per second and shares only virtual coordinates. An identity has one active room. Presence registers disconnect cleanup before publication, leaves on background/exit, hides stale members after 45 seconds and revalidates membership after reconnecting. Real-gym check-in requires a location sampled within 60 seconds, accuracy within 100 meters and distance within 500 meters, validated by the backend. Capacity is ten guests per room.

Backend requests require Firebase identity tokens. Rules and server operations enforce room membership, ownership, friendship and blocking. AI request limits are separate by provider role; multiplayer does not depend on AI availability. See the backend guide for exact quotas, endpoints and secret setup.

## Verification and remaining work

Before main integration, verification passed 40 iOS unit tests, 23 backend unit tests, 9 database-rule tests, 6 emulator API tests, 3 training-budget tests, repository lint and Swift syntax checks. Native simulator rehearsals covered two-person multiplayer/messages, work-in acceptance, privacy, cardio timing/background behavior and Live Activities. The final trainer rehearsal passed with a persisted conversation and a real todo edit. Signed development builds were installed and launched on the connected iPhone without clearing records.

Those historical results do not substitute for checking the rebased code. The integration record below records the exact upstream revision, conflict decisions and fresh verification.

Still outside the prototype: scanned real gym layouts, continuous/background GPS routes, media/voice messages, push notifications, account recovery/cross-device login, an independently validated coaching dataset, physical two-phone rehearsal and real paired-Watch sensor rehearsal. Real Places admission and generic Gemini generation require their configured provider access; current preset-gym interaction remains usable without them. Trainer dictation is text input, not social voice messaging.

## Main integration record

- Fetched upstream main: `c62be48e04162612a893cacbc710b8083534453f`.
- Upstream adds developer-configured general AI, player portraits/customizable rank avatars, and coaching/nutrition context.
- Pre-rebase feature commit: `a3ca352d25e3ca39975e4cee610fc9416c73b549`, retained by `codex/social-gym-before-main-rebase`.
- Local `main` must remain at `166a670e9a83bb447d59b14b0f01f7498e18246f`; no remote push or merge to main is part of this task.
- Confirmed decisions: Tinker is the only workout planner; general AI handles nutrition, analysis and avatar tools. Local player portraits and gym avatars remain separate.
- Preserved upstream rank/scoring and appearance changes, meal photos, body-analysis context and developer configuration. Retained legacy profile configuration fields for existing-store compatibility, without restoring the removed personal-key settings screen.
- Preserved blank starts, explicit preset selection, timer-only cardio, immutable saved sets, Community navigation, presence and proximity-only friendship. General AI nutrition uses a new storage key and rejects workout arrays; old workout programs are not overwritten.
- Regenerated the Xcode project from the combined specification, including Firebase, Watch, Live Activity, signing templates and general AI configuration.
- Fresh checks: **46 iOS unit tests**, **23 backend unit tests**, **9 Firebase rule tests**, **6 emulator API tests**, repository lint, Swift syntax, simulator app/Watch/widget builds and a signed native-rehearsal build passed. Added checks for nutrition/workout isolation and the trainer's 28-day schedule boundary. **Both native UI rehearsals passed**: `testAnonymousAndTrainerInbox` (ordinary chat, actual todo edit, anonymous profile) and `testOutdoorBlankWorkout` (timer, minimap, no strength controls). The backend and cloud model were not redeployed or retrained for this integration.
