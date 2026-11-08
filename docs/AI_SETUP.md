# LiftRank AI APIs and workout fine-tuning

Tinker is reserved for the workout trainer: exercise guidance, remaining-set edits, and requested daily/weekly schedules. Generic social drafts and avatar images use a separate Gemini credential. There is no fallback between the two providers. A system prompt alone is not fine-tuning; a trained model is identified by a saved `tinker://.../sampler_weights/...` checkpoint.

## APIs and credentials

| Feature | API / location in code | Required configuration | Where the credential lives |
| --- | --- | --- | --- |
| Trainer chat and workout edits | Tinker Anthropic-compatible Messages API; `backend/src/providers.ts`, authenticated `POST /trainer` | `TINKER_API_KEY`, `TINKER_TRAINER_MODEL` | Backend environment / private Secret Manager secret |
| Home trainer welcome | Same workout model; authenticated, read-only `POST /trainer/greeting` | Same trainer key/model; `GREETING_GLOBAL_LIMIT` (200/day default) | Backend only; 20 greetings/guest/day, also counted against the 30/day trainer budget |
| Older workout-context companion route | Same Tinker API; `POST /companion` without `targetID` | Same trainer configuration | Backend only |
| Editable social introduction | Gemini Developer API `generateContent`; `POST /companion` with authorized `targetID` | **Your own `GEMINI_API_KEY`**, `GENERAL_AI_MODEL` | Backend only; add later |
| Selfie/text avatar preview | Gemini Developer API image generation; `POST /avatars/generate` | **Your own `GEMINI_API_KEY`**, `AVATAR_MODEL` with image-generation access | Backend only; add later |
| Body analysis, nutrition guidance, meal photos, summaries and local avatar tools | Developer-configured provider in `LiftRank/Features/AI/AIService.swift` | `LIFTRANK_AI_PROVIDER`, `LIFTRANK_AI_MODEL`, `LIFTRANK_AI_BASE_URL`, `LIFTRANK_AI_KEY` in ignored `Config/AI.local.xcconfig` | Use a server relay for provider secrets in distributed builds; these settings do not configure Tinker |
| Future external gym directory | Google Places API (New); `/gyms/search`, `/rooms/join` | `GOOGLE_PLACES_API_KEY` | Backend / Secret Manager; Wilson presets, nearby workout spaces and Demo Gym do not need it |
| Identity, presence, social and approved image storage | Firebase Auth, Realtime Database, Storage | Local `SocialConfig.plist`; server project/database/bucket values and service-account identity | Ignored local app configuration; server uses Cloud Run identity |
| Outdoor minimap and Apple workouts | MapKit, CoreLocation, HealthKit, WatchConnectivity, ActivityKit | Apple capabilities and user permissions | No external AI API key |

Tinker inference endpoint: `https://tinker.thinkingmachines.dev/services/tinker-prod/anthropic/api/v1/messages`. Supply `x-api-key` and `anthropic-version: 2023-06-01`; put the evaluated checkpoint URI in `model`. [Official compatibility documentation](https://tinker-docs.thinkingmachines.ai/tinker/compatible-apis/anthropic/).

Generic AI endpoint: `https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent`, with `x-goog-api-key`. Default text model is configurable as `gemini-2.5-flash`; image model as `gemini-3.1-flash-image`. Confirm access for your key before enabling them. [Text API](https://ai.google.dev/gemini-api/docs/text-generation), [image API](https://ai.google.dev/gemini-api/docs/image-generation).

## Main integration: one workout planner

All workout planning entry points open the private Tinker trainer, including the four-week planning shortcut. Plans use the same `DailyPlan` storage with a 28-day limit. Dictation only fills the message draft; sending remains explicit. Recorded sets and cardio timing remain protected.

Main's developer-configured general AI remains separate for body analysis, nutrition guidance, meal photos, summaries and avatar customization. Nutrition has its own storage key (`ai.program.nutrition.v1`) and a validator that rejects strength/cardio arrays. Existing combined/strength programs and old assistant conversations remain readable; saved strength days can be selected during optional workout setup. They are not overwritten when new nutrition guidance is generated. The older personal-key settings screen is removed, matching main; legacy profile fields and Keychain contents are not erased.

`Config/AI.xcconfig` and its ignored local override configure general AI only. Their values are embedded in the app: use your own relay URL and an appropriate app credential for distributed builds, keeping provider secrets on that relay. Leave the key blank until this service is configured. See `Config/AI.local.example.xcconfig`. Gym image/introduction generation still uses the backend `GEMINI_API_KEY`, separately.

## Configure later

Copy `backend/.env.example` to the ignored `backend/.env` for local use. Do not put provider secrets in Swift, `Info.plist`, Git, screenshots, or example files.

```dotenv
TINKER_API_KEY=<private workout credential>
TINKER_TRAINER_MODEL=tinker://<run>:train:0/sampler_weights/<checkpoint>
TINKER_REQUIRE_FINE_TUNED=true
GEMINI_API_KEY=<your separate Gemini Developer API credential>
GENERAL_AI_MODEL=gemini-2.5-flash
AVATAR_MODEL=gemini-3.1-flash-image
COMPANION_GLOBAL_LIMIT=300
GENERAL_AI_GLOBAL_LIMIT=300
AVATAR_GLOBAL_LIMIT=30
```

Leave `GEMINI_API_KEY` absent until you choose to enable generic AI. Introduction drafts then explain the missing configuration and users can type their own messages. Image generation explains that presets are available; a failed preview never replaces an approved avatar. Multiplayer is independent of AI availability. Gemini no longer implicitly uses the Cloud Run Vertex AI service account.

`TINKER_TRAINER_MODEL` takes precedence over the legacy `TINKER_MODEL`. Without either, the default is the base `thinkingmachines/Inkling`; set `TINKER_REQUIRE_FINE_TUNED=true` when deploying an evaluated checkpoint to reject a missing/base-model configuration. An expired or unavailable checkpoint returns an explicit error and preserves the workout; it does not silently switch providers/models.

For Cloud Run, create a private Gemini secret when the team supplies its key, grant the runtime service account access to that secret, and bind `GEMINI_API_KEY` using `gcloud run services update --update-secrets`. Do not use `--set-env-vars` to transfer a secret. Existing Tinker/Places secrets and Firebase permissions remain separate. Use `--update-env-vars` for the model URI so other configuration is retained.

## Data boundaries and limits

Trainer sends the catalog, remaining sets, completed exercise counts, requested schedule, and supplied goals on explicit chat sends. Training uses synthetic data only; the scripts do not export app conversations, selfies, location, measurements, or private workouts. The pilot teaches the app's editing contract, not medical judgment or validated professional coaching.

Social introductions send only the two public names and shared interests; caller text, workout context and health data are excluded. The draft is returned for user editing and is never automatically sent. Selfies stay in request memory; only an approved generated avatar is stored.

Runtime daily quotas are separate: 30 trainer attempts per guest, 30 generic text attempts per guest, and 3 avatar attempts per guest. Project defaults are 300 trainer, 300 generic text and 30 image attempts. Trainer validation permits one repair request, and both attempts count. Quotas limit request counts, not exact dollar spend. Fine-tuning runs use their own conservative dollar budget and do not use these app quotas.

Tinker's specific HTTP 422 “missing required tool call” failure also uses that single repair allowance. On repair, previous chat turns are retained as untrusted context and the latest user message stays the current instruction. This avoids older plain-text replies causing another unstructured response. Other provider errors are not automatically retried, and no model output bypasses workout validation.

## Reproducible workout pilot

Use Python 3.12 and the pinned dependencies in `backend/training/requirements.txt`. No VM or local GPU is needed. The official SDK submits training to Tinker. [SDK quickstart](https://tinker-docs.thinkingmachines.ai/tinker/quickstart/).

```sh
cd backend
npm run training:dataset
uv venv training/.venv
uv pip install --python training/.venv/bin/python -r training/requirements.txt
training/.venv/bin/python training/run.py
```

The last command is a local preflight, with no training or inference requests. It renders the actual serving system prompt and named-tool schema through Tinker's Inkling renderer, counts all input/target tokens, and reports the planned reservation. The default is `thinkingmachines/Inkling-Small` with the `specialist` dataset: 219 synthetic examples (159 original plus 60 correction/replay examples) and 33 evaluation cases from the actual 75-exercise catalog. Generated JSONL and run artifacts are ignored; the generator and scoring code are reviewable in Git.

The corpus covers explicit and short exercise additions, full-list preservation, changes, deletions, scheduling, rest days, English/Chinese, completed-set protection, unknown exercises, cardio boundaries and unrelated requests. Held-out phrases use distinct inputs. They share the app's contract and exercise vocabulary, so this is a narrow regression benchmark, not an independent general fitness benchmark.

Before **each paid run**, recheck and update `PRICEBOOK` / `RATES_CHECKED_ON` in the runner, then check the correct organization's remaining balance and current [machine-readable rates](https://tinker-docs.thinkingmachines.ai/tinker/models.json). Recheck free storage and auto-reload settings in [Tinker Billing](https://tinker.thinkingmachines.ai/billing/balance). Never infer spendable credit from gross usage alone. The initial authorized budget is the lower of $120 and available credit; this pilot deliberately caps itself at $20 and requires $1 of unallocated credit. The deployed pilot is already trained: these commands are for a deliberate future run, not a required setup step.

The runner has no automatic inference retry, reserves two times the published cost before each batch/request, rejects oversized inputs, limits outputs to 6,000 tokens, refuses an existing run directory, and saves both sampler and resumable training checkpoints with seven-day TTLs. Defaults: two epochs, rank-16 LoRA, learning rate `1e-4`, batch size 8, seed 91; no unembedding training. `--model`, `--dataset`, and `--seed` allow explicit experiments. Do not start simultaneous runs against the same budget, and subtract prior run reservations before choosing a replacement run's cap. SDK retries use the SDK's request identity; inspect the console after interruptions before starting any replacement run.

```sh
# Only after checking the current balance and rates; values below are placeholders.
training/.venv/bin/python training/run.py --execute --budget 20 \
  --verified-balance <current-credit-usd> --balance-date <current-UTC-date> \
  --run <unique-run-name>
```

The runner evaluates the base model and checkpoint against the same 33 cases through the **actual Anthropic endpoint**, validates tool arguments with the production validator, and checks edit semantics. These include iOS request flags, multi-turn history, no active workout, and changed completed-set facts. A candidate is eligible for an app rehearsal only if it passes all cases and does not regress against baseline. Keep completed-set protections and client stale-edit validation enabled regardless of model score. Never deploy a failed candidate just because training completed.

Before promoting, run the authenticated `/trainer` smoke test and the app's trainer-edit tests. Save the report, checkpoint URI, expiry, observed balance/usage and baseline/candidate scores. `refine.py`, `rehearse.py`, `fresh_check.py`, and `final_check.py` preserve the original pilot's evaluation procedure; use `run.py` for a new run because it incorporates all 33 checks without depending on historical local run folders.

## Release checkpoint lifetime

The deployed pilot has **private 30-day release copies**, expiring **December 8, 2026 at 00:48 UTC** (December 7 at 7:48 PM New York time). Experimental originals expire after seven days. See [pilot results](../backend/training/RESULTS.md) for the exact inference and training-state paths. No automatic renewal or paid storage upgrade is enabled.

Before expiry, check remaining credit and free storage, then deliberately retain a finite-duration checkpoint using the official SDK's `RestClient.copy_weights(path, destination_project_id, ttl_seconds=2592000).result()`. Use the returned **sampler** URI in `TINKER_TRAINER_MODEL` and update Cloud Run with `--update-env-vars`; verify an authenticated trainer request. A copy receives a new URI, so leaving the old environment variable unchanged will still cause expiry failures. Keep a separate **`weights/` training-state** copy if further fine-tuning is planned: a `sampler_weights/` checkpoint supports inference, not resuming optimizer state. A copied run itself cannot be trained; initialize a new training client from its saved training weights. [Checkpoint documentation](https://tinker-docs.thinkingmachines.ai/tinker/howto/checkpoints/).

See [pilot results](../backend/training/RESULTS.md) for the current run status, scores, cost and deployment decision.
