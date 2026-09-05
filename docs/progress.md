# Development Progress

> This is the current project checklist and an append-only summary of important milestones. Historical architecture choices are retained only in the timeline and do not override the current status.

## Current status

**Phase:** iOS v2 task-monster and Monster Atlas loop is implemented in the client and staging Worker.

**Implemented:** local-first task flow, task groups, image-based generation, flexible evidence verification, medals/EXP, multi-platform UI, direct private-CloudKit persistence without an app account, device-local private images, monster taxonomy and discovery, D1/R2/Queue generation, sequential Level 1-9 artwork, budget recovery, disk caching, and iOS edge navigation.

**Deployed:** the configured staging Worker is live. On 2026-09-03, `GET /health` returned HTTP 200 with OpenAI, usage protection, and monster services configured. Production still has only the base API configuration and does not yet include the staging monster bindings.

**Next:** run physical-iPhone and paid-team CloudKit acceptance; exercise staging image generation and budget/dead-letter behavior; then promote monster resources to production and prepare TestFlight.

## Rules for contributors

1. Read [README](../README.md) and [Product and technical plan](product-plan.md) before changing product behavior.
2. Update the relevant checkbox when a subtask is completed.
3. Keep SwiftData/CloudKit schema changes backward compatible. A published production schema must evolve additively.
4. Append a dated milestone to this file when completing a meaningful unit of work.
5. Never move private tasks, evidence, EXP, or discoveries into the global monster service.

## Roadmap

### 0. Foundation and architecture

- [x] Create the GitHub repository and Xcode project.
- [x] Use one SwiftUI target for macOS, iOS, and iPadOS.
- [x] Adopt SwiftData local-first storage and remove Supabase.
- [x] Choose Cloudflare Workers as the minimal AI gateway.
- [x] Keep `OPENAI_API_KEY` exclusively in Worker secrets.
- [x] Separate the MVP from StoreKit, server accounts, and per-user billing.

### 1. Local models and persistence

- [x] Implement `BadgeCategory`, `UserBadge`, `TaskContract`, `Evidence`, `XPLog`, and `MonsterDiscovery`.
- [x] Configure the SwiftData model container.
- [x] Use external storage for evidence and source-image data.
- [x] Remove old Supabase authentication, dependencies, secrets, and migration files.
- [ ] Complete a documented offline CRUD and relaunch-persistence acceptance pass.

### 2. Session, task generation, and groups

- [x] Open directly without an app account and use the device iCloud account for private sync.
- [x] Implement `POST /generate-task` with size validation and Structured Outputs.
- [x] Apply an atomic global rate limit and monthly request budget before OpenAI calls.
- [x] Support text or one compressed source image plus optional context.
- [x] Generate a single task or a multi-child task group.
- [x] Keep task titles short and valid; preserve details in a separate description.
- [x] Let users edit the contract before saving.
- [x] Keep drafts after network failure and allow retry.

### 3. Tasks, interaction, and reminders

- [x] Show Unfinished, Completed, and Overdue task tabs.
- [x] Show task details, source images, evidence, and status.
- [x] Schedule and restore local deadline notifications.
- [x] Reconcile task-group parents idempotently after child completion.
- [x] Show collapsed groups as stacked pixel cards and expand children in place.
- [x] Add directional task/achievement transitions and iOS edge-swipe navigation.
- [x] Keep page headings and selectors fixed while only content regions transition.

### 4. Evidence and verification

- [x] Accept any one-to-five-image batch.
- [x] Support camera, PhotosPicker, and files on iOS; drag-and-drop and paste on macOS.
- [x] Compress copies before storing them in SwiftData.
- [x] Implement `POST /verify-evidence` with the shared usage gate.
- [x] Keep evidence in request memory only and forward with `store: false`.
- [x] Treat title and evidence requirement as independent, forgiving verification paths.
- [x] Return and persist Verified, Need More Proof, or Not Verified.
- [x] Preserve pending batches and retry after service failures.

### 5. Medals and achievements

- [x] Award EXP through `XPLog` and update one medal independently.
- [x] Implement nine-rank progression.
- [x] Render medal fragments and rank/EXP state.
- [x] Play reward animation only after persistence succeeds.
- [x] Show verified task/evidence history in Achievements.

### 6. Monster client

- [x] Decode monster fields for single tasks and child tasks with stable fallback taxonomy.
- [x] Preserve explicitly named sports as independent species.
- [x] Lock encounter level from the final selected medal rank.
- [x] Give child tasks encounters and keep group parents monster-free.
- [x] Preview a ready variant during confirmation or show an unknown silhouette.
- [x] Refresh before verification reveal and save discoveries idempotently.
- [x] Prevent duplicate defeat counts for repeated callbacks from one task.
- [x] Reveal monsters before medal/EXP animation and honor Reduce Motion.
- [x] Show personal species with locked Level 1-9 routes in the Monster Atlas.
- [x] Cache public artwork and refresh pending discoveries.
- [ ] Validate VoiceOver, Reduce Motion, and offline caches on physical iPhone hardware.

### 7. Monster Worker

- [x] Add D1 migrations for species, aliases, concepts, variants, normalized taxonomy, and distinct sports.
- [x] Implement idempotent `POST /monster-variants/ensure` and variant GET.
- [x] Implement immutable monster-asset delivery from R2.
- [x] Implement Queue consumption, generation leases, retries, and safe failure summaries.
- [x] Generate Level 1 from visual DNA and higher levels sequentially from the prior image.
- [x] Enforce signature-object visual anchors.
- [x] Add a separate per-minute and monthly monster-image budget.
- [x] Recover variants automatically from temporary budget exhaustion.
- [x] Configure and deploy staging D1, R2, Queue, dead-letter queue, secrets, and migrations.
- [x] Verify the staging health configuration.
- [ ] Complete staging generation/caching/dead-letter acceptance across several species and levels.
- [ ] Create and deploy equivalent production bindings and migrations.

### 8. CloudKit and physical-device acceptance

- [x] Configure the `iCloud.mofololo.LifeMedals` private container for Development and Production builds.
- [x] Make the SwiftData schema CloudKit compatible.
- [x] Display account and synchronization states.
- [x] Enable CloudKit Development and remote-notification background delivery in Debug.
- [ ] Activate paid-team signing and container access.
- [ ] Validate offline recovery, conflicts, EXP, task groups, and discoveries between two physical devices; confirm source/evidence images remain device-local.
- [ ] Publish the verified CloudKit development schema to Production.

### 9. Product validation and distribution

- [ ] Use LifeMedals daily for at least one to two weeks.
- [ ] Record task-generation quality, evidence friction, and motivational impact.
- [ ] Run a small beta with five to ten users.
- [ ] Finish small/standard/large iPhone and iPad visual QA.
- [ ] Add critical UI smoke tests.
- [ ] Prepare icons, screenshots, privacy materials, and App Store metadata.
- [ ] Complete TestFlight and App Review.

### 10. Later commercial phase

- [x] Remove the planned LifeMedals account server and Sign in with Apple requirement from the current product architecture.
- [ ] Add StoreKit 2 subscriptions, transaction listening, and purchase restoration.
- [ ] Add minimal account, entitlement, and usage-ledger records.
- [ ] Link purchases with `appAccountToken` and validate signed transactions.
- [ ] Add free/paid per-user quotas and rate limits.
- [ ] Implement account deletion, server cleanup, and Apple token revocation.

This phase must not move private task or evidence data to the server.

## Milestone log

- 2026-09-04 — Removed Sign in with Apple and the login gate. Unified the app and private CloudKit container identifiers, enabled Development/Production CloudKit environments and background remote notifications, moved task-source/evidence images to backup-excluded device-local storage, and added safe legacy image migration.
- 2026-09-04 — Migrated monster generation and evolution assets from opaque WebP to alpha-channel PNG cutouts, versioned the transparent style family, and made clients refresh stale pre-migration monster artwork.

- 2026-09-03 — Added iOS edge-swipe navigation for task tabs, task-detail return, and achievement tabs; unified directional transitions and limited them to the changing content region. Refined task-group cards so collapsed groups stack toward the lower right and expanded groups return to a normal single-card parent. Current iOS Simulator Debug build passed.
- 2026-09-02 — Added validated short task titles and a separate task description throughout generation, persistence, notifications, verification, and task-group editing. Compressed a large medal asset.
- 2026-08-30 — Made monster variants recover from temporary monthly image-budget exhaustion instead of remaining permanently failed; updated staging release metadata and tests.
- 2026-08-29 — Replaced deadline presets with platform wheel-date selection and expanded deadline tests.
- 2026-08-27 — Simplified evidence submission to any one-to-five-image batch. Made verification motivational and forgiving: credible support for the title or locked requirement can pass. Removed exact photo-plan requirements from new generation while retaining compatibility fields for existing data.
- 2026-08-26 — Preserved fourteen named sports as distinct species, added Worker and iOS fallback normalization, required one or two strongly associated visual anchors, added Athlete seeds and D1 migration `0004`, and versioned the v2 art prompts.
- 2026-08-25 — Completed the task-monster client loop, encounter level locking, idempotent discoveries, reveal ordering, Monster Atlas, disk cache, pending-art refresh, confirmation preview, and background ensure/poll behavior.
- 2026-08-23 — Added image-based task creation from mail, syllabi, posters, and similar sources; retained the compressed source image in SwiftData and added Worker validation/tests.
- 2026-08-08 — Converted the project into a macOS/iOS multi-platform target, added UIKit/AppKit adapters and compact iPhone UI, completed a simulator page audit, fixed overflow and keyboard/navigation issues, and added Reduce Motion behavior.
- 2026-08-07 — Added local-development Debug configuration, Sign in with Apple, Keychain sessions, CloudKit-compatible models, synchronization monitoring, and the private CloudKit container configuration.
- 2026-08-04 — Embedded and optimized the WebKit medal-transmutation animation, connected it to persisted EXP progress, and made the reward overlay controllable from Swift.
- 2026-07-31 — Completed task lists and notifications, one-to-five-image evidence persistence, three-state verification, retry behavior, EXP awards, and achievement history.
- 2026-07-30 — Built the Cloudflare Worker task-generation proxy, atomic global usage gate, monthly budget, editable contract flow, and SwiftData migration. Removed Supabase and standardized on OpenAI Responses API with `gpt-5.6-terra`.
- 2026-07-29 — Created the repository, initial Xcode app, README, and product plan. An early Supabase experiment was removed the following day and is not part of the current architecture.
