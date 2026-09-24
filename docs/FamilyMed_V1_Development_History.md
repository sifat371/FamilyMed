# FamilyMed V1 Development History and Handoff

**Project:** FamilyMed  
**Repository:** `sifat371/FamilyMed`  
**Document date:** 2026-09-24  
**Current development branch:** `feat/v1-core-closure`  
**Base branch:** `main`  
**Current branch head at the time of writing:** `2293526d5effb5a6fad61fef995940da5d16f92d`  
**Current PR:** #7 — **Close V1 medication lifecycle gap**  
**CI status at the time of writing:** Passed

---

## 1. Purpose of this document

This document records the development journey of FamilyMed V1 from the initial product definition through the current `feat/v1-core-closure` branch.

It is intended to serve as:

- a development history;
- a technical handoff;
- a record of important product and architecture decisions;
- a summary of major bugs found during real-device testing and how they were fixed;
- a reference for finishing V1 without losing earlier context;
- a baseline for future V1.1/V2 work.

This is not only a changelog. It explains why the current application behaves the way it does and which product boundaries were intentionally chosen.

---

## 2. Product direction established at the beginning

FamilyMed was defined as a **family medication-care application**, not primarily as an AI prescription scanner.

The main product idea is that one account holder can manage medication routines for people they care for, such as:

- parents;
- spouse;
- children;
- themselves;
- other family members.

The core product loop established for V1 was:

1. Register or sign in.
2. Add a family member.
3. Add medication information.
4. Create a medication routine.
5. Enable reminders.
6. Receive local medication notifications.
7. Mark doses Taken, Snoozed, Skipped, or Missed.
8. Review Today and History.
9. Preserve actions and medication history.
10. Later support prescription-assisted entry with explicit human confirmation.

A major product principle was established early:

> **Family care is the product. Prescription AI is an assistant inside the product, not the product itself.**

This decision influenced the entire implementation order. We deliberately built the medication-care loop first so that OCR/AI would not block delivery of a useful application.

---

## 3. Safety and product rules established before implementation

The V1 specification established several important rules that should continue to be treated as non-negotiable:

- AI cannot prescribe.
- AI cannot modify a prescribed dose automatically.
- AI extraction cannot directly create an active medication.
- Selecting an AI candidate and confirming it are separate actions.
- Unknown prescription text must remain unknown rather than being silently guessed.
- Reminder clock times are not treated as prescription instructions.
- A prescription pattern such as `1+0+1` does not automatically mean specific clock times such as 08:00 and 20:00.
- `Taken` means a caregiver/user confirmed the dose as taken; the application does not claim to prove ingestion.
- Editing a routine changes future dose behavior without rewriting past medication history.
- Ending medication must preserve historical dose records.

These rules remain relevant when the prescription workflow is implemented.

---

# 4. Initial architecture

FamilyMed was created as a monorepo:

```text
FamilyMed/
├── mobile/       Flutter Android client
├── backend/      FastAPI/PostgreSQL backend
├── ai/           prescription extraction service boundary
├── docs/         specifications and implementation plans
├── infra/
└── docker-compose.yml
```

## 4.1 Mobile stack

The mobile application uses:

- Flutter;
- Riverpod;
- go_router;
- Dio;
- Drift/SQLite;
- flutter_secure_storage;
- flutter_local_notifications;
- timezone;
- English/Bangla localization.

The Android app package is:

```text
com.familymed.familymed
```

## 4.2 Backend stack

The API uses:

- Python 3.13;
- FastAPI;
- PostgreSQL;
- SQLAlchemy 2.x async;
- Alembic;
- Pydantic;
- JWT authentication;
- Argon2-compatible password hashing through `pwdlib`.

API base path:

```text
/api/v1
```

## 4.3 Local/offline architecture

The mobile application was designed to keep medication/dose state locally using Drift.

Dose actions are optimistic:

1. update local state immediately;
2. queue a sync operation;
3. update the UI;
4. replay the action when the API is available;
5. clear the queued operation after successful synchronization.

This architecture became especially important during real-device testing because the development API was accessed through temporary Cloudflare tunnels.

---

# 5. Development chronology

## Phase 0 — Product specification and implementation planning

The first commits were documentation-first:

- `e745d8c` — add FamilyMed V1 design specification;
- `2663347` — add FamilyMed foundation implementation plan;
- `88f10ba` — tighten the foundation plan.

This gave the project a defined V1 scope before implementation.

The approved V1 included authentication, family members, manual medication entry, schedules, Today, notifications, dose actions, history, offline synchronization, and a safe prescription-assisted workflow.

---

## Phase 1 — Application foundation

Major foundation commit:

```text
2bea1f0 — feat: establish FamilyMed application foundation
```

This established:

- Flutter application structure;
- FastAPI project structure;
- PostgreSQL configuration;
- Alembic migrations;
- Drift local database;
- localization infrastructure;
- CI;
- routing and application baseline;
- environment configuration.

This was the point at which FamilyMed became a working application project rather than only a specification.

---

## Phase 2 — Authentication, family management, and manual medication entry

Major vertical-slice commit:

```text
b0be546 — feat: add auth, family, and manual medication flow
```

This added the first meaningful end-to-end user workflow.

### Authentication

Implemented:

- registration;
- login;
- JWT access/refresh flow;
- secure token storage;
- session restoration;
- automatic token refresh;
- logout;
- invalid-session handling.

### Family management

Implemented:

- family-member creation;
- ownership/access checks on the backend;
- family-member profile;
- family-member listing;
- preferred language;
- relationship and timezone fields.

### Manual medications

Implemented:

- manual medication creation;
- strength;
- dosage form;
- start date;
- optional end date;
- medication state;
- backend authorization.

At this stage, medication routines and Today behavior were still incomplete.

---

## Phase 3 — Schedules, dose generation, Today, actions, reminders, history

This became the largest early development phase.

Design/implementation documents were added first:

- `b977434` — schedules, doses, and Today design;
- `c4296c8` — implementation plan;
- `21a07b8` — final plan review.

### Backend schedule/dose implementation

Key additions included:

- medication schedules;
- schedule times;
- rolling dose generation;
- reconciliation of pending/missed doses;
- medication lifecycle backend services;
- Taken/Snooze/Skip actions;
- notification preferences;
- Today projection;
- reminder feed;
- history projection.

Representative commits included:

```text
94a8d6a — add schedule and dose persistence
4a98ad1 — add medication schedule generation
02953ad — reconcile due and missed doses
d37e781 — add medication lifecycle services
9a5a795 — expose medication lifecycle routes
992a0b1 — implement idempotent dose actions
727e27f — implement notification preferences
e953d84 — build Today/history/reminder projections
d5b6d90 — expose Today/history/reminder feed
```

### Mobile schedule and Today layer

The Flutter application then gained:

- schedule repository;
- Today repository;
- local cache;
- routine setup;
- notification scheduler;
- Today dashboard;
- dose cards;
- dose details;
- dose actions;
- offline queueing;
- history;
- correction UI.

Representative commits:

```text
7cd8130 — add mobile schedule and Today data layer
63b7ef6 — add routine setup and local reminders
2b2137c — add Today dashboard
a47764d — add optimistic dose repository
c2602a4 — add durable dose sync coordinator
cdada80 — add dose action screen
c6e2912 — add member history screen
f96319d — add correction screen
```

---

## Phase 4 — Offline reliability and account isolation

A large amount of work went into preventing data from one signed-in account from leaking into another account's local cache.

Important changes included:

- account-scoped local medication state;
- account-scoped cached doses;
- account-scoped offline sync queue;
- account-aware optimistic updates;
- cancellation of reminders when a session ends;
- prevention of stale reminder eligibility;
- preserving queued dose actions;
- preserving reminder eligibility during synchronization.

Representative commits:

```text
a2bca92 — scope local medication data by account
71e4d2e — migrate local cache to account scope
14d1f47 — scope offline sync replay to account
71d247d — scope optimistic dose actions to account
e16ee65 — isolate optimistic cache updates by account
e903f9b — isolate Today cache and preserve queued actions
53e6589 — cancel reminders on session end
```

This work is the reason later testing showed that logging into multiple accounts retained the appropriate separate states.

---

## Phase 5 — Notification coordination and sync reliability

Notification handling was centralized through a reminder coordinator.

This ensured reminder reconciliation happens after:

- authentication;
- app resume;
- routine changes;
- notification preference changes;
- dose changes.

Important work included:

- notification tap handling;
- cold-start notification handling;
- reminder feed respecting user preferences;
- sync conflict behavior;
- user-visible sync-failure messaging.

Representative commits:

```text
f6d895f — centralize reminder reconciliation
5654beb — use reminder coordinator in app lifecycle
139647e — refresh reminders after routine changes
20b9134 — handle notification cold-start launch
b2f6c8b — honor reminder preferences in feed
```

---

## Phase 6 — PR #3: schedules, doses, Today, and reminders

The schedules/doses work was consolidated into:

```text
PR #3 — Schedules, doses, Today, and reminders
Merge: 0676ef633db991546794ebe8936869f687821fa4
```

At this point the primary medication-care architecture existed, but real-device testing immediately exposed navigation and usability problems that automated tests had not fully captured.

---

# 6. First real-device testing and navigation repair

The app was built and installed on a physical Android phone.

The first build exposed issues such as:

- unclear authenticated landing behavior;
- inconsistent navigation between Today and Family;
- empty Today state without useful actions;
- difficulty returning to family management;
- login/register forms being disrupted by routing/loading state.

This resulted in:

```text
PR #4 — Fix V1 navigation and empty Today onboarding
Merge: 5edef6213a5070288ccb3e310fd1695eb1b6b005
```

Major improvements:

- persistent bottom navigation;
- Today tab;
- Family tab;
- family-aware authenticated landing;
- empty Today actions;
- sign-out access;
- family-member profiles kept inside the shell;
- stable widget keys for navigation testing;
- login/register form stability.

The real-device app then became practical to navigate.

---

# 7. Reminder failure investigation

During physical-device testing, medication schedules appeared in Today, but reminders did not reliably fire.

Several separate problems were identified.

## 7.1 Missing Android scheduled-notification receivers

The Android manifest did not contain the scheduled notification receivers required by `flutter_local_notifications`.

## 7.2 Exact-alarm access

The app used:

```text
AndroidScheduleMode.inexactAllowWhileIdle
```

This could allow medication reminders to arrive late.

Exact alarm permission/access was not being requested.

## 7.3 Same-minute scheduling

The scheduler ignored an alarm when its resolved timestamp was already in the past.

Therefore creating a reminder for the current minute was unreliable by design.

## 7.4 Stale Today state

After creating a routine or taking/skipping a dose, the backend/local database could already be correct while Riverpod still showed the previous Today state.

This made the app look slower or broken even when the write had succeeded.

These fixes became:

```text
PR #5 — Fix reminder delivery and stale Today updates
Merge: 07a251173deb205744c858f7c2daf5c368fe2c3d
```

Key commits:

```text
25978af — Configure Android scheduled notification receivers
0b4bc75 — Request exact alarm access and schedule reminders precisely
bc71e66 — Refresh Today and medication state after routine changes
9c45e62 — Refresh Today after enabling reminders
9e68fc9 — Refresh Today immediately after dose actions
```

---

# 8. V1 usability hardening

Once the reminder problem was under control, development stopped focusing on one isolated bug at a time.

The project moved into a broad V1 hardening pass.

This became:

```text
PR #6 — Harden V1 medication and reminder UX
Merge: c033ed6a333a56d179485af4b693182eaed37b8a
```

This was a large improvement pass across the application.

---

## 8.1 Reminder time UX

The original routine form accepted raw 24-hour text such as:

```text
04:15
20:00
```

This was ambiguous for normal users and especially problematic for a caregiver-focused application.

It was replaced with a proper Android time picker and explicit AM/PM display.

Examples:

```text
4:15 AM
8:00 PM
```

The application still sends canonical 24-hour values internally.

Additional changes:

- multiple reminder rows can be removed;
- duplicate reminder times are rejected;
- History, Today, and Dose Details use AM/PM presentation.

---

## 8.2 Hidden schedule-period bug

A hidden implementation problem was discovered:

new reminder rows defaulted internally to `morning`, even when the selected clock time was in the evening.

This was corrected by deriving the period from the selected local time:

- morning;
- afternoon;
- evening;
- night.

The hidden row state was then removed.

---

## 8.3 Medication and family editing

Originally the app supported creation but did not provide a complete editing experience.

PR #6 added:

- Edit family member;
- Edit medication;
- medication date pickers;
- DOB picker;
- improved relationship input;
- localized relationship labels.

The onboarding choice **My parent** was also corrected so that it no longer silently assumed the parent was the mother.

---

## 8.4 Developer-oriented input removal

Several forms originally required technical/raw values.

Examples included:

- `YYYY-MM-DD`;
- ISO timestamps such as `2026-09-23T12:12:00Z`;
- raw 24-hour reminder text.

These were replaced with user-facing pickers.

History correction now uses:

- date picker;
- time picker;
- AM/PM display.

Future-dated medication corrections are rejected.

---

## 8.5 Dose state hardening

Finalized doses such as Taken, Skipped, or Missed should not be accidentally acted on again.

PR #6 therefore:

- disables normal dose actions for finalized doses;
- exposes **Correct record** instead;
- shows dose status clearly on Dose Details;
- improves History correction flow.

---

## 8.6 Quantity presentation

Backend numeric values could appear as:

```text
1.000 tablet
```

A compact quantity formatter was added so user-facing screens display:

```text
1 tablet
```

The formatter is used across relevant mobile UI and notification scheduling for newly scheduled notifications.

---

## 8.7 Reminder settings became revisitable

Originally the reminder enable screen behaved too much like a one-time onboarding step.

It was changed into a real setting.

A caregiver can now:

- open Reminder settings from the family profile;
- enable reminders;
- disable reminders;
- return later after choosing Not now.

The screen also explains Android notification and **Alarms & reminders** permission requirements.

---

## 8.8 Better network/error states

Retry actions were added to:

- Today;
- Family;
- Family Profile.

This prevents a temporary API failure from becoming a dead-end screen.

---

## 8.9 Improved editing/navigation behavior

Bottom navigation is hidden on setup/editing forms so an accidental tap does not discard partially entered data.

Examples:

- medication editing;
- routine setup;
- reminder settings;
- correction flow.

---

## 8.10 Authentication UX

Password fields gained show/hide controls.

---

## 8.11 Human-friendly family and history text

Raw backend values were replaced with localized labels such as:

```text
Mother
Father
Parent
Spouse
Child
Self
Other
```

History dates and percentages were also formatted for normal users rather than API-style output.

---

## 8.12 Medication identity/cache protection

A cache/feed edge case could replace the real medication name with the fallback word:

```text
Medication
```

The dose parser/cache logic was hardened so existing medication identity is preserved when an incomplete feed item is encountered.

---

# 9. Physical-device QA result after PR #6

A second Android build was installed over the first build rather than uninstalling the application.

This was intentional because upgrade behavior and persistence needed testing.

Manual physical-device testing confirmed:

- the existing signed-in session survived the upgrade;
- family/medication state survived the upgrade;
- Today displayed clear AM/PM times;
- reminders fired successfully;
- notification delivery worked;
- previous Taken/Skipped states remained visible;
- multiple account login/state handling behaved correctly;
- the app felt significantly more responsive than the original build;
- the revised reminder-time UI was clearer than the first version.

This physical-device milestone was important because it validated functionality that automated tests alone could not fully verify.

---

# 10. Development/testing infrastructure used during real-device work

The university/lab development PC did not have a direct physical-phone USB testing connection available for the workflow used here.

Therefore two separate temporary HTTP tunnels were used.

## 10.1 Backend tunnel

FastAPI was run locally on:

```text
127.0.0.1:8001
```

Port 8000 was already occupied.

A Cloudflare quick tunnel exposed the API to the Android phone.

The APK was built with the temporary API URL using:

```bash
flutter build apk --debug \
  --dart-define=FAMILYMED_API_BASE_URL=https://<temporary-api-tunnel>/api/v1
```

Important:

Cloudflare quick-tunnel URLs are temporary.

If the API tunnel dies, an APK compiled with the old URL cannot automatically discover the new URL. A new APK build is required with the replacement API URL.

This is a development-only limitation, not the intended production architecture.

## 10.2 APK transfer tunnel

The generated APK was served locally with:

```bash
python3 -m http.server 8080 --bind 127.0.0.1
```

A separate Cloudflare tunnel exposed port 8080 so the APK could be downloaded on the phone.

The API tunnel and APK-download tunnel serve completely different purposes and must not be confused.

---

# 11. Local lab configuration that must not be accidentally committed

The lab machine currently contains intentional local modifications, including:

```text
backend/uv.lock
docker-compose.yml
mobile/pubspec.lock
```

Most importantly, the lab Docker PostgreSQL host port was changed from 5432 to:

```text
5433
```

because the system PostgreSQL instance already uses 5432.

This local `docker-compose.yml` adjustment should not be erased by a destructive Git reset and should not be accidentally committed as a project-wide configuration change.

When changing branches on the lab PC, we used:

```bash
git stash push -u -m "lab local config before V1 hardening"
git switch main
git pull origin main
git stash pop
```

Avoid:

```bash
git reset --hard
```

unless the local configuration has intentionally been backed up and is meant to be discarded.

---

# 12. CI and testing strategy

Development has generally followed test-first or test-backed changes.

## Backend CI

Backend CI verifies:

```bash
uv sync --all-groups
uv run ruff check .
uv run alembic upgrade head
uv run pytest -v
```

Coverage includes:

- authentication;
- family ownership;
- medications;
- medication lifecycle;
- schedule generation;
- Today;
- history;
- reminder feed;
- notification preferences;
- reconciliation;
- dose actions;
- cross-family access controls.

## Mobile CI

Flutter CI verifies:

```bash
flutter pub get
flutter gen-l10n
dart run build_runner build
flutter analyze
flutter test
flutter build apk --debug
```

The second hardened local build passed:

- Flutter analyzer;
- 71 Flutter tests;
- debug APK build.

Real-device testing is then used as a separate acceptance layer.

---

# 13. Current branch — V1 core closure

After PR #6 was validated on the phone, development moved to:

```text
feat/v1-core-closure
```

The goal of this branch is to close remaining core medication-care gaps before implementing the prescription-assisted flow.

---

## 13.1 Medication lifecycle gap

The backend already supported:

```text
POST /member-medications/{id}/pause
POST /member-medications/{id}/resume
POST /member-medications/{id}/end
```

but the Flutter application did not expose those actions.

This was a mismatch between backend capability, the original V1 specification, and actual mobile UX.

PR #7 fixes that.

### Added on this branch

Commit:

```text
e141663 — Add medication lifecycle mobile repository
```

The mobile app now has a dedicated repository for:

- Pause;
- Resume;
- End.

Localization was added in English and Bangla.

The family profile medication card now exposes:

- **Pause medicine** for active medication;
- **Resume medicine** for paused medication;
- **End medicine** for active/paused medication.

Ending medication requires confirmation.

The confirmation explains that:

- future reminders stop;
- future untouched doses stop;
- existing history remains.

After a lifecycle action, the app:

- refreshes medication state;
- refreshes Today;
- reconciles local reminders.

Widget tests were added for Pause → Resume and End confirmation behavior.

---

## 13.2 Current PR

```text
PR #7 — Close V1 medication lifecycle gap
Head: 2293526d5effb5a6fad61fef995940da5d16f92d
```

CI run #305 passed successfully at the time this document was created.

---

# 14. Current V1 feature status

## Implemented and working

### Authentication

- Register;
- Login;
- refresh token;
- secure session storage;
- restored sessions;
- logout;
- multiple account state isolation.

### Family care

- add family member;
- list family members;
- family profile;
- edit family member;
- relationship localization;
- English/Bangla preference.

### Manual medications

- create medication;
- edit medication;
- strength;
- dosage form;
- start/end date;
- human-friendly pickers;
- status display.

### Medication lifecycle

Backend:

- Pause;
- Resume;
- End.

Mobile lifecycle controls are implemented in the current PR branch.

### Routines

- create routine;
- edit routine;
- multiple reminder times;
- remove reminder times;
- duplicate-time validation;
- meal relation;
- quantity/unit;
- user-selected reminder clock times;
- automatic period derivation.

### Today

- doses grouped by family member;
- Taken summary;
- Pending/Upcoming/Taken/Skipped/Missed state;
- AM/PM time;
- pull refresh;
- periodic refresh while open;
- offline cached state;
- retry behavior.

### Dose actions

- Taken;
- Snooze;
- Skip;
- correction;
- final-state protection.

### Notifications

- Android notification permission;
- exact alarm access where available;
- scheduled notification receivers;
- reboot receiver;
- reminder reconciliation;
- notification tap → dose;
- notification launch handling;
- account/session cleanup;
- physical-device reminder delivery confirmed.

### History

- member history;
- adherence display;
- events;
- correction flow;
- preservation of historical records.

### Offline/sync

- local Drift cache;
- queued dose actions;
- optimistic UI;
- sync coordinator;
- replay after activity/resume;
- account-scoped state;
- sync-failure notice.

---

# 15. What is still required to declare V1 complete

The remaining major V1 milestone is the **prescription-assisted medication entry workflow**.

The current UI still shows:

```text
Scan prescription — coming soon
```

The approved V1 specification requires a safe mocked prescription pipeline even if real OCR is deferred.

The next development branch should implement:

1. prescription image selection/upload;
2. backend prescription records;
3. private/local development storage abstraction;
4. prescription history;
5. mocked extraction endpoint/service;
6. extraction candidates;
7. candidate selection;
8. separate explicit confirmation;
9. editable/correctable extracted fields;
10. creation of a draft member medication only after confirmation;
11. optional medicine-master search;
12. tests proving that selection alone cannot activate/create confirmed medication state.

Real OCR/HTR is **not required** for the V1 finish line.

The existing `ai/` boundary was intentionally created so real OCR can replace the mock implementation later without changing the safety model.

---

# 16. Recommended final V1 development sequence

After PR #7:

## Step A — Merge core closure

Merge PR #7 after branch review/CI.

## Step B — Prescription workflow branch

Suggested branch:

```text
feat/v1-prescription-workflow
```

Implement the mocked prescription-assisted flow end to end.

## Step C — Final product hardening

Run the complete V1 workflow and fix only release-blocking issues.

Avoid introducing large new features at this point.

## Step D — Final Android acceptance build

The final V1 acceptance flow should include:

1. Register.
2. Add Amma.
3. Upload/select a prescription photo.
4. Mock extraction returns at least two medication candidates.
5. Select a candidate.
6. Verify selection is not yet confirmation.
7. Explicitly confirm/correct medication.
8. Create routine.
9. Set multiple AM/PM reminder times.
10. Enable Android reminder permissions.
11. Verify physical notification delivery.
12. Mark Taken.
13. Snooze another dose.
14. Skip another dose.
15. Verify Today.
16. Verify History.
17. Correct one final dose record.
18. Pause medication.
19. Resume medication.
20. End medication and verify history remains.
21. Perform a dose action offline.
22. Restore network and verify sync.
23. Logout.
24. Login with another account and verify state isolation.
25. Return to the original account and verify its state remains intact.

## Step E — V1 baseline

When the full acceptance flow passes:

- merge the final branch;
- confirm CI;
- create a clean release APK/build;
- tag the repository with a V1 baseline;
- archive/update this document with the final release commit.

---

# 17. Features intentionally deferred beyond V1

These should not delay the current V1 release:

- real handwriting/OCR model integration;
- caregiver invitations/multi-caregiver sharing;
- doctor accounts;
- pharmacy ordering;
- refill prediction;
- medication recommendation;
- drug-interaction decisions;
- diagnosis;
- emergency triage;
- EHR/hospital integration;
- research-data collection;
- advanced adherence analytics;
- notification action buttons such as Taken/Snooze directly from the notification;
- elder-specific simplified UI.

These may be candidates for V1.1/V2 after the core product is stable.

---

# 18. Important development lessons from the first builds

Several lessons from the development process should be preserved.

## Automated tests are necessary but not enough

CI passed many behaviors that still felt broken on a physical phone.

Real-device testing revealed:

- notification receiver configuration;
- exact-alarm behavior;
- stale UI refresh;
- ambiguity of raw 24-hour reminder entry;
- navigation weaknesses;
- practical account/session behavior.

Therefore future milestones should use both:

- automated CI;
- physical-device acceptance testing.

## UI state can make correct backend behavior look broken

Several early reports of delayed behavior were caused by stale providers rather than failed backend writes.

After any state-changing action, confirm both:

- canonical backend/local state;
- UI invalidation/refresh.

## Reminder infrastructure must be treated as a system

A reminder is not just a scheduled timestamp.

Correct delivery depends on:

- routine generation;
- notification preference;
- Android permission;
- exact-alarm capability;
- manifest receivers;
- app lifecycle reconciliation;
- user account;
- local cached reminder eligibility.

The centralized reminder coordinator is therefore an important architectural component.

## Production infrastructure should not use quick tunnels

`trycloudflare.com` was useful for development and phone testing, but it is ephemeral.

A production/staging deployment should use a stable HTTPS API domain.

---

# 19. Current handoff summary

At the time of this document:

- `main` contains the validated PR #6 V1 hardening build.
- Physical-device notifications work.
- AM/PM reminder UX works.
- the app is substantially faster and clearer than the first physical build.
- account-specific state isolation has been exercised successfully.
- `feat/v1-core-closure` adds mobile Pause/Resume/End medication lifecycle controls.
- PR #7 CI has passed.
- the final major V1 development block is prescription-assisted entry using the existing mocked AI boundary.

The project should now be treated as being in **V1 completion**, not early prototyping.

The finish line should remain fixed:

> Complete the prescription-assisted mocked golden path, run final end-to-end Android QA, fix release-blocking issues, and establish the V1 baseline.

---

## 20. Key Git milestones

| Milestone | Reference |
|---|---|
| V1 design specification | `e745d8c` |
| Application foundation | `2bea1f0` |
| Auth + family + manual medication vertical slice | `b0be546` |
| Schedules/Today/reminders PR #3 | `0676ef6` |
| Navigation/onboarding PR #4 | `5edef62` |
| Reminder reliability PR #5 | `07a2511` |
| V1 UX hardening PR #6 | `c033ed6` |
| Current core-closure branch | `feat/v1-core-closure` |
| Current core-closure head | `2293526` |
| Current PR | #7 |

---

**End of current development record.**
