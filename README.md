# LifeMedals

**Current status:** The macOS/iOS MVP loop is implemented, including task groups, flexible evidence verification, medals and EXP, task monsters, and a personal Monster Atlas. The staging Cloudflare Worker is deployed with OpenAI, usage protection, D1, R2, and Queue bindings. Production monster infrastructure, signed-device CloudKit validation, and TestFlight/App Store work remain open.

## Product

LifeMedals turns an intention into a verifiable achievement:

```text
Describe or photograph an obligation
  -> AI creates an editable task contract
  -> confirm and complete the task
  -> submit 1-5 evidence images
  -> AI returns Verified / Need More Proof / Not Verified
  -> reveal or defeat a task monster
  -> earn medal EXP
  -> keep the result in the achievement library and Monster Atlas
```

A task contract contains a short title, description, deadline, locked evidence requirement, suggested medal, and estimated effort. Image-based creation accepts material such as an email, syllabus, or event poster and retains a compressed source image only on the device that created the task. Inputs with multiple independent actions become a task group whose children can be completed and verified separately.

## Architecture

| Layer | Implementation | Status |
| --- | --- | --- |
| Client | One SwiftUI target for macOS, iOS, and iPadOS | Implemented |
| Local data | SwiftData for tasks, evidence, medals, EXP, and discoveries | Implemented |
| Device sync | SwiftData with a private CloudKit container | Implemented; signed-device validation pending |
| App access | No app account; direct entry with private sync owned by the device iCloud account | Implemented |
| AI gateway | Cloudflare Worker using OpenAI Responses API and Structured Outputs | Deployed to staging |
| Monster assets | D1 metadata, R2 WebP assets, and Queue-based GPT Image generation | Deployed to staging; production pending |
| Subscriptions | StoreKit 2 plus server-side entitlement and usage records | Planned, not part of the MVP |

Supabase and Sign in with Apple are not used. The device's iCloud account owns private CloudKit synchronization. Without an available iCloud account, the local SwiftData replica remains usable.

## Repository layout

```text
LifeMedals/
├── README.md
├── docs/
│   ├── ios-migration-plan.md
│   ├── monster-image-spec.md
│   ├── monster-service-runbook.md
│   ├── product-plan.md
│   └── progress.md
├── LifeMedals/
│   ├── LifeMedals.xcodeproj/
│   ├── LifeMedals/                 # App source and SwiftData models
│   └── LifeMedalsTests/            # XCTest coverage
└── worker/
    ├── migrations/                 # D1 schema and taxonomy migrations
    ├── src/                        # Worker and monster generation services
    └── test/                       # Node test suite
```

## Implemented product behavior

- Create a task from natural language or one compressed JPEG plus optional context.
- Generate either one task or a task group with independently verifiable children.
- Edit title, description, deadline, evidence requirement, medal, and effort before saving.
- Keep unfinished, completed, and overdue task views with directional tab transitions and iOS edge-swipe navigation.
- Schedule local deadline notifications without making task saves depend on notification permission.
- Submit any 1-5 images from the camera, photo library, or files; macOS also supports drag-and-drop and paste.
- Compress evidence to a maximum 1,800-pixel edge and approximately 1 MB before device-local file storage.
- Treat the task title and locked evidence requirement as independent verification paths. Reasonable proof for either may pass.
- Persist Verified, Need More Proof, or Not Verified results; failed network requests remain retryable.
- Award EXP at a fixed rate of 100 XP per estimated hour, independently for each medal family.
- Show medal progress, verified history, source images, and evidence in Achievements.
- Assign a reusable English monster taxonomy tag and lock the encounter level when the task is confirmed.
- Preview ready artwork during confirmation, keep encounters hidden until verification, then reveal the monster before the medal/EXP animation.
- Store personal `MonsterDiscovery` records only in SwiftData/CloudKit and cache public artwork on disk.
- Represent collapsed task groups as stacked pixel cards and expand their child tasks in place.
- Provide English and Chinese app UI through the shared `L10n` helper. Repository documentation is maintained in English.

## Data boundaries

Private business data is local-first and belongs in SwiftData/CloudKit:

- `BadgeCategory`: built-in or custom medal category.
- `UserBadge`: EXP and rank for one category.
- `TaskContract`: task or group data, local-source-image presence metadata, optional compatibility fields, monster assignment, and status.
- `Evidence`: batch/order metadata, timestamp, verdict, and explanation.
- `XPLog`: auditable EXP change linked to a task and medal.
- `MonsterDiscovery`: a user's discovered tag/level/style, first source task, artwork URL, and defeat count.

Global monster resources contain only reusable catalog data. D1 stores species, aliases, concepts, and variant state; R2 stores immutable generated WebP files; Queue messages coordinate generation. They must never contain user identity, task text, evidence, EXP, or personal discoveries.

Evidence images are held only for the active verification request by the Worker and are forwarded with `store: false`. They are not written to Durable Objects, D1, KV, R2, or Worker logs. `store: false` does not by itself mean that upstream abuse-monitoring retention is disabled; Zero Data Retention requires separate OpenAI approval and configuration.

Task source images and evidence images are stored under the app's Application Support directory, excluded from device backups, and keyed by the corresponding model UUID. They are never written to new CloudKit-backed records. Legacy binary fields remain temporarily in the schema only so existing records can be migrated to local files and cleared safely. Public monster artwork remains a re-downloadable disk cache.

## Monster rules

- Taxonomy tags are reusable lowercase English identifiers, even when the source task is written in another language.
- Named sports remain distinct species, such as `sports.basketball`, `sports.baseball`, `sports.tennis`, and `sports.swimming`. `fitness.workout` is reserved for gym, strength, or unspecified general exercise.
- A task group's parent has no monster; each independently verified child has its own encounter.
- The selected medal's current `BadgeRank.rawValue` locks the monster level from 1 through 9. Later EXP changes do not rewrite the encounter.
- Each species concept selects one or two recognizable physical anchors and integrates every anchor into the body, silhouette, clothing, or equipment.
- Artwork failures never block local saves, evidence verification, EXP, notifications, or discovery persistence.

See [Monster image specification](docs/monster-image-spec.md) and [Monster service runbook](docs/monster-service-runbook.md).

## Local development

Requirements: current Xcode, Node.js 20 or later, and a Cloudflare account only when working on the Worker.

```bash
# Open the shared Apple-platform project.
open LifeMedals/LifeMedals.xcodeproj

# Run Worker tests and a deployment dry run.
cd worker
npm test
npm run check
```

Select the `LifeMedals` scheme and run on an iPhone or iPhone Simulator. Debug uses the Development environment and Release uses Production for the `iCloud.mofololo.LifeMedals` private container. Both configurations require the `mofololo.LifeMedals` App ID and a provisioning profile with iCloud/CloudKit and remote-notification entitlements.

The client uses build-specific defaults in `LifeMedalsAPIConfiguration`: Debug targets the staging Worker and Release targets production. Override a single Xcode run with `LIFEMEDALS_API_BASE_URL` in the scheme environment.

## Worker configuration

The API key must exist only as the encrypted Worker secret `OPENAI_API_KEY`. Never place it in Swift, `Info.plist`, an Xcode scheme, Markdown, logs, or committed configuration.

The Worker exposes:

- `GET /health`
- `POST /generate-task`
- `POST /verify-evidence`
- `POST /monster-variants/ensure`
- `GET /monster-variants/{canonicalTag}/{level}`
- `GET /monster-assets/{objectKey}`

Task generation and evidence verification share an atomic SQLite Durable Object gate. Current defaults are 20 requests per minute and 500 requests per UTC month. Monster image generation has a separate rate and monthly budget. OpenAI project spending alerts remain necessary because request counts are not real-time billing estimates.

The configured staging health endpoint returned HTTP 200 on 2026-09-03 and reported OpenAI, usage protection, and monster services as configured. Do not infer production readiness from staging health alone.

## Remaining work

- Complete daily self-testing and a small external beta.
- Validate camera orientation, permissions, notifications, Dynamic Type, VoiceOver, Reduce Motion, and offline artwork caching on physical iPhones.
- Activate and validate the CloudKit container with a paid Apple Developer Team, including conflict tests and confirmation that private images never appear on a second device.
- Promote monster D1/R2/Queue bindings and migrations to production, then verify production generation and caching.
- Prepare icons, screenshots, privacy disclosures, TestFlight, and App Review materials.
- Build StoreKit subscriptions, server accounts, entitlements, per-user quotas, and account deletion only in the later commercial phase.

For the detailed current checklist, see [Development progress](docs/progress.md). For product and architectural decisions, see [Product and technical plan](docs/product-plan.md).
