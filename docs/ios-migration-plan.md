# LifeMedals iOS Migration and Acceptance Plan

## Approach

LifeMedals uses the existing SwiftUI target for macOS, iOS, and iPadOS. The platforms share their SwiftData schema, private CloudKit container, AI services, notification logic, and business UI. No separate app account is required; private sync follows the device iCloud account.

## Status

### 1. Multi-platform foundation — complete

- [x] Support `macosx`, `iphoneos`, and `iphonesimulator` in one target.
- [x] Configure iPhone/iPad device families, iOS deployment target, and camera/photo usage descriptions.
- [x] Use the CloudKit Development environment in Debug.
- [x] Keep Release entitlements for `iCloud.mofololo.LifeMedals` and remote notifications.
- [x] Build macOS and iOS Simulator Debug configurations.

### 2. Platform APIs and responsive UI — complete

- [x] Provide shared AppKit/UIKit image adapters.
- [x] Use cross-platform ImageIO compression.
- [x] Support both `NSViewRepresentable` and `UIViewRepresentable` for the WebKit medal animation.
- [x] Support AppKit/UIKit camera preview.
- [x] Add compact iPhone navigation and responsive creation, task, evidence, account, and reward screens.
- [x] Support camera, PhotosPicker, and files on iOS; retain drag-and-drop and paste on macOS.
- [x] Add task groups with stacked-card collapsed state and animated child expansion.
- [x] Add Unfinished/Completed/Overdue and Medals/Monster Atlas transitions.
- [x] Add narrow iOS edge-swipe navigation without replacing task-row swipe actions.
- [x] Honor Reduce Motion in task, tab, monster, and reward transitions.

### 3. Automated and simulator checks — substantially complete

- [x] Add XCTest coverage for deadlines, task generation, task groups, taxonomy, discovery idempotency, and artwork synchronization.
- [x] Add Debug screenshot routes for representative pages.
- [x] Inspect standard iPhone simulator layouts and build the current iOS target successfully.
- [ ] Add critical end-to-end UI smoke tests.
- [ ] Repeat visual QA on a small iPhone, standard iPhone, Pro Max, and iPad.

### 4. Physical-device and CloudKit acceptance — next

- [ ] Activate signing and the CloudKit container with a paid Apple Developer Team.
- [ ] Validate camera/photo permissions, capture orientation, and compressed output on iPhone.
- [ ] Validate local notification authorization, foreground presentation, deadline delivery, and restoration after launch.
- [ ] Validate initial Apple authorization, cancellation, revocation, offline session behavior, and sign-out.
- [ ] Validate Dynamic Type, VoiceOver order and labels, touch targets, keyboard avoidance, and orientation policy.
- [ ] Validate Reduce Motion and offline monster-artwork caching.
- [ ] Validate Mac/iPhone synchronization for tasks, task groups, edits, evidence, verdicts, EXP, and discoveries.
- [ ] Validate offline edits, reconnection, concurrent changes, conflicts, and large evidence-image fields.
- [ ] Inspect the development schema in CloudKit Console and publish it to Production before distribution.

### 5. TestFlight and distribution — pending

- [ ] Produce the iOS icon, launch experience, and device screenshots.
- [ ] Complete the privacy manifest, privacy policy, and camera/photo/iCloud/AI disclosures.
- [ ] Create the iOS version in App Store Connect and verify its iCloud container association.
- [ ] Archive and validate signing, entitlements, and privacy declarations.
- [ ] Run a TestFlight beta covering crashes, performance, network failure, and data migration.
- [ ] Submit to App Review.

## Acceptance criterion

An iPhone beta must independently complete:

```text
Generate contract -> save -> receive reminder -> capture/select proof
-> verify -> reveal monster -> award EXP -> review achievements
```

Local data must survive network loss. When connectivity returns, Mac and iPhone using the same iCloud account must eventually converge without duplicating EXP or monster defeats.

## Debug screenshot routes

Set `LIFEMEDALS_DEBUG_PAGE` in a Debug scheme to open `tasks`, `medals`, `atlas`, `account`, `review`, `task-detail`, or `award`. These routes exist only for simulator screenshot regression and do not alter the Release user flow.
