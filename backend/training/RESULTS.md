# Workout trainer pilot — November 7–8, 2026

A real LoRA fine-tune of **`thinkingmachines/Inkling-Small` is deployed** to the LiftRank development backend. Tinker handles workout coaching, remaining-set edits and requested schedules. Generic introductions and avatar images require a separate Gemini API key and never fall back to this workout model.

## Evaluation and training

| Candidate / check | Result | Decision |
| --- | --- | --- |
| Original Inkling baseline | 15/20 primary cases | Short additions and schedules needed improvement |
| First completed Inkling fine-tune | 20/20 primary; 4/6 additional app cases | Rejected; cardio and read-only follow-up failures |
| Final Inkling-Small baseline, with final serving prompt | 18/20 primary cases | Comparison for the released model |
| Final Inkling-Small fine-tune | **33/33**: 20 primary, 6 app-shaped, 7 fresh cases | Passed the release evaluation |

The final model trained on **219 synthetic examples**, including 60 correction/replay examples, drawn from LiftRank's actual 75-exercise catalog. Training used two epochs, rank-16 LoRA, learning rate `1e-4`, batch size 8, seed 91 and no unembedding training: **1,325,296 training tokens**. No personal app conversations, workouts, measurements, selfies or location were used for fine-tuning.

Checks cover “add deadlift,” “add pull up,” adding both, full remaining-list preservation, explicit numbers, deletion, completed-set protection, read-only questions, prior conversation, cardio edit prohibitions, today/week schedules and requests without an active workout. Fresh checks changed recorded exercise facts to detect memorized answers. Production validation additionally rejects current-list edits when no editable strength session exists. A scoped serving instruction supplies editable default sets/reps/rest only for short additions with no active session, creating today's draft schedule.

These are development regression checks, and several cases informed corrections and prompt changes. They are not an independent fitness-quality benchmark or clinical validation. Passing them does not guarantee every future request will succeed. Invalid replies preserve local records and show an explicit retry state; recorded sets remain immutable.

## Credit and spending

The user authorized at most the lower of **$120 and remaining credit**. Before starting, the matching Tinker organization showed **$119.91**, auto-reload off, $0 due and the free 100 GB / 100-checkpoint storage plan. The entire pilot deliberately used a **$20 conservative reservation ceiling**.

The latest observed balance after training and release checks was **$112.12**, a **$7.79 decrease**, with **$0 due**. Billing can post later, so this is an observed balance change rather than a final invoice. Free storage remained selected, using **44 GB and 5 checkpoints**. No credit purchase, auto-reload, paid storage plan or indefinite retention was enabled. Firebase/Cloud Run and later Gemini/Places billing are separate from this Tinker balance. [Tinker Billing](https://tinker.thinkingmachines.ai/billing/balance).

At the checked rates, completed training alone is approximately **$5.2851** for the rejected Inkling model and **$2.2928** for the released Small model. Evaluation adds inference usage. The first stopped Inkling session submitted one 23,808-token batch; its uncertain charge remains reserved rather than assumed free. A later attempt to resume a sampler checkpoint was rejected before training; the final run instead started from Small and saved a resumable training-state checkpoint too. [Official rates](https://tinker-docs.thinkingmachines.ai/tinker/models.json).

The combined local ledgers retain **$19.335** in conservative reservations, including twice the published training price, uncertain/error calls and a bounded allowance for live app verification. Reservations are not charges. Unused evaluation reservation was released only with complete provider token receipts, still charging input at twice the uncached rate. No further training is running.

## Deployed release

- Development project: `liftrank-514018`.
- Cloud Run: `liftrank-social`, `us-central1`, revision **`liftrank-social-00012-6ww`**.
- `TINKER_REQUIRE_FINE_TUNED=true`; no silent fallback to a base model or another provider.
- Private inference checkpoint: `tinker://da628ca0-b8c1-5c95-bca8-bc087927fa97:train:0/sampler_weights/workout-v2`.
- Private resumable training state: `tinker://61ad4c1d-0d2c-5685-916e-71ad8108c768:train:0/weights/workout-v2`.
- Expiry: **2026-12-08 00:48:51 UTC** for inference, one second later for training state; **December 7, 7:48 PM New York time**.

The release copies retain the same evaluated weights for 30 days. Renew deliberately before expiry and update the deployed model URI; there is no automatic renewal. Experimental originals retain seven-day TTLs. [Renewal and API setup](../../docs/AI_SETUP.md).

## Application verification

Passed: 40 iOS XCTest cases, 23 backend unit tests, 6 Firebase Emulator API integration tests, 9 database-rule tests, 3 training-budget tests, repository lint and Swift syntax checks. The settings update built, installed and launched on the development iPhone without resetting local records.

Authenticated cloud smoke checks passed short deadlift/pull-up additions, preservation of remaining todos, weekly scheduling, generic-key error states, social privacy, equipment ownership, proximity rejection and cleanup. The fine-tuned model also answered the older workout-context companion route as ordinary text. The release-copy API accepted synthetic histories starting with an assistant turn or containing consecutive user turns.

Native rehearsal exposed Tinker returning HTTP 422 because a long persisted conversation produced no required tool call. The prior reply and workout remained intact with Retry available. The provider adapter now routes this specific error through the existing single validation repair, preserving historical turns as context on the retry. A production-path replay of the synthetic simulator conversation passed in two attempts; unit coverage verifies both attempts count against quota and unrelated provider errors are not retried. The final native `testAnonymousAndTrainerInbox` rehearsal **passed** against revision `liftrank-social-00012-6ww`: ordinary greeting, actual remaining-todo edit, anonymous profile protection and restoration to public mode. The dedicated simulator retained its existing conversation and records throughout the fix.

Private raw responses, token receipts, dataset snapshots and budget ledgers live under ignored `backend/training/runs/`; generators, scoring rules and budget tests are versionable. The reusable `run.py` now evaluates all 33 cases and saves both checkpoint types. General AI adapters have mock coverage and missing-key live coverage; real image/social generation with the new Gemini key has not been exercised because that key is intentionally absent.
