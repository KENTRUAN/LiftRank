# Nearby workout spaces

Implemented on `codex/nearby-workout-spaces`; main is unchanged.

## Experience

- Home has a short trainer welcome and one **Start workout / Continue workout** button. Home, Profile, routine starts and external start actions route through Community. Cardio uses the same space selection.
- Home's **Today** section appears only when today's requested plan contains exercises. Tapping it opens a read-only list of exercises, sets, rep ranges and rest times. It never opens trainer chat, workout setup or starts a session; trainer chat has its own entry.
- Select a registered gym within 500 meters, create a public/private space, join an approved nearby space, or start a private solo workout offline. Entering starts or resumes the same local workout. Choosing a preset remains a separate optional step.
- Custom spaces are open floors with avatars and a private trainer. **Start set** selects any strength exercise. The **Cardio** shortcut beside the set controls retains automatic timing, pause/resume, the outdoor map and Apple Health/Watch handling. Recorded sets remain locked.
- Pinch to zoom from 0.8× to 3×; drag with two fingers to pan. There are also zoom/reset buttons and an option for a taller viewport. One-finger taps still walk or open profiles/equipment. Camera changes never send movement.
- Registered gyms are always public. Public custom spaces require a join request. Any current member may approve or decline. The host manages visibility and invitations to accepted friends. If the host leaves, the longest-present remaining member becomes host.
- Private spaces are hidden from discovery. Invited friends must still pass proximity validation. Going private cancels pending public requests and unused public approvals; current members stay.
- Invitations appear in the gym lobby and Community Messages, with a tab badge. In-room requests appear above the scene. Invitations expire after five minutes; requests and approvals after two minutes.
- The last member leaving ends the space. Abrupt disconnects may leave it listed until the 90-second lease expires; presence hides after 45 seconds. Expired spaces and their location centers are deleted on subsequent API access. Backgrounding removes online presence without stopping the workout timer. Device-only solo spaces stay open while backgrounded.

## Registered gyms

The default preset is **Duke Wilson Recreation Center, 330 Towerview Road, Durham, NC 27708** (`registered-duke-wilson`). The address comes from [Duke Recreation](https://recreation.duke.edu/wilson-recreation-center/); the on-site coordinate (35.997085, -78.940951) comes from [Duke OIT](https://eprint.oit.duke.edu/printers/1178), verified November 7, 2026. The scene is a stylized preset, not Wilson's actual floor plan.

To replace the default registry, point `REGISTERED_GYMS_FILE` at a server-readable JSON file:

```json
[{"id":"duke-wilson","name":"Duke Wilson Recreation Center","address":"330 Towerview Road, Durham, NC 27708","latitude":35.997085,"longitude":-78.940951}]
```

Package an override file in the Cloud Run image if using it there. No Maps/Places key is needed for presets or custom spaces. Existing Places routes remain available for a future directory integration. Demo Gym is separate and still supports multiplayer from anywhere.

## Authenticated API

| Route | Purpose |
| --- | --- |
| `POST /spaces/nearby` | Fresh location → registered gyms and public spaces within 500 m |
| `POST /spaces/create` | Create a space and atomically join it |
| `POST /spaces/inbox` | Own invitations/status, requests for the current room, current space metadata |
| `POST /spaces/:id/request` | Request admission with a fresh nearby location |
| `POST /spaces/:id/respond` | A current member accepts/declines a pending request |
| `POST /spaces/:id/invite` | Host invites an accepted friend |
| `POST /spaces/:id/cancel` | Withdraw one's request or dismiss one's invitation |
| `POST /spaces/:id/visibility` | Host changes custom-space visibility |
| `POST /rooms/join`, `/renew`, `/leave` | Admission, renewal and cleanup for all room types |
| `POST /trainer/greeting` | Read-only training welcome; never applies todos or schedules |

Admission data now lives in **`world/access/memberships` and `world/access/spaces`**. Transactions over `world/access` make capacity, grants, membership, host succession and space closure atomic. Five-Hz movement remains under `world/rooms`, outside those transactions.

Space coordinates and grants are server-only. Custom-space summaries omit coordinates and identity IDs and round distance to 50-meter increments. Raw check-in samples are not retained. Workouts and body measurements remain local. One identity can occupy one room, with ten members maximum per room.

Location must be no older than 60 seconds, report accuracy within 100 meters, and be within 500 meters. Proximity is checked again when redeeming an approval or invitation. Blocking prevents discovery, requests and admission involving a blocked member. Private invitations require an accepted friendship both when issued and redeemed.

## AI keys and limits

Home welcomes use the existing **`TINKER_API_KEY`** and configurable **`TINKER_TRAINER_MODEL`**, including the fine-tuned workout checkpoint. The supplied context contains local date/language, activity/state/completed-set count, and the explicitly requested plan's title/count. The trainer response is validated, and only reply text returns to the client. It cannot silently add a plan or change a workout.

Home refreshes on appearance/foreground, coalesced within ten seconds. The limit is 20 greetings per guest/day and **`GREETING_GLOBAL_LIMIT=200`** project-wide; calls also count against the existing 30/day trainer budget. Errors preserve the last welcome (or a built-in message) with a retry control. AI never blocks starting a workout. Generic images and introduction tools still use their separate Gemini key.

## Rollout

Deploy this branch's **backend and database rules together** before running shared spaces against the hosted project. Membership moved from `world/memberships`; existing online users must re-enter after rollout. Firebase identities, profiles, messages and local workout records remain intact. Do not deploy new rules alone while the older backend is serving.

Deployed to development project **`liftrank-514018`** on November 7, 2026: Cloud Run **`liftrank-social-00013-bpk`**, serving 100% of traffic, with the matching Realtime Database rules. Existing environment settings, secret references, runtime service account and two-instance limit were preserved. The iOS screens require building this feature branch; deploying the backend does not update installed apps.

For local verification use the emulator configuration from `configuration/SocialConfig.emulator.example.plist`. In Simulator, set **Features → Location → Custom Location** to `35.997085, -78.940951`. Use distinct simulator installations/guest identities for multiplayer. Keep emulator files out of hosted/release builds.

Rehearse these flows:

1. Home → Start workout → Wilson; distant/stale/inaccurate check-ins fail.
2. Create a public space; another nearby device requests entry; accept within the scene. Walk, open profiles, add friends and chat.
3. Make the space private. A third device cannot discover/enter it. Invite a friend; a distant friend cannot redeem the invitation.
4. Creator leaves while others continue. Remaining members approve requests. Last member leaves and the space disappears. Check background/reconnect and ten-person capacity.
5. Start an offline solo space, pinch/pan, log a set, start outdoor cardio, pause/background/resume and finish. Verify existing history remains.
6. Check Home welcome success and AI outage/quota fallback; no plan is created automatically.

Checks: `python3 scripts/lint.py --swift`, the `LiftRank` XCTest scheme, backend `npm run build && npm test`, `npm run test:rules`, `npm run test:integration`, and the opt-in native `WorkoutSpaceRehearsal` UI suite. Provider tests use mocks and spend no API credits. Simulator/emulator coverage does not replace a physical proximity/Watch rehearsal.

Verified November 7, 2026: repository lint/Swift syntax, all 50 iOS unit tests, 23 backend unit tests, 10 Firebase rule tests and 12 authenticated emulator integration tests passed. The native private-space test covered pinch zoom, free-choice set logging, cardio, pause/background/resume and final cleanup. Paired native simulator tests covered creating/discovering a public space at Wilson, requesting/approving entry inside the scene, two live members, and the guest remaining after the creator left. No live AI inference was needed for these checks.

After deployment, `python3 backend/scripts/cloud-smoke.py --greeting` also passed against the hosted service. Temporary authenticated guests verified shared movement, equipment sharing, anonymous profiles, friendship/private messages, third-user read denial, blocking, Wilson validation, public-space approval, private visibility, host succession, nearby invitations and last-member closure. One live Home welcome request verified the configured workout model. Test accounts and their records were removed. These checks used synthetic coordinates and made no Places or image-generation calls.
