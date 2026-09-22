# Schedules, Doses, Today, and Reminders Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn an existing FamilyMed medication into a durable reminder routine with backend-generated dose occurrences, Today, Taken/Snooze/Skip, marked history, local Android notifications, and offline dose-action sync.

**Architecture:** FastAPI/PostgreSQL remains canonical for schedules, generated doses, lifecycle state, idempotent actions, and history. Flutter adds routine setup, Today, a 30-day reminder feed, local notifications, and a Drift-backed cache/action queue. Time-derived transitions are centralized in backend generation/reconciliation services so later worker infrastructure can reuse them without changing domain semantics.

**Tech Stack:** Python 3.13, FastAPI, SQLAlchemy 2.x async, PostgreSQL 17, Alembic, Pydantic, `zoneinfo`; Flutter/Dart, Riverpod, Dio, Drift/SQLite, go_router, `flutter_local_notifications`, `timezone`, Android local notifications.

**Spec:** `docs/superpowers/specs/2026-09-23-schedules-today-doses-design.md`

## Global Constraints

- The backend is the canonical source for schedules and dose occurrences.
- Source/prescription instruction and reminder clock times are separate data.
- Routine UI must say exactly: **“Reminder times are not part of the prescription.”**
- `taken` means family/user-confirmed status only; never claim verified ingestion.
- Snooze remains `status=pending` with `snoozed_until`; it is never a separate status.
- One member medication may have at most one current `active`/`paused` schedule.
- Generate a rolling 30-day window: member-local today through local date + 29 days, bounded by medication/schedule dates and `generation_not_before_at`.
- Future untouched `upcoming` rows may be replaced; due/final/event-bearing history may not be rewritten.
- A pending dose becomes missed only after its member-local day ends, or later if `snoozed_until` extends past that boundary.
- `client_action_id` is the idempotency key for user dose actions and must be reused unchanged during retries.
- Ordinary `occurred_at` may not be more than 5 minutes ahead of server time.
- Cross-family resources use the existing not-found behavior instead of revealing existence.
- Schedule creation/editing is online-only; Today viewing and dose actions support temporary offline use.
- Notification permission does not control schedule activation. Denial or “Not now” leaves the routine active.
- Android notifications use an inexact scheduling mode; do not request restricted exact-alarm permission or promise second-level exact delivery.
- Default snooze is 15 minutes.
- History UI/API call the metric `marked_adherence_percentage` / “marked adherence”, never verified adherence.
- All new user-visible strings are localized in English and Bangla.
- V1 local notifications are maintained from a server-backed 30-day reminder feed. Setup, authenticated startup, app resume, schedule mutation, and successful sync refresh that feed. If the app is not opened for more than 30 days, V1 does not guarantee notifications beyond the last cached window; a later background-worker/mobile-background-refresh slice can remove that limitation.

## Review Focus

1. **Idempotency key misuse:** Reusing one `client_action_id` for a different dose or action returns `409 IDEMPOTENCY_KEY_REUSED`. Pinned in Task 4.
2. **Future dose already acted on:** A schedule edit preserves an early-marked future dose because it is final/event-bearing even when `scheduled_at > now`. Pinned in Task 2.
3. **Duplicate reminder times:** Two times with the same local clock value but different period labels are still duplicate occurrences and must be rejected. Pinned in Task 2.
4. **Permanent offline replay failure:** A queued action receiving permanent `422` stops automatic retry, remains visibly failed, and cannot enter a retry loop. Pinned in Task 9.
5. **Notification denial/scheduling failure:** OS permission denial or platform scheduling failure never deactivates or rolls back a successfully created routine. Pinned in Task 7.

---

### Task 1: Persist schedules, dose ledger, audit logs, and notification preferences

**Files:**
- Create: `backend/app/schedules/__init__.py`
- Create: `backend/app/schedules/models.py`
- Create: `backend/app/doses/__init__.py`
- Create: `backend/app/doses/models.py`
- Create: `backend/app/notifications/__init__.py`
- Create: `backend/app/notifications/models.py`
- Create: `backend/migrations/versions/0003_schedules_doses_today.py`
- Modify: `backend/app/models.py`
- Test: `backend/tests/test_schedule_models.py`

**Interfaces:**
- Consumes: existing `Base`, `TimestampMixin`, `User`, `Family`, `FamilyMembership`, `FamilyMember`, and `MemberMedication` tables.
- Produces: `MedicationSchedule`, `ScheduleTime`, `ScheduledDose`, `DoseLog`, and `NotificationPreference` SQLAlchemy models.

- [ ] **Step 1: Write the failing model test with a local seed helper**

Keep the fixture self-contained in `backend/tests/test_schedule_models.py` so no new global fixture contract is introduced:

```python
async def _seed_medication(session: AsyncSession) -> MemberMedication:
    user = User(
        name="Caregiver",
        email=f"caregiver-{uuid4()}@example.com",
        password_hash="test-hash",
        preferred_language="en",
        timezone="Asia/Dhaka",
    )
    session.add(user)
    await session.flush()
    family = Family(name="Caregiver's family", created_by_user_id=user.id)
    session.add(family)
    await session.flush()
    session.add(FamilyMembership(
        family_id=family.id,
        user_id=user.id,
        role="owner",
        status="active",
    ))
    member = FamilyMember(
        family_id=family.id,
        name="Amma",
        relationship="mother",
        preferred_language="bn",
        timezone="Asia/Dhaka",
    )
    session.add(member)
    await session.flush()
    medication = MemberMedication(
        family_member_id=member.id,
        display_name="Metformin",
        strength="500 mg",
        status="draft",
        start_date=date(2026, 9, 23),
        created_by_user_id=user.id,
    )
    session.add(medication)
    await session.flush()
    return medication
```

Then insert schedule → schedule time → dose → dose log → notification preference and assert all IDs persist.

Also deliberately insert invalid schedule status, invalid dose status, non-positive quantity, blank unit, duplicate schedule time, and duplicate dose occurrence and assert PostgreSQL raises `IntegrityError`.

- [ ] **Step 2: Run RED**

```bash
cd backend
uv run pytest tests/test_schedule_models.py -v
```

Expected: import/collection failure because the new models do not exist.

- [ ] **Step 3: Implement SQLAlchemy models with `String` status columns plus explicit CHECK constraints**

Use `String` rather than SQLAlchemy/PostgreSQL enum types, matching the existing codebase style. Core shapes:

```python
class MedicationSchedule(TimestampMixin, Base):
    __tablename__ = "medication_schedules"
    __table_args__ = (
        CheckConstraint("status IN ('active','paused','ended')", name="ck_medication_schedule_status"),
        CheckConstraint("end_date IS NULL OR end_date >= start_date", name="ck_medication_schedule_dates"),
    )
    id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
    member_medication_id: Mapped[UUID] = mapped_column(Uuid, ForeignKey("member_medications.id"), nullable=False)
    raw_instruction: Mapped[str | None] = mapped_column(Text, nullable=True)
    meal_relation: Mapped[str | None] = mapped_column(String(32), nullable=True)
    timezone: Mapped[str] = mapped_column(String(64), nullable=False)
    start_date: Mapped[date] = mapped_column(nullable=False)
    end_date: Mapped[date | None] = mapped_column(nullable=True)
    generation_not_before_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    status: Mapped[str] = mapped_column(String(20), nullable=False)
    created_by_user_id: Mapped[UUID] = mapped_column(Uuid, ForeignKey("users.id"), nullable=False)
```

```python
class ScheduleTime(TimestampMixin, Base):
    __tablename__ = "schedule_times"
    __table_args__ = (
        CheckConstraint("period IN ('morning','afternoon','evening','night','custom')", name="ck_schedule_time_period"),
        CheckConstraint("quantity > 0", name="ck_schedule_time_quantity"),
        CheckConstraint("length(trim(unit)) > 0", name="ck_schedule_time_unit"),
        UniqueConstraint("schedule_id", "local_time", name="uq_schedule_time_clock"),
    )
    id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
    schedule_id: Mapped[UUID] = mapped_column(Uuid, ForeignKey("medication_schedules.id", ondelete="CASCADE"), nullable=False)
    period: Mapped[str] = mapped_column(String(20), nullable=False)
    local_time: Mapped[time] = mapped_column(Time, nullable=False)
    quantity: Mapped[Decimal] = mapped_column(Numeric(10, 3), nullable=False)
    unit: Mapped[str] = mapped_column(String(40), nullable=False)
    sort_order: Mapped[int] = mapped_column(Integer, nullable=False)
```

`ScheduledDose` snapshots schedule/member/medication IDs, UTC `scheduled_at`, local date/time, timezone, quantity/unit/meal relation, state timestamps, and has CHECK `status IN ('upcoming','pending','taken','skipped','missed')` plus unique `(schedule_id, scheduled_local_date, scheduled_local_time)`.

`DoseLog` has CHECK action in `('became_pending','snoozed','marked_taken','skipped','missed','corrected')`, nullable user, nullable unique `client_action_id`, `occurred_at`, `recorded_at`, and PostgreSQL `JSONB metadata`.

`NotificationPreference` is unique on `(user_id, family_member_id)` and defaults to `enabled=False`, `default_snooze_minutes=15`, `caregiver_escalation_enabled=False`.

Add the partial unique PostgreSQL index:

```python
Index(
    "uq_current_schedule_per_medication",
    "member_medication_id",
    unique=True,
    postgresql_where=text("status IN ('active', 'paused')"),
)
```

- [ ] **Step 4: Add migration and model registration**

Create `0003_schedules_doses_today.py`:

```python
revision = "0003_schedules_doses_today"
down_revision = "0002_auth_family_medications"
```

Create tables in FK-safe order and reproduce the same CHECK/unique/partial-index guarantees in Alembic. Downgrade in reverse order. Import all new model classes from `backend/app/models.py` so metadata sees them.

- [ ] **Step 5: Verify GREEN**

```bash
cd backend
uv run ruff check .
uv run alembic upgrade head
uv run pytest tests/test_schedule_models.py -v
```

- [ ] **Step 6: Commit**

```bash
git add backend/app/schedules backend/app/doses backend/app/notifications backend/app/models.py backend/migrations/versions/0003_schedules_doses_today.py backend/tests/test_schedule_models.py
git commit -m "feat: add schedule and dose persistence"
```

---

### Task 2: Build schedule APIs and idempotent 30-day dose generation

**Files:**
- Create: `backend/app/schedules/schemas.py`
- Create: `backend/app/schedules/repository.py`
- Create: `backend/app/schedules/generation.py`
- Create: `backend/app/schedules/service.py`
- Create: `backend/app/schedules/router.py`
- Modify: `backend/app/main.py`
- Test: `backend/tests/test_schedules.py`

**Interfaces:**
- Consumes: Task 1 models and existing medication ownership helper.
- Produces:
  - `local_occurrence_to_utc(local_date: date, local_time: time, timezone_name: str) -> datetime`
  - `generate_schedule_window(session: AsyncSession, schedule_id: UUID, now_utc: datetime) -> list[ScheduledDose]`
  - schedule POST/GET/PATCH endpoints.

- [ ] **Step 1: Write RED schedule/generation tests**

Create schedule payload:

```python
payload = {
    "raw_instruction": "1+0+1 PC",
    "meal_relation": "after_food",
    "timezone": "Asia/Dhaka",
    "start_date": "2026-09-23",
    "end_date": None,
    "times": [
        {"period": "morning", "local_time": "08:00", "quantity": "1", "unit": "tablet"},
        {"period": "night", "local_time": "20:00", "quantity": "1", "unit": "tablet"},
    ],
}
```

Assert draft medication becomes active and a controlled `now_utc` creates only candidate occurrences on/after the current minute through local date +29.

Pin conversion:

```python
assert local_occurrence_to_utc(date(2026, 9, 24), time(8, 0), "Asia/Dhaka") == datetime(2026, 9, 24, 2, 0, tzinfo=timezone.utc)
```

Test invalid timezone → `422 INVALID_TIMEZONE`; zero/nine times → 422; duplicate `08:00` with different period labels → 422; second active schedule → `409 ACTIVE_SCHEDULE_EXISTS`; repeated generation remains duplicate-free; cross-family schedule access → 404.

For Review Focus #2, create a future dose, mark it `taken` with a `marked_taken` log, edit the schedule, and assert that exact dose/log survives while untouched future rows are replaced.

- [ ] **Step 2: Run RED**

```bash
cd backend
uv run pytest tests/test_schedules.py -v
```

- [ ] **Step 3: Implement Pydantic schedule schemas**

```python
class ScheduleTimeInput(BaseModel):
    period: Literal["morning", "afternoon", "evening", "night", "custom"]
    local_time: time
    quantity: Decimal = Field(gt=0, max_digits=10, decimal_places=3)
    unit: Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=40)]

class ScheduleCreate(BaseModel):
    raw_instruction: str | None = None
    meal_relation: Literal["before_food", "after_food", "with_food", "none", "unspecified"] | None = None
    timezone: str
    start_date: date
    end_date: date | None = None
    times: Annotated[list[ScheduleTimeInput], Field(min_length=1, max_length=8)]
```

A model validator rejects duplicate `local_time` values and `end_date < start_date`. Validate IANA timezone using `ZoneInfo`; map `ZoneInfoNotFoundError` to `422 INVALID_TIMEZONE`.

- [ ] **Step 4: Implement generation**

`generate_schedule_window()` loads schedule/medication/member/times, derives local today from `now_utc`, loops through today +29, respects medication/schedule dates, and skips any candidate before both `generation_not_before_at` and the current server minute floor.

Insert missing rows by unique occurrence key and snapshot timezone/quantity/unit/meal relation. Generation does not create a `DoseLog`.

- [ ] **Step 5: Implement create/update and routes**

Creation sets `generation_not_before_at` to current server minute and activates a draft medication in the same transaction.

Editing deletes only:

```python
ScheduledDose.status == "upcoming"
ScheduledDose.scheduled_at > now_utc
~exists(select(DoseLog.id).where(DoseLog.scheduled_dose_id == ScheduledDose.id))
```

Then replace schedule times and regenerate. Pending/final/event-bearing rows stay unchanged.

Expose the three schedule endpoints and include `schedule_router` in `backend/app/main.py`.

- [ ] **Step 6: Verify GREEN and commit**

```bash
cd backend
uv run ruff check .
uv run pytest tests/test_schedules.py tests/test_medications.py -v
git add app/schedules app/main.py tests/test_schedules.py
git commit -m "feat: add medication schedule generation"
```

---

### Task 3: Reconcile due/missed doses and medication lifecycle

**Files:**
- Create: `backend/app/doses/reconciliation.py`
- Modify: `backend/app/medications/service.py`
- Modify: `backend/app/medications/router.py`
- Modify: `backend/app/schedules/service.py`
- Test: `backend/tests/test_reconciliation.py`
- Test: `backend/tests/test_medication_lifecycle.py`

**Interfaces:**
- Consumes: Task 2 generation.
- Produces: `reconcile_schedule(session, schedule_id, now_utc)`, pause/resume/end services and routes.

- [ ] **Step 1: Write RED time/lifecycle tests**

At `2026-09-23T02:00:00Z`, an 08:00 Asia/Dhaka occurrence becomes `pending` and gets exactly one `became_pending` log.

A dose on local `2026-09-23` becomes missed no earlier than Dhaka next midnight (`2026-09-23T18:00:00Z`). If snoozed to `18:30Z`, reconciliation at `18:10Z` keeps it pending and after `18:30Z` marks it missed.

Assert pause removes only untouched future upcoming rows; resume changes `generation_not_before_at` to the resume minute and does not backfill the paused interval; manual end preserves pending/final history; natural completion waits until local end date elapsed and no non-final dose on/before it remains.

- [ ] **Step 2: Run RED**

```bash
cd backend
uv run pytest tests/test_reconciliation.py tests/test_medication_lifecycle.py -v
```

- [ ] **Step 3: Implement reconciliation**

For `upcoming` due rows, set pending and append one system log with `occurred_at=dose.scheduled_at`. For pending rows calculate next local midnight in the dose timezone, convert to UTC, and use:

```python
miss_threshold = max(local_day_end_utc, dose.snoozed_until or local_day_end_utc)
```

At/after threshold set `missed`, `missed_at=miss_threshold`, and append one `missed` log.

- [ ] **Step 4: Implement lifecycle endpoints**

Pause/end use the same untouched-upcoming deletion predicate as Task 2. Resume sets medication/schedule active, resets `generation_not_before_at`, and generates the next window. Natural completion changes medication to `completed` and schedule to `ended` only after the spec condition is met.

Expose:

```text
POST /api/v1/member-medications/{id}/pause
POST /api/v1/member-medications/{id}/resume
POST /api/v1/member-medications/{id}/end
```

- [ ] **Step 5: Verify GREEN and commit**

```bash
cd backend
uv run ruff check .
uv run pytest tests/test_reconciliation.py tests/test_medication_lifecycle.py -v
git add app/doses/reconciliation.py app/medications app/schedules/service.py tests/test_reconciliation.py tests/test_medication_lifecycle.py
git commit -m "feat: reconcile doses and medication lifecycle"
```

---

### Task 4: Implement idempotent dose actions, correction, and notification preferences

**Files:**
- Create: `backend/app/doses/schemas.py`
- Create: `backend/app/doses/repository.py`
- Create: `backend/app/doses/service.py`
- Create: `backend/app/doses/router.py`
- Create: `backend/app/notifications/schemas.py`
- Create: `backend/app/notifications/service.py`
- Create: `backend/app/notifications/router.py`
- Modify: `backend/app/main.py`
- Test: `backend/tests/test_dose_actions.py`
- Test: `backend/tests/test_notification_preferences.py`

**Interfaces:**
- Consumes: Task 3 reconciliation and existing family memberships.
- Produces: `DoseProjection`; Taken/Snooze/Skip/Correct APIs; notification preference GET/PATCH.

- [ ] **Step 1: Write RED action tests**

Use stable UUID payloads:

```python
{"client_action_id": str(action_id), "occurred_at": "2026-09-23T12:00:00Z"}
```

Assert Taken/Skip from upcoming or pending set final state/timestamp, clear snooze, and append one event. Snooze is pending-only and keeps `status="pending"`.

Repeat the exact action ID and assert success with unchanged log count. Different final action returns `409 DOSE_ALREADY_FINALIZED`. Cross-family dose ID returns 404. `occurred_at > server_now + 5 minutes` returns 422.

For Review Focus #1, reuse the same action ID on another dose and on another action for the same dose; both return `409 IDEMPOTENCY_KEY_REUSED`.

- [ ] **Step 2: Write RED correction/preference tests**

Correction body:

```python
{
    "client_action_id": str(uuid4()),
    "occurred_at": "2026-09-24T10:00:00Z",
    "new_status": "taken",
    "effective_at": "2026-09-23T12:12:00Z",
    "reason": "Recorded late by caregiver",
}
```

Assert prior missed timestamp/log remain and `corrected` metadata contains previous/new status and effective time.

Preference GET with no DB row returns `enabled=false`, `default_snooze_minutes=15`. PATCH accepts `enabled` and `default_snooze_minutes` in range 1–1440 and rejects client attempts to set escalation.

- [ ] **Step 3: Run RED**

```bash
cd backend
uv run pytest tests/test_dose_actions.py tests/test_notification_preferences.py -v
```

- [ ] **Step 4: Implement ownership/idempotency**

`require_accessible_dose()` joins dose → family member → family membership and maps absence to existing 404 error.

Lookup existing `DoseLog.client_action_id` before state validation. The same ID is idempotent only if both dose ID and mapped log action match; otherwise raise `IDEMPOTENCY_KEY_REUSED`.

- [ ] **Step 5: Implement services/routes and verify GREEN**

Each action reconciles first, validates timestamps, applies transition, logs once, commits, and returns `DoseProjection`. Correction retains prior timestamps/logs and sets the new status timestamp from `effective_at`.

```bash
cd backend
uv run ruff check .
uv run pytest tests/test_dose_actions.py tests/test_notification_preferences.py -v
git add app/doses app/notifications app/main.py tests/test_dose_actions.py tests/test_notification_preferences.py
git commit -m "feat: add idempotent dose actions"
```

---

### Task 5: Add Today, history, and the 30-day reminder feed

**Files:**
- Create: `backend/app/doses/projections.py`
- Modify: `backend/app/doses/schemas.py`
- Modify: `backend/app/doses/router.py`
- Test: `backend/tests/test_today.py`
- Test: `backend/tests/test_history.py`
- Test: `backend/tests/test_reminder_feed.py`

**Interfaces:**
- Consumes: generation/reconciliation/actions.
- Produces:
  - `GET /api/v1/today`
  - `GET /api/v1/family-members/{member_id}/history`
  - `GET /api/v1/reminder-doses?days=30`.

- [ ] **Step 1: Write RED Today/history tests**

Today must group each member using that member's local date, include zero-dose members, order by effective reminder time, and return `taken_count`/`total_count`.

History default is most recent 30 member-local days, maximum 90. Pin marked adherence:

```python
# taken, taken, skipped, missed, pending
assert history.marked_adherence_percentage == Decimal("50.00")
```

No final statuses → null percentage. History includes event logs/corrections. Cross-family member → 404.

- [ ] **Step 2: Write RED reminder-feed tests**

`GET /api/v1/reminder-doses?days=30` returns only the authenticated user's accessible, non-final `upcoming|pending` doses for family members whose notification preference is enabled. It reconciles/generates before querying and returns dose ID, member ID, medication display, timezone, scheduled local date/time, UTC scheduled time, status, snooze, quantity/unit/meal relation.

Assert disabled preference excludes that member; `days=0` or `days=31` returns 422; cross-family rows never appear.

- [ ] **Step 3: Run RED**

```bash
cd backend
uv run pytest tests/test_today.py tests/test_history.py tests/test_reminder_feed.py -v
```

- [ ] **Step 4: Implement projections**

Before Today/history/feed reads, reconcile accessible schedules. Today includes all accessible members. Reminder feed is bounded to 1–30 days and final-state-free.

Calculate:

```python
final_count = taken + skipped + missed
percentage = None if final_count == 0 else (
    Decimal(taken) * 100 / Decimal(final_count)
).quantize(Decimal("0.01"))
```

- [ ] **Step 5: Verify full backend GREEN and commit**

```bash
cd backend
uv run ruff check .
uv run pytest tests/test_today.py tests/test_history.py tests/test_reminder_feed.py -v
uv run pytest -v
git add app/doses tests/test_today.py tests/test_history.py tests/test_reminder_feed.py
git commit -m "feat: add today history and reminder feed"
```

---

### Task 6: Add Flutter schedule/Today/reminder data contracts and Drift storage

**Files:**
- Modify: `mobile/lib/core/database/app_database.dart`
- Create: `mobile/lib/core/database/tables/cached_today_members.dart`
- Create: `mobile/lib/core/database/tables/cached_doses.dart`
- Create: `mobile/lib/core/database/tables/sync_operations.dart`
- Create: `mobile/lib/features/schedules/domain/medication_schedule.dart`
- Create: `mobile/lib/features/schedules/data/schedule_repository.dart`
- Create: `mobile/lib/features/today/domain/dose_projection.dart`
- Create: `mobile/lib/features/today/domain/today_member_group.dart`
- Create: `mobile/lib/features/today/data/today_repository.dart`
- Create: `mobile/lib/features/doses/data/reminder_dose_repository.dart`
- Test: `mobile/test/core/database/today_cache_test.dart`
- Test: `mobile/test/features/schedules/schedule_repository_test.dart`
- Test: `mobile/test/features/today/today_repository_test.dart`
- Test: `mobile/test/features/doses/reminder_dose_repository_test.dart`

**Interfaces:**
- Consumes: existing `ApiClient` and Riverpod/Drift patterns.
- Produces: `ScheduleRepository`, `TodayRepository`, `ReminderDoseRepository`, `DoseProjection`, `TodayMemberGroup`, and persisted future dose rows.

- [ ] **Step 1: Write RED Drift migration tests**

Fresh and upgraded DBs must reach schema version 2 and support three new tables.

`CachedTodayMembers`: member ID/name/relationship/local date/timezone/updatedAt.

`CachedDoses`: dose ID, member ID, medication ID/name/strength, `scheduledLocalDate`, `scheduledLocalTime`, `timezone`, `scheduledAt`, quantity as text, unit, meal relation, status, snooze, updatedAt.

`SyncOperations`: operation ID PK, dose ID, action, JSON payload, createdAt, attempt count, last error, `terminalFailure`.

Use `quantityText` to avoid floating-point display drift.

- [ ] **Step 2: Run RED**

```bash
cd mobile
flutter test test/core/database/today_cache_test.dart
```

- [ ] **Step 3: Implement v1→v2 Drift migration**

```dart
@DriftDatabase(tables: [CachedTodayMembers, CachedDoses, SyncOperations])
class AppDatabase extends _$AppDatabase {
  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.createTable(cachedTodayMembers);
        await m.createTable(cachedDoses);
        await m.createTable(syncOperations);
      }
    },
  );
}
```

- [ ] **Step 4: Write RED repository tests**

`TodayRepository.loadToday()` parses `/today`, atomically upserts current-day member/dose rows, and on network failure returns cached result with `isOffline=true`.

`ScheduleRepository` exposes:

```dart
Future<MedicationSchedule> createSchedule(String medicationId, ScheduleDraft draft);
Future<MedicationSchedule?> getCurrentSchedule(String medicationId);
Future<MedicationSchedule> updateSchedule(String scheduleId, ScheduleDraft draft);
```

`ReminderDoseRepository.refreshWindow()` calls `/reminder-doses?days=30`, upserts future/current non-final rows, deletes stale future cached rows that have no queued sync operation, and returns the 30-day `List<DoseProjection>`.

- [ ] **Step 5: Implement parsers/repositories and verify GREEN**

```bash
cd mobile
flutter pub get
flutter gen-l10n
dart run build_runner build --delete-conflicting-outputs
flutter analyze
flutter test test/core/database/today_cache_test.dart test/features/schedules/schedule_repository_test.dart test/features/today/today_repository_test.dart test/features/doses/reminder_dose_repository_test.dart
git add lib/core/database lib/features/schedules lib/features/today lib/features/doses/data/reminder_dose_repository.dart test/core/database/today_cache_test.dart test/features/schedules test/features/today test/features/doses/reminder_dose_repository_test.dart
git commit -m "feat: add mobile routine and dose cache"
```

---

### Task 7: Build routine setup and local notification coordination

**Files:**
- Modify: `mobile/pubspec.yaml`
- Modify: `mobile/android/app/src/main/AndroidManifest.xml`
- Create: `mobile/lib/core/notifications/notification_scheduler.dart`
- Create: `mobile/lib/core/notifications/flutter_notification_scheduler.dart`
- Create: `mobile/lib/core/notifications/reminder_coordinator.dart`
- Create: `mobile/lib/features/schedules/presentation/set_routine_screen.dart`
- Create: `mobile/lib/features/schedules/presentation/enable_reminders_screen.dart`
- Create: `mobile/lib/features/schedules/data/notification_preference_repository.dart`
- Modify: `mobile/lib/features/family/presentation/member_profile_screen.dart`
- Modify: `mobile/lib/app/router.dart`
- Modify: `mobile/lib/l10n/app_en.arb`
- Modify: `mobile/lib/l10n/app_bn.arb`
- Test: `mobile/test/features/schedules/set_routine_flow_test.dart`
- Test: `mobile/test/core/notifications/reminder_coordinator_test.dart`

**Interfaces:**
- Consumes: schedule repository, reminder dose feed, cached doses.
- Produces: `NotificationScheduler` and `ReminderCoordinator.refresh()`.

- [ ] **Step 1: Add verified Flutter dependencies**

```bash
cd mobile
flutter pub add flutter_local_notifications timezone
```

Commit resolver-selected compatible versions. Add only:

```xml
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
```

Do not add exact-alarm permissions.

- [ ] **Step 2: Write RED routine/notification tests**

Assert exact disclaimer:

```dart
expect(find.text('Reminder times are not part of the prescription.'), findsOneWidget);
```

Test 1–8 schedule rows, unique local time, positive quantity, retained form after API failure, create/edit routes.

For Review Focus #5, fake permission denial and separately make the scheduler throw. The routine remains server-active; UI offers “Continue to Today”.

- [ ] **Step 3: Implement notification abstraction**

```dart
abstract interface class NotificationScheduler {
  Future<bool> requestPermission();
  Future<void> reconcile(List<DoseProjection> doses);
  Future<void> cancelDose(String doseId);
  Future<void> snoozeDose(DoseProjection dose);
}
```

Production uses deterministic 31-bit IDs derived from dose UUID/string, payload `dose:<uuid>`, `AndroidScheduleMode.inexactAllowWhileIdle`, and timezone package initialization. `reconcile()` schedules non-final future/effective reminders and cancels cached IDs absent from the refreshed feed.

- [ ] **Step 4: Implement `ReminderCoordinator`**

`refresh()` performs:

```text
ReminderDoseRepository.refreshWindow()
→ NotificationScheduler.reconcile(feed)
```

It is single-flight to avoid overlapping platform scheduling work.

After successful create/edit routine, refresh the coordinator. Enable flow requests permission; if granted PATCH preference enabled then refresh; if denied leave preference/routine safe and continue. “Not now” keeps preference disabled and routes to `/today`.

- [ ] **Step 5: Verify GREEN and commit**

```bash
cd mobile
flutter gen-l10n
dart run build_runner build --delete-conflicting-outputs
flutter analyze
flutter test test/features/schedules/set_routine_flow_test.dart test/core/notifications/reminder_coordinator_test.dart
git add pubspec.yaml pubspec.lock android/app/src/main/AndroidManifest.xml lib/core/notifications lib/features/schedules lib/features/family/presentation/member_profile_screen.dart lib/app/router.dart lib/l10n test/features/schedules/set_routine_flow_test.dart test/core/notifications/reminder_coordinator_test.dart
git commit -m "feat: add routine setup and local reminders"
```

---

### Task 8: Make Today the authenticated home with cached/offline rendering

**Files:**
- Create: `mobile/lib/features/today/presentation/today_screen.dart`
- Create: `mobile/lib/features/today/presentation/dose_card.dart`
- Modify: `mobile/lib/app/router.dart`
- Modify: `mobile/lib/features/auth/presentation/login_screen.dart`
- Modify: `mobile/lib/l10n/app_en.arb`
- Modify: `mobile/lib/l10n/app_bn.arb`
- Test: `mobile/test/features/today/today_screen_test.dart`
- Modify/Test: `mobile/test/features/auth/auth_flow_test.dart`

**Interfaces:**
- Consumes: `TodayRepository`.
- Produces: protected `/today` route; dose cards target `/doses/:doseId`.

- [ ] **Step 1: Write RED routing/rendering tests**

Assert returning login/restored session defaults to `/today`; registration/login with zero members still uses `/care-for`.

Render:

```dart
expect(find.text('Amma'), findsOneWidget);
expect(find.text('2 / 3 marked taken'), findsOneWidget);
expect(find.text('Metformin 500 mg'), findsWidgets);
```

Status has text/icon semantics, never color alone. Cached repository result with `isOffline=true` renders an offline indicator and doses.

- [ ] **Step 2: Implement Today and router**

Add `/today` to protected paths. Authenticated welcome/splash redirect defaults to Today while explicit zero-member login/register behavior still navigates to care-for.

Use Riverpod `AsyncValue`, pull-to-refresh, grouped member cards, ordered dose cards, and the offline banner.

- [ ] **Step 3: Verify GREEN and commit**

```bash
cd mobile
flutter gen-l10n
flutter analyze
flutter test test/features/today/today_screen_test.dart test/features/auth/auth_flow_test.dart
git add lib/features/today lib/app/router.dart lib/features/auth/presentation/login_screen.dart lib/l10n test/features/today/today_screen_test.dart test/features/auth/auth_flow_test.dart
git commit -m "feat: add today dashboard"
```

---

### Task 9: Add optimistic dose actions and durable offline sync

**Files:**
- Create: `mobile/lib/features/doses/data/dose_repository.dart`
- Create: `mobile/lib/features/doses/presentation/dose_action_screen.dart`
- Create: `mobile/lib/core/sync/sync_coordinator.dart`
- Create: `mobile/lib/core/sync/api_activity_events.dart`
- Create: `mobile/lib/core/sync/sync_events.dart`
- Modify: `mobile/lib/core/api/api_client.dart`
- Modify: `mobile/lib/core/auth/auth_controller.dart`
- Modify: `mobile/lib/app/app.dart`
- Modify: `mobile/lib/app/router.dart`
- Modify: `mobile/lib/features/today/data/today_repository.dart`
- Modify: `mobile/lib/core/notifications/reminder_coordinator.dart`
- Modify: `mobile/lib/l10n/app_en.arb`
- Modify: `mobile/lib/l10n/app_bn.arb`
- Test: `mobile/test/core/sync/sync_coordinator_test.dart`
- Test: `mobile/test/features/doses/dose_action_screen_test.dart`

**Interfaces:**
- Consumes: Drift cached doses/sync operations, ApiClient refresh behavior, reminder coordinator.
- Produces: offline-capable `DoseRepository.markTaken/snooze/skip/correct`, `SyncCoordinator.drain()`, `/doses/:doseId`.

- [ ] **Step 1: Write RED optimistic/offline tests**

Taken offline immediately changes cached state and creates one operation. The generated operation UUID is also the serialized `client_action_id` and remains stable across retries.

Snooze keeps status pending and changes `snoozedUntil`. Skip updates final state. Fake reminder coordinator confirms notification state is refreshed after successful/optimistic changes.

- [ ] **Step 2: Pin replay failure semantics**

409 final conflict: adopt server projection, delete op, emit `recordChanged` sync event.

404: remove stale cached dose and operation.

Network/5xx: retain op and increment attempts.

For Review Focus #4, 422 marks `terminalFailure=true`; a second `drain()` leaves attempt count unchanged.

- [ ] **Step 3: Implement API activity events without circular dependency**

```dart
class ApiActivityEvents {
  final _controller = StreamController<void>.broadcast();
  Stream<void> get successes => _controller.stream;
  void notifySuccess() => _controller.add(null);
  Future<void> dispose() => _controller.close();
}
```

Add `apiActivityEventsProvider` alongside existing API/auth providers in `auth_controller.dart`, inject it into `ApiClient`, and emit only after a public `get/post/patch` wrapper successfully returns.

`SyncCoordinator` subscribes and uses one `_drainFuture` single-flight guard so replay API calls cannot cause recursive drain work.

- [ ] **Step 4: Implement optimistic transaction and queue**

Within one Drift transaction: save previous projection in operation JSON metadata, apply optimistic dose state, insert `SyncOperation`. Then attempt `drain()`.

On successful replay replace cache from server response, delete op, and call `ReminderCoordinator.refresh()` so final/snoozed notifications match canonical state.

- [ ] **Step 5: Trigger queue/reminder refresh at required lifecycle points**

Convert `FamilyMedApp` to `ConsumerStatefulWidget` + `WidgetsBindingObserver`.

On authenticated state and app resume:

```dart
await ref.read(syncCoordinatorProvider).drain();
await ref.read(reminderCoordinatorProvider).refresh();
```

Also drain immediately after queue insertion; guarded API-success events trigger another drain. Schedule create/edit already refreshes reminders in Task 7.

- [ ] **Step 6: Implement dose action screen**

Show medication, quantity/unit, meal relation, scheduled time, Taken/Snooze 15 min/Skip and exact safety copy: **“Taken status is based on family/user confirmation.”** Disable duplicate local submissions while the Drift transaction runs.

- [ ] **Step 7: Verify GREEN and commit**

```bash
cd mobile
flutter gen-l10n
dart run build_runner build --delete-conflicting-outputs
flutter analyze
flutter test test/core/sync/sync_coordinator_test.dart test/features/doses/dose_action_screen_test.dart test/features/today/today_screen_test.dart
git add lib/core/api lib/core/auth/auth_controller.dart lib/core/sync lib/core/notifications/reminder_coordinator.dart lib/app lib/features/doses lib/features/today/data/today_repository.dart lib/l10n test/core/sync/sync_coordinator_test.dart test/features/doses/dose_action_screen_test.dart test/features/today/today_screen_test.dart
git commit -m "feat: add offline dose action sync"
```

---

### Task 10: Add member history and correction UI

**Files:**
- Create: `mobile/lib/features/history/domain/member_history.dart`
- Create: `mobile/lib/features/history/data/history_repository.dart`
- Create: `mobile/lib/features/history/presentation/member_history_screen.dart`
- Create: `mobile/lib/features/history/presentation/correct_record_screen.dart`
- Modify: `mobile/lib/features/family/presentation/member_profile_screen.dart`
- Modify: `mobile/lib/app/router.dart`
- Modify: `mobile/lib/l10n/app_en.arb`
- Modify: `mobile/lib/l10n/app_bn.arb`
- Test: `mobile/test/features/history/history_flow_test.dart`

**Interfaces:**
- Consumes: backend history and Task 9 offline-capable correction path.
- Produces: member History access and explicit correction UI.

- [ ] **Step 1: Write RED history/correction tests**

Mock missed then corrected-to-taken history. Assert both events remain visible and summary label is “Marked adherence”.

Correct a final dose with target status/effective time/reason and assert it queues action `correct` with one stable client ID.

- [ ] **Step 2: Implement history/repository/screens**

`HistoryRepository.load(memberId, from, to)` is online-only; transient failure shows an error because only Today is required offline.

Member profile gains History. History groups by local date, shows current projection plus event timeline, and exposes **Correct record** only for final doses.

- [ ] **Step 3: Verify GREEN and commit**

```bash
cd mobile
flutter gen-l10n
flutter analyze
flutter test test/features/history/history_flow_test.dart
git add lib/features/history lib/features/family/presentation/member_profile_screen.dart lib/app/router.dart lib/l10n test/features/history/history_flow_test.dart
git commit -m "feat: add marked medication history"
```

---

### Task 11: Add vertical-slice acceptance coverage and run the final gate

**Files:**
- Create: `backend/tests/test_schedules_today_vertical_slice.py`
- Create: `mobile/test/features/schedules_today_acceptance_test.dart`
- Modify: `README.md` only if the new local-notification dependency or developer commands require documentation.

**Interfaces:**
- Consumes: Tasks 1–10.
- Produces: final acceptance proof and verification evidence.

- [ ] **Step 1: Write backend HTTP acceptance test**

Exercise real PostgreSQL-backed HTTP flow:

```text
register
→ add Amma
→ add Metformin
→ create 08:00 + 20:00 Asia/Dhaka routine
→ medication active
→ reconcile controlled now
→ Today
→ Taken
→ duplicate Taken retry has one log
→ Snooze pending dose and remain pending
→ Skip eligible dose
→ History
→ Correct final record and retain prior log
→ reminder feed contains only enabled-member non-final doses
→ edit schedule and preserve event-bearing history
→ second account gets 404 for dose
```

- [ ] **Step 2: Write Flutter acceptance test**

Use fake APIs/scheduler plus in-memory Drift:

```text
member profile
→ Set routine
→ Enable reminders / Not now
→ Today
→ dose action
→ Taken
→ offline Snooze queued
→ reconnect/drain
→ History
→ Correct record
```

Assert both safety/disclaimer strings appear and a 30-day reminder feed refresh drives the fake scheduler.

- [ ] **Step 3: Run focused acceptance tests**

```bash
cd backend
uv run pytest tests/test_schedules_today_vertical_slice.py -v
cd ../mobile
flutter test test/features/schedules_today_acceptance_test.dart
```

- [ ] **Step 4: Run complete backend gate**

```bash
cd backend
uv sync --all-groups
uv run ruff check .
uv run alembic upgrade head
uv run pytest -v
```

Expected: all pass against PostgreSQL 17.

- [ ] **Step 5: Run complete mobile gate**

```bash
cd mobile
flutter pub get
flutter gen-l10n
dart run build_runner build --delete-conflicting-outputs
flutter analyze
flutter test
flutter build apk --debug
```

Expected: analyzer clean, all tests pass, Android debug APK builds.

- [ ] **Step 6: Check branch cleanliness/scope**

```bash
git status --short
git diff --check main...HEAD
git log --oneline --decorate main..HEAD
```

Expected: no unintended generated/untracked files; no whitespace errors; task commits only.

- [ ] **Step 7: Commit acceptance/docs**

```bash
git add backend/tests/test_schedules_today_vertical_slice.py mobile/test/features/schedules_today_acceptance_test.dart
git add README.md  # only when README was actually changed

git commit -m "test: verify schedules today dose flow"
```
