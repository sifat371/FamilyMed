# FamilyMed V1 — Schedules, Doses, Today, and Reminder Design

Date: 2026-09-23  
Branch: `feat/schedules-today-doses`  
Status: Design for review

## 1. Purpose

This slice turns an existing FamilyMed medication record into an actionable daily care routine. A caregiver should be able to set reminder times, see today's scheduled doses, mark what happened, snooze a pending dose, and review/correct the marked history.

FamilyMed remains a medication-care tool, not a prescribing system. `taken` always means **marked taken by a family/user**; it does not claim verified ingestion.

Golden path:

`Add medication → set routine → enable reminders or Not now → generate doses → Today → Taken / Snooze / Skip → History`

## 2. Existing Context

Current `main` already has:

- FastAPI + PostgreSQL authentication;
- family ownership/membership scoping;
- family members with timezone values;
- `MemberMedication` with manual entry and `draft` status;
- Flutter auth, secure tokens, family/member flows, and medication entry;
- Riverpod, Dio, Drift, localization, and the FamilyMed visual system.

This slice extends those patterns rather than introducing a parallel architecture.

## 3. Scope

### In scope

- One current active/paused schedule per member medication.
- One to eight local reminder times per schedule.
- Raw/source instruction stored separately from reminder clock times.
- Backend-generated durable dose occurrences.
- Rolling 30-day future generation.
- `upcoming`, `pending`, `taken`, `skipped`, `missed` dose states.
- Today dashboard grouped by family member.
- Taken, Snooze, Skip, and explicit history correction.
- Append-only dose event logs.
- Medication pause, resume, manual end, and natural completion.
- Per-user/per-member notification preference; default snooze 15 minutes.
- Android local notifications.
- Offline Today cache and offline dose-action queue.
- Member history with `marked_adherence_percentage`.
- English/Bangla localization.

### Out of scope

- Prescription OCR/HTR or AI-created schedules.
- Clinical recommendations, drug interactions, diagnosis, or dose advice.
- Caregiver escalation.
- Pharmacy/refill workflows.
- Doctor/hospital portals.
- Production cron/background-worker infrastructure.
- Offline schedule creation/editing.
- Full `Today | Family | History | Me` navigation redesign. This slice makes Today the authenticated home; broader navigation polish can follow.

## 4. Safety and Product Rules

1. Source instruction and reminder times are separate data.
2. Routine UI must say: **“Reminder times are not part of the prescription.”**
3. `taken` is family/user-confirmed status only.
4. Snooze never becomes a status; a snoozed dose remains `pending` with `snoozed_until`.
5. Notification permission never controls whether a schedule is active.
6. Schedule edits never rewrite historical/due dose events.
7. Inaccessible family-owned resources return the existing not-found behavior.
8. Mobile retries must not duplicate dose actions/logs.
9. Unknown/invalid timezone identifiers are rejected rather than silently treated as UTC.

## 5. Chosen Architecture

The backend is the canonical source for schedules and dose occurrences. Flutter caches the Today projection and queues user actions while offline.

```text
MemberMedication
      ↓
MedicationSchedule
      ↓
ScheduleTime(s)
      ↓
rolling generator
      ↓
ScheduledDose(s)
      ↓
Taken / Snooze / Skip / Missed / Correct
      ↓
DoseLog (append-only)
```

This is preferred over dynamically computing Today from schedules because schedule changes must not change past expectations. It is preferred over phone-owned dose generation because the backend must remain the source of truth across devices and future caregivers.

No worker service is required yet. A shared reconciliation service is invoked by schedule mutations, Today/history reads, lifecycle actions, and dose actions. A future worker may call the same service without changing semantics.

## 6. Backend Data Model

### 6.1 `medication_schedules`

Fields:

- `id` UUID PK
- `member_medication_id` FK
- `raw_instruction` nullable text
- `meal_relation`: nullable enum-like string `before_food | after_food | with_food | none | unspecified`
- `timezone` IANA string
- `start_date` local date
- `end_date` nullable local date
- `generation_not_before_at` UTC timestamp
- `status`: `active | paused | ended`
- `created_by_user_id` FK
- timestamps

Invariant: a member medication may have at most one schedule whose status is `active` or `paused`. Ended schedules remain for history.

`generation_not_before_at` prevents same-day backfill. On initial schedule creation and every resume, it is set to the current server time truncated to the minute. Missing occurrences earlier than this boundary are never later recreated.

Creating the first schedule for a `draft` medication changes that medication to `active` in the same transaction.

### 6.2 `schedule_times`

Fields:

- `id` UUID PK
- `schedule_id` FK
- `period`: `morning | afternoon | evening | night | custom`
- `local_time`
- `quantity` decimal/numeric, not float
- `unit` trimmed short text
- `sort_order`

Rules:

- 1–8 times per schedule;
- local times unique per schedule;
- quantity > 0;
- unit nonblank.

### 6.3 `scheduled_doses`

Each row is one durable occurrence and snapshots the schedule information needed for stable history.

Fields:

- `id` UUID PK
- `schedule_id` FK
- `schedule_time_id` nullable FK, `ON DELETE SET NULL`
- `family_member_id` FK
- `member_medication_id` FK
- `scheduled_at` UTC timestamp
- `scheduled_local_date`
- `scheduled_local_time`
- `timezone` snapshot
- `quantity` snapshot
- `unit` snapshot
- `meal_relation` snapshot
- `status`: `upcoming | pending | taken | skipped | missed`
- `snoozed_until` nullable UTC
- `taken_at`, `skipped_at`, `missed_at` nullable UTC
- timestamps

Unique occurrence key: `(schedule_id, scheduled_local_date, scheduled_local_time)`.

The current row is a projection; the audit trail lives in `dose_logs`.

### 6.4 `dose_logs`

Append-only events:

- `id` UUID PK
- `scheduled_dose_id` FK
- `action`: `became_pending | snoozed | marked_taken | skipped | missed | corrected`
- `performed_by_user_id` nullable FK
- `client_action_id` nullable UUID
- `occurred_at` UTC
- `recorded_at` server UTC
- `metadata` JSONB

`client_action_id` is unique when non-null. Flutter generates one stable UUID for each user action and reuses it for retries.

Generation itself does **not** create a dose log. This is intentional: untouched future `upcoming` rows may be safely replaced when a schedule changes, pauses, or ends. Once a dose has a real event (`became_pending` or user action), its history is preserved.

Application APIs never edit/delete existing log rows.

### 6.5 `notification_preferences`

Fields:

- `id` UUID PK
- `family_member_id` FK
- `user_id` FK
- `enabled` boolean default false
- `default_snooze_minutes` default 15
- `caregiver_escalation_enabled` fixed/default false in V1
- timestamps

Unique `(user_id, family_member_id)`.

## 7. Time and Generation Semantics

### 7.1 Time representation

- Schedule input is local date/time + IANA timezone.
- `scheduled_at` is persisted in UTC.
- Today/history grouping uses stored local-date/time snapshots.
- Bangladesh launch path is explicitly tested with `Asia/Dhaka`.

DST-specific global UX is not a launch requirement for this Bangladesh-first slice; invalid timezone identifiers must still fail validation.

### 7.2 Rolling generation

For each active schedule, ensure occurrences exist for the member-local current date through current date + 29 days, bounded by medication/schedule dates.

A candidate occurrence is generated only when its UTC timestamp is at or after both:

- `generation_not_before_at`, and
- the current server minute floor.

This prevents backfilling a morning dose when a routine is created or resumed later that same day.

Generation is idempotent: repeated calls cannot duplicate dose rows.

Reconciliation runs before:

- `/today`;
- history reads;
- dose actions;
- schedule create/update/resume;
- medication pause/resume/end.

### 7.3 Due and missed transitions

`upcoming → pending` when `scheduled_at <= now`.

A `pending` dose becomes `missed` only after its member-local calendar day ends. If snoozed beyond that boundary, the missed threshold is the later of local-day end and `snoozed_until`.

`taken`, `skipped`, and `missed` are final for ordinary actions but may be changed only through the explicit correction path.

### 7.4 Snooze

Snooze is valid only for a `pending` dose.

Request includes:

- `client_action_id`;
- `occurred_at`;
- `snoozed_until`.

`snoozed_until` must be later than `occurred_at`.

Result:

```text
status = pending
snoozed_until = requested time
```

Repeated snoozes are allowed with distinct client action IDs.

## 8. Schedule Mutation Semantics

### Create

- Requires writable access to the medication's member.
- Rejects ended/completed medication.
- Rejects if a current active/paused schedule already exists.
- Creates schedule + times transactionally.
- Sets `generation_not_before_at` to current minute.
- Activates a draft medication.
- Generates the rolling window.

### Edit

Editable: instruction text, meal relation, dates, timezone, and times.

At server `now`:

- taken/skipped/missed rows are preserved;
- pending rows are preserved;
- only future `upcoming` rows with `scheduled_at > now` and no event logs are removed;
- future occurrences are regenerated from the new schedule.

Past/due expectations are never silently moved.

### Pause

- medication → `paused`;
- current schedule → `paused`;
- pending and historical/final rows stay;
- future untouched `upcoming` rows are removed;
- no new occurrences are generated while paused.

### Resume

- medication/schedule → `active`;
- `generation_not_before_at` becomes the current minute;
- next 30-day window is regenerated;
- paused-period occurrences are not backfilled.

### Manual end

- medication → `ended`;
- schedule → `ended`;
- future untouched `upcoming` rows are removed;
- pending and historical rows stay.

### Natural completion

When `end_date` has fully elapsed in the schedule timezone and there are no non-final doses for that date or earlier, reconciliation changes medication to `completed` and schedule to `ended`.

## 9. Dose Actions and Idempotency

### Timestamp validation

For ordinary user actions, `occurred_at`:

- must be a valid UTC timestamp;
- cannot be more than 5 minutes in the server's future;
- may be older than the sync time so offline actions retain their real action time.

### Taken

Allowed from `upcoming` or `pending` when the caregiver confirms the dose was actually taken.

Sets current status `taken`, `taken_at=occurred_at`, clears snooze, appends `marked_taken`.

Early marking is allowed because FamilyMed records what the family reports; it does not redefine the reminder clock as clinical truth.

### Skip

Allowed from `upcoming` or `pending`.

Sets `skipped`, `skipped_at=occurred_at`, clears snooze, appends `skipped`.

### Duplicate retry

If the same `client_action_id` is received again, return the current dose projection without adding another log.

### Conflict

A different ordinary action against a final dose returns `409 DOSE_ALREADY_FINALIZED` and includes the current projection.

Snoozing a non-pending dose returns `409 DOSE_NOT_PENDING`.

### Correction

A final dose can be corrected to `taken`, `skipped`, or `missed`.

Correction payload contains:

- new `client_action_id`;
- `occurred_at` = when the correction was made;
- `new_status`;
- `effective_at` = timestamp associated with the corrected status;
- optional reason.

The backend updates the current status projection, keeps previous timestamps/logs, sets the new status timestamp from `effective_at`, and appends `corrected` metadata containing previous/new status, effective time, and reason.

History therefore remains auditable rather than being erased.

## 10. API Surface

All endpoints use existing bearer auth and error-envelope conventions.

### Schedules

```text
POST  /api/v1/member-medications/{medication_id}/schedules
GET   /api/v1/member-medications/{medication_id}/schedule
PATCH /api/v1/schedules/{schedule_id}
```

The GET returns the current active/paused schedule; if none exists, 404. Ended schedules remain historical data but are not returned as the current routine.

Create/update payload includes:

- `raw_instruction` nullable;
- `meal_relation`;
- `timezone`;
- `start_date`, optional `end_date`;
- `times[] { period, local_time, quantity, unit }`.

### Medication lifecycle

```text
POST /api/v1/member-medications/{medication_id}/pause
POST /api/v1/member-medications/{medication_id}/resume
POST /api/v1/member-medications/{medication_id}/end
```

### Today

```text
GET /api/v1/today
```

Returns every accessible family member plus that member's local-day doses. Each group includes member identity, local date/timezone, `taken_count`, `total_count`, and ordered dose projections.

`total_count` means all scheduled non-cancelled occurrences for that local day, including upcoming, pending, taken, skipped, and missed.

Dose projection includes medication name/strength, quantity/unit, meal relation, scheduled time, effective reminder time, status, and snooze fields.

### Dose actions

```text
POST /api/v1/doses/{dose_id}/taken
POST /api/v1/doses/{dose_id}/snooze
POST /api/v1/doses/{dose_id}/skip
POST /api/v1/doses/{dose_id}/correct
```

### History

```text
GET /api/v1/family-members/{member_id}/history?from=YYYY-MM-DD&to=YYYY-MM-DD
```

Default range: most recent 30 local days. Maximum range: 90 days.

History groups by local date and includes current dose projection plus its event log/corrections.

`marked_adherence_percentage` is:

```text
100 × taken_current_status / (taken + skipped + missed current statuses)
```

Upcoming/pending are excluded. If denominator is zero, return null. UI calls this **marked adherence**, never verified adherence.

### Notification preference

```text
GET   /api/v1/family-members/{member_id}/notification-preference
PATCH /api/v1/family-members/{member_id}/notification-preference
```

V1 mutable fields: `enabled`, `default_snooze_minutes`. Escalation is unavailable.

## 11. Flutter Experience

### Routine setup

A medication profile/card exposes **Set routine**.

Example:

```text
Metformin 500 mg
Source instruction: 1 + 0 + 1 • after food

Morning   8:00 AM   1 tablet
Night     8:00 PM   1 tablet

Reminder times are not part of the prescription.
```

Validation mirrors backend constraints. Submission is online-only. API failure keeps entered values intact.

### Enable reminders

After successful routine creation:

```text
Enable reminders
[ Enable reminders ]
[ Not now ]
```

Enable requests OS notification permission and turns on the backend preference only if the user enables reminders. Denial leaves the routine active and shows an explanatory state.

Not now leaves preference disabled and continues to Today.

### Today as authenticated home

For users with family members, successful login routes to `/today`. Restored authenticated sessions also default to `/today`. Registration with no family members still uses the existing care-for onboarding.

Example:

```text
Amma
2 / 3 marked taken

✓ 8:00 AM  Metformin 500 mg
✓ 8:00 AM  Amlodipine 5 mg
○ 8:00 PM  Metformin 500 mg
```

Status always has text/icon semantics; never color alone.

If Today API fails but local cache exists, render cache with an offline indicator.

### Dose action screen

```text
Amma's evening dose

Metformin 500 mg
1 tablet • After food
Scheduled 8:00 PM

[ Mark as taken ]
[ Snooze 15 min ]
[ Skip this dose ]

Taken status is based on family/user confirmation.
```

Taken/Skip update local UI optimistically. Snooze keeps status pending and changes effective reminder time.

### History

Member profile gains History access. Final doses can open **Correct record**. The UI shows corrections rather than pretending earlier history never existed.

## 12. Local Notifications

Flutter uses a `NotificationScheduler` abstraction so tests use a fake implementation.

Production rules:

- schedule only non-final cached doses when preference is enabled;
- deterministic notification ID derived from dose ID;
- finalizing cancels the pending notification;
- snooze replaces the reminder with `snoozed_until`;
- schedule edit/pause/end/refresh reconciles local notifications with current cached/server dose IDs;
- tapping a notification opens that dose's action screen;
- Android notification permission is requested only from the user's Enable action;
- exact-alarm permission is not required by this slice; use a plugin/platform scheduling mode that avoids restricted exact-alarm privileges and do not promise second-level exact delivery.

## 13. Offline Cache and Action Queue

Schedule creation/editing stays online-only. Today and dose actions support temporary offline use.

Drift schema adds at least:

### `cached_doses`

Stores the identifiers/display/status fields required to render Today/history without network access.

### `sync_operations`

Stores:

- operation/client action UUID;
- dose ID;
- action `taken | skip | snooze | correct`;
- JSON payload;
- created time;
- attempt count;
- last error nullable.

Flow:

```text
user action
  ↓
optimistic cached-dose update
  ↓
insert sync operation with stable client_action_id
  ↓
try API now
  ↓
success: replace local projection with server response + delete op
network failure: keep op
```

Queue drains opportunistically on:

- startup/session restore;
- app resume;
- immediately after queue insertion;
- after later successful API activity.

No connectivity-listener dependency is required solely for this.

Conflict handling:

- 401 → existing ApiClient refresh path;
- duplicate action ID → idempotent success;
- 409 final-state conflict → adopt server projection, remove local op, show non-destructive “record changed” feedback;
- confirmed 404 → remove stale cache/op;
- permanent 422 → keep user-visible failure but do not retry forever;
- transient/network/5xx → retain op for retry.

## 14. Error Codes

Use existing API error envelope.

Important codes:

- `ACTIVE_SCHEDULE_EXISTS` — 409
- `INVALID_TIMEZONE` — 422
- `INVALID_SCHEDULE` — 422
- `DOSE_ALREADY_FINALIZED` — 409
- `DOSE_NOT_PENDING` — 409
- `RESOURCE_NOT_FOUND` — 404

Flutter blocks duplicate button submission while a request is in flight; backend idempotency still protects retries.

## 15. Service Boundaries

Backend:

```text
app/schedules/
  models.py
  schemas.py
  repository.py
  service.py
  generation.py
  router.py

app/doses/
  schemas.py
  repository.py
  service.py
  reconciliation.py
  router.py

app/notifications/
  models.py
  schemas.py
  service.py
  router.py
```

`generation.py` owns occurrence creation. `reconciliation.py` owns time-derived transitions. Routers contain no scheduling logic.

Flutter:

```text
features/schedules/
features/today/
features/doses/
features/history/
core/notifications/
core/sync/
```

Platform notifications are behind an interface. Sync code is independent of widgets/navigation.

## 16. Testing Strategy

### Backend/PostgreSQL

Tests cover:

- migrations and constraints;
- schedule creation activates draft medication;
- one active/paused schedule invariant;
- Asia/Dhaka local time → expected UTC;
- 30-day generation and end-date bounds;
- no duplicate occurrences on repeated reconciliation;
- no same-day backfill before `generation_not_before_at`;
- cross-family schedule/dose/history requests → 404;
- schedule edit preserves final/pending rows and replaces only future untouched upcoming rows;
- pause/resume/end semantics;
- natural completion;
- upcoming→pending transition;
- end-of-local-day missed transition;
- snooze across local midnight delays missed transition;
- snooze remains pending;
- Taken/Skip behavior;
- duplicate client action ID is idempotent;
- conflicting final action returns 409;
- correction preserves old logs/timestamps;
- Today grouping/count/order;
- marked-adherence calculation;
- notification preference defaults/updates.

### Flutter

Tests cover:

- routine form validation and retained values after error;
- reminder-vs-source disclaimer;
- notification permission denial leaves routine active;
- Today rendering and accessibility semantics;
- Taken/Skip optimistic updates;
- snooze remains pending;
- notification schedule/cancel/reschedule through fake scheduler;
- cached Today when API unavailable;
- offline queue creation;
- stable client action ID across retries;
- queue drain success;
- 409 conflict adopts server state;
- history correction;
- restored auth session defaults to Today;
- English/Bangla strings.

### Acceptance path

The slice is not complete until CI demonstrates:

```text
register/login
→ add Amma
→ add Metformin
→ create 08:00 + 20:00 routine
→ medication active
→ doses generated
→ Today shows today's doses
→ mark one Taken
→ summary updates
→ Snooze another
→ it remains Pending with snoozed_until
→ Skip a dose
→ History shows events
→ correct a final record and retain prior log
→ queue an offline action
→ later sync without duplicate log
→ edit schedule without rewriting prior history
→ second account cannot access the dose
```

Final gate:

- backend dependency sync;
- Ruff;
- Alembic upgrade on PostgreSQL 17;
- full pytest;
- Flutter dependency/code generation;
- `flutter analyze`;
- full Flutter tests;
- Android debug APK build.

## 17. Success Criteria

A FamilyMed caregiver can convert a medication into a reliable daily routine, see the canonical scheduled-dose ledger, receive local reminders when enabled, record dose outcomes during temporary network loss, and later understand/correct marked history without FamilyMed making a clinical claim it cannot verify.
