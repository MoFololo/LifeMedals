# LifeMedals Product and Technical Plan

> Updated 2026-09-03. This document describes the implemented multi-platform MVP and separates it from future commercial work.

## 1. Product thesis

Checking off an ordinary to-do provides weak feedback. LifeMedals connects game-like progression to real work through three mechanisms:

1. **Contract:** AI turns an imprecise intention or source image into an editable task contract.
2. **Evidence:** completion is supported by one to five natural evidence images and a forgiving three-state AI verdict.
3. **Accumulation:** verified work becomes medal EXP, history, and a reusable monster discovery rather than disappearing into a completed list.

The product should motivate rather than police. It is not an academic grader, auditor, application tracker, or anti-cheating system.

## 2. Core experience

```text
Text or source image
  -> editable task or task group
  -> local save and deadline reminder
  -> execution
  -> 1-5 evidence images
  -> Verified / Need More Proof / Not Verified
  -> monster reveal
  -> medal EXP and achievement history
```

The user may edit the title, description, deadline, evidence requirement, medal, and estimated effort before confirmation. After saving, the evidence requirement is locked so verification cannot silently change the agreement.

If the input contains multiple independent actions, the service returns a task group. The parent is an organizational container; each child owns its evidence, status, EXP, and monster encounter. Finishing all children reconciles the parent exactly once.

## 3. Current scope

The implemented MVP supports:

- Natural-language and image-based task creation.
- Short, validated titles and separate task descriptions.
- Task groups for multiple independently actionable items.
- Five medal families: Solver, Builder, Career, Athlete, and Life.
- SwiftData local persistence and CloudKit-compatible models.
- Direct app entry with private sync owned by the device's iCloud account.
- Unfinished, completed, and overdue task views.
- Local deadline notifications.
- Camera, photo library, and file evidence on iOS; macOS also supports drag-and-drop and paste.
- Flexible one-to-five-image evidence batches.
- AI verification with retryable failures and three verdicts.
- Independent medal EXP, nine ranks, achievement history, and reward animation.
- Reusable task monsters, asynchronous artwork, discoveries, and a personal Monster Atlas.
- English and Chinese in-app copy.

The current MVP does not include:

- StoreKit products, subscriptions, purchase restoration, or entitlements.
- Per-user server quotas, billing ledgers, or a LifeMedals account backend.
- Server-side task, evidence, medal, EXP, or discovery storage.
- Social feeds, friends, leaderboards, monetary penalties, or general AI chat.
- Anti-cheating measures such as GPS or capture watermarks.
- Production App Store assets, TestFlight validation, or completed physical-device CloudKit acceptance.

Tasks whose proof would expose sensitive booking, payment, or identity information should remain out of the initial test set.

## 4. Medal and progression system

Every medal family maintains its own EXP and rank. The AI estimates effort from 0.25 through 8 hours in quarter-hour increments; the client applies the fixed rule `100 XP = 1 estimated hour`. The model never chooses an arbitrary XP award.

| Rank | EXP required from prior rank | Cumulative EXP |
| --- | ---: | ---: |
| Bronze | Initial | 0 |
| Silver | 1,000 | 1,000 |
| Gold | 2,000 | 3,000 |
| Platinum | 3,000 | 6,000 |
| Emerald | 4,000 | 10,000 |
| Diamond | 6,000 | 16,000 |
| Master | 8,000 | 24,000 |
| Grandmaster | 10,000 | 34,000 |
| Champion | 16,000 | 50,000 |

EXP persistence must complete before reward animation begins. Animations may celebrate state but must never be required for state correctness.

## 5. Evidence policy

Evidence should be something the user naturally produces: an Accepted screen, notes, an email thread, a repository result, a workout log, or a photo of completed work.

- Any batch of one to five images may be submitted.
- The title and locked evidence requirement are two independent pass paths. Credible support for either can be enough for `Verified`.
- Relevant boundary cases without a clear contradiction should lean toward verification.
- `Need More Proof` lets the user add another batch.
- A transport or service failure leaves the batch pending and retryable.
- The service returns `{verdict, explanation}` through Structured Outputs.

The client creates a JPEG copy with a maximum 1,800-pixel edge and a target size of approximately 1 MB, then stores it with SwiftData external storage. Original media is not copied permanently into the app.

## 6. Monster system

Each independently verifiable task receives a reusable lowercase English taxonomy tag. The client locks the monster level to the selected medal's current rank at confirmation time. A later rank-up does not alter that encounter.

The system has a strict privacy split:

| Scope | Storage | Contents |
| --- | --- | --- |
| Global catalog | Cloudflare D1 | species, English aliases, visual DNA, variant state and safe generation metadata |
| Global artwork | Cloudflare R2 | immutable generated WebP files |
| Generation work | Cloudflare Queue | generic tag/level/style work only |
| Personal state | SwiftData/private CloudKit | discoveries, source task IDs, defeat counts, and cached public URLs |

The confirmation screen calls `POST /monster-variants/ensure` and briefly polls `GET /monster-variants/{tag}/{level}`. A ready image may be previewed; otherwise a local unknown silhouette appears. Saved unfinished tasks keep the encounter hidden. After evidence is verified, the app refreshes the variant, atomically persists task/discovery/EXP state, reveals the monster, and then plays the medal reward.

Artwork unavailability is non-blocking. An unknown discovery may be stored first and updated when the Atlas later sees a ready variant. Public HTTPS images are cached in the app's cache directory for offline viewing.

Named sports must not collapse into `fitness.workout`. Basketball, baseball, tennis, swimming, and other explicit sports have separate `sports.*` tags. See [Monster image specification](monster-image-spec.md).

## 7. Client architecture

One SwiftUI target serves macOS, iOS, and iPadOS. Shared code owns business state, SwiftData, AI services, notifications, and most UI. Small adapters isolate AppKit/UIKit image types, camera preview, ImageIO compression, WebKit representables, window commands, and compact layout differences.

The UI uses the repository's current light pixel-art system (`PixelTheme`, pixel cards, pixel tabs, and medal artwork). New work should extend this system rather than restoring the earlier Liquid Glass design described in historical commits.

Current navigation:

- iPhone: bottom navigation for Create, Tasks, and Achievements.
- macOS: shared top-level navigation adapted to the larger window.
- Tasks: Unfinished, Completed, and Overdue tabs; iOS supports narrow edge swipes between them.
- Achievements: Medals and Monster Atlas tabs with the same directional transition behavior.
- Task detail: iOS left-edge swipe returns to the list.

All meaningful motion must honor Reduce Motion. Pure-icon controls need accessibility labels, and physical-device VoiceOver validation remains pending.

## 8. Local data and sync

SwiftData is the source of truth for user business data. Local create, edit, browsing, notifications, EXP, and evidence history do not depend on the network.

Core models:

- `BadgeCategory`
- `UserBadge`
- `TaskContract`
- `Evidence`
- `XPLog`
- `MonsterDiscovery`

Models use stable UUIDs, optional relationships where CloudKit requires them, and no SwiftData uniqueness constraints unsupported by CloudKit. Debug uses the Development environment and Release uses Production for the private `iCloud.mofololo.LifeMedals` container. Source and evidence image bytes are stored only in backup-excluded Application Support files; CloudKit synchronizes their business metadata but not the image bytes.

The CloudKit integration and sync monitor exist, but paid-team signing, schema activation, physical-device sync, conflict handling, offline recovery, and confirmation of image non-sync still require acceptance testing. After a production CloudKit schema is published, model changes must remain additive and migration-safe.

## 9. Worker architecture and privacy

The Cloudflare Worker reads `OPENAI_API_KEY` only from an encrypted secret. It provides:

- task generation and evidence verification through OpenAI Responses API;
- structured request limits and safe error envelopes;
- an atomic SQLite Durable Object rate and monthly request gate;
- D1/R2/Queue-based monster generation with a separate image budget;
- immutable public monster asset delivery.

The staging environment is deployed and healthy. Production currently lacks the monster storage bindings present in staging and must be promoted separately.

The Worker must never persist a user's task, evidence, medals, EXP, or discoveries. Evidence exists only in the active request and is forwarded with `store: false`. Logs must exclude API keys, image Base64, and private task content.

## 10. Commercial phase

A later commercial release may add:

1. an optional future account/session service only if the product later needs identity independent of the device iCloud account;
2. StoreKit 2 auto-renewable subscriptions;
3. `appAccountToken` linkage and signed transaction validation;
4. minimal `UserAccount`, `SubscriptionEntitlement`, and `UsageLedger` records;
5. per-user quotas and rate limits;
6. purchase restoration, refund/expiry handling, and account deletion with token revocation.

iCloud identity and App Store purchase ownership remain separate systems. Even in this phase, the server must not gain access to private tasks or evidence.

## 11. Acceptance priorities

1. Use the product daily for one to two weeks and record generation quality, evidence friction, and motivational impact.
2. Validate all core flows on physical iPhones, including permissions, rotation, keyboard behavior, Dynamic Type, VoiceOver, and Reduce Motion.
3. Validate Mac/iPhone CloudKit convergence, offline edits, conflicts, and large evidence fields with paid-team signing.
4. Exercise staging monster generation, budget recovery, sequential level evolution, caching, and dead-letter behavior.
5. Promote monster resources to production only after staging acceptance.
6. Run a five-to-ten-person beta before App Store preparation.

The product hypothesis is not that every possible productivity feature can be built; it is that verified, collectible progress feels meaningfully more motivating than checking a box.
