# Equipment interaction and trainer quality

Branch: `codex/equipment-and-trainer-quality`. Main is unchanged.

## Equipment

Select equipment directly in the scene; the dropdown is removed. The current station and **Release equipment** sit above the fixed set controls, so they remain accessible while scrolling. Release is available when no set/cardio is active. **Start set** requires a station already selected in the scene; it never defaults to the bench. Work-in requests and owner approval still use the existing backend rules.

The same reservation and exercise checks apply to the scene, the workout Review picker, and manual set completion. Bench choices are bench presses; pull-ups belong at the rack. Stale/lost reservations cannot start new sets. Already-started sets can still be saved after a disconnect, preserving local workout history. Private/custom open floors continue to allow any strength exercise. Equipment accessibility targets track the camera for VoiceOver and native UI tests.

## Trainer roles

| Responsibility | Model/configuration |
| --- | --- |
| Natural conversation, training advice, daily and multi-week schedules | Full `thinkingmachines/Inkling`, configured with `TINKER_COACH_MODEL` and `TINKER_COACH_EFFORT=medium` |
| Explicit changes to the current remaining workout list | Existing fine-tuned `TINKER_TRAINER_MODEL` checkpoint |
| Home welcome and legacy workout companion | Full coaching model; read-only |
| Social introductions and images | Separate Gemini key, unchanged |

Both workout models use the existing server-side `TINKER_API_KEY`. This does not start another fine-tuning job. The earlier 219-example pilot measured editing-contract correctness; it was not an independent coaching or program-quality benchmark.

The full coach answers ordinary messages as text. Only explicit change requests use a tool. For multi-week plans, it designs complete reusable sessions and one bounded sets/rep progression entry per week. The backend expands these into all requested calendar days, including rest days, and validates every exercise and resulting number. Individual day edits remain separate. This avoids the model shortening later weeks or copying today's single exercise across the whole program.

The fine-tuned editor only receives a focused current-list instruction and the current workout context. Its English boilerplate is not used as the chat reply, and it cannot replace the schedule. Conversation and plan titles follow the user's latest language. No checkpoint/model fallback occurs on failure. Existing local stale-edit checks and immutable recorded sets remain in effect.

Each provider attempt counts against the existing guest/project trainer quotas. One repair is allowed per stage, at most four total calls for a mixed request. Truncated responses, invalid exercises, malformed tool text, incomplete progressions and invalid numbers cannot apply a partial edit. Provider outages leave workouts unchanged. Cloud Run uses a 300-second request timeout and the iOS trainer request allows 330 seconds to cover bounded retries.

## Verification

Passed: `python3 scripts/lint.py --swift`, 22 targeted `GymTests`/`CommunityWorkoutTests`, the native `EquipmentRehearsal`, backend build, 34 backend unit tests and 22 Firebase Emulator rule/API tests. The UI rehearsal selects the bench directly, verifies bench-only choices in both scene and Review, releases it, selects the rack for pull-ups, and verifies release is disabled during an active set.

For opt-in paid synthetic inference checks:

```sh
cd backend
npm run build
cd ..
node --env-file=backend/.env backend/scripts/coach-rehearsal.mjs
```

The script caps itself at five model attempts and checks the reported regression: `帮我制定一个四周的力量训练日程，保持我当前的训练不变。` It verifies a Chinese 28-day plan, complete sessions, rest days, movement variety and an unchanged active pull-up workout. It also checks a read-only question and a focused edit that preserves existing todos. Optional `LIFTRANK_REHEARSAL_PLAN_ONLY=1` limits the run to the planning case and at most two attempts. These use synthetic data and never modify a real workout.

The verified full-model planning result contained 28 days, three sessions per week, five exercises per session and weekly progression. This is a targeted regression result, not a guarantee that every generated training plan will be suitable for every user.

## Development deployment

Deployed on November 8, 2026 (UTC), to `liftrank-514018`, Cloud Run `liftrank-social`, revision `liftrank-social-00014-wrq`, serving 100% of development traffic. Existing service identity, secret bindings, fine-tuned checkpoint, quotas and instance limits were preserved. Database rules were unchanged.

The hosted smoke rehearsal passed room authentication/presence, friend/private-chat privacy, work-in approval, exclusive cardio, anonymous profiles, proximity rejection, public/private spaces, invitations, host succession, blocking and cleanup. A live read-only Home greeting verified the deployed full-model route. The iOS equipment changes require rebuilding the app from this branch; the simulator rehearsal does not install the update on a physical phone.

Provider reference: [Tinker Anthropic-compatible API](https://tinker-docs.thinkingmachines.ai/tinker/compatible-apis/anthropic/) documents optional tools and reasoning effort. [Published model rates](https://tinker-docs.thinkingmachines.ai/tinker/models.json) were checked for the bounded development inference runs. Backend secrets and raw synthetic evaluation reports remain outside Git.
