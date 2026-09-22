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
- A paused schedule never generates new future doses until resume.
- A pending dose becomes missed only after its member-local day ends, or later if `snoozed_until` extends past that boundary.
- `client_action_id` is the idempotency key for user dose actions and must be reused unchanged during retries.
- Ordinary `occurred_at` may not be more than 5 minutes ahead of server time.
- A correction `effective_at` must be at or before that correction's `occurred_at`.
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

Keep the seed helper in `backend/tests/test_schedule_models.py`:

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

Insert schedule → schedule time → dose → dose log → notification preference and assert persistence. Separately attempt invalid schedule status, invalid dose status, non-positive quantity, blank unit, duplicate schedule time, and duplicate dose occurrence and expect `IntegrityError`.

- [ ] **Step 2: Run RED**

```bash
cd backend
uv run pytest tests/test_schedule_models.py -v
```

Expected: new model imports fail.

- [ ] **Step 3: Implement SQLAlchemy models with String states + CHECK constraints**

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

`ScheduledDose` snapshots schedule/member/medication IDs, UTC `scheduled_at`, local date/time, timezone, quantity/unit/meal relation, state timestamps, has CHECK `status IN ('upcoming','pending','taken','skipped','missed')`, and unique `(schedule_id, scheduled_local_date, scheduled_local_time)`.

`DoseLog` has CHECK action in `('became_pending','snoozed','marked_taken','skipped','missed','corrected')`, nullable user, nullable unique `client_action_id`, `occurred_at`, `recorded_at`, and PostgreSQL `JSONB metadata`.

`NotificationPreference` is unique on `(user_id, family_member_id)` and defaults to disabled / 15-minute snooze / escalation false.

Add the partial unique PostgreSQL index:

```python
Index(
    "uq_current_schedule_per_medication",
    "member_medication_id",
    unique=True,
    postgresql_where=text("status IN ('active', 'paused')"),
)
```

- [ ] **Step 4: Add migration and registration**

`backend/migrations/versions/0003_schedules_doses_today.py`:

```python
revision = "0003_schedules_doses_today"
down_revision = "0002_auth_family_medications"
```

Create tables in FK-safe order with the same DB constraints; downgrade in reverse order. Register all model classes from `backend/app/models.py`.

- [ ] **Step 5: Verify GREEN and commit**

```bash
cd backend
uv run ruff check .
uv run alembic upgrade head
uv run pytest tests/test_schedule_models.py -v
git add app/schedules app/doses app/notifications app/models.py migrations/versions/0003_schedules_doses_today.py tests/test_schedule_models.py
git commit -m "feat: add schedule and dose persistence"
```

---

### Task 2: Build schedule APIs and idempotent 30-day generation

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
- Produces `local_occurrence_to_utc(...)`, `generate_schedule_window(...)`, and schedule POST/GET/PATCH.

- [ ] **Step 1: Write RED schedule/generation tests**

Use:

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

Assert draft medication becomes active and controlled `now_utc` creates only occurrences on/after current minute through local date +29.

```python
assert local_occurrence_to_utc(date(2026, 9, 24), time(8), "Asia/Dhaka") == datetime(2026, 9, 24, 2, tzinfo=timezone.utc)
```

Test invalid timezone → `422 INVALID_TIMEZONE`; zero/nine times → 422; time with seconds/microseconds → 422; duplicate `08:00` under different period labels → 422; second current schedule → `409 ACTIVE_SCHEDULE_EXISTS`; repeat generation is duplicate-free; cross-family access → 404.

For Review Focus #2, early-mark a future dose `taken` with a log, edit the schedule, and assert exact dose/log survives while untouched future rows are replaced.

Also pause a schedule, edit its clock times, and assert no new future dose rows appear until resume.

- [ ] **Step 2: Run RED**

```bash
cd backend
uv run pytest tests/test_schedules.py -v
```

- [ ] **Step 3: Implement strict schemas**

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

Validate unique minute-precision local times, `end_date >= start_date`, and `ZoneInfo(timezone)`; map unknown timezone to `INVALID_TIMEZONE`.

- [ ] **Step 4: Implement generation**

`generate_schedule_window(session, schedule_id, now_utc)` loads schedule/medication/member/times, computes local today, iterates today..today+29, respects date bounds, and skips candidates before both `generation_not_before_at` and server current minute. It inserts missing rows by unique occurrence key and does not create generation logs.

- [ ] **Step 5: Implement create/update routes**

Create sets `generation_not_before_at` to current minute and activates a draft medication.

Edit preserves pending/final/event-bearing rows and deletes only:

```python
ScheduledDose.status == "upcoming"
ScheduledDose.scheduled_at > now_utc
~exists(select(DoseLog.id).where(DoseLog.scheduled_dose_id == ScheduledDose.id))
```

Replace schedule times transactionally. Call generation **only when `schedule.status == "active"`**; a paused schedule remains without future generated rows.

Expose POST/GET/PATCH and include router in `main.py`.

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
- Produces reconciliation plus pause/resume/end services and routes.

- [ ] **Step 1: Write RED time/lifecycle tests**

At `2026-09-23T02:00Z`, an 08:00 Asia/Dhaka occurrence becomes pending and gets exactly one `became_pending` log.

A local-2026-09-23 dose cannot become missed before `2026-09-23T18:00Z`. If snoozed to `18:30Z`, reconciliation at `18:10Z` stays pending; after `18:30Z` becomes missed.

Pause removes only untouched future upcoming rows; resume resets `generation_not_before_at` and does not backfill paused time; manual end preserves pending/final history; natural completion waits for local end-date completion and no non-final dose on/before it.

- [ ] **Step 2: Run RED**

```bash
cd backend
uv run pytest tests/test_reconciliation.py tests/test_medication_lifecycle.py -v
```

- [ ] **Step 3: Implement reconciliation**

Due upcoming rows become pending and append one system event with `occurred_at=scheduled_at`. Pending rows compute next local midnight UTC and:

```python
miss_threshold = max(local_day_end_utc, dose.snoozed_until or local_day_end_utc)
```

At threshold set missed/missed_at and append exactly one `missed` event.

- [ ] **Step 4: Implement lifecycle routes**

Pause/end use Task 2's untouched-future deletion predicate. Resume activates medication/schedule, resets generation boundary to current minute, then generates. Natural completion ends schedule and marks medication completed only after the approved condition.

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
- Consumes: Task 3 reconciliation and family memberships.
- Produces `DoseProjection`, Taken/Snooze/Skip/Correct, notification preference GET/PATCH.

- [ ] **Step 1: Write RED action tests**

```python
{"client_action_id": str(action_id), "occurred_at": "2026-09-23T12:00:00Z"}
```

Taken/Skip from upcoming or pending set final timestamp, clear snooze, append one event. Snooze is pending-only and remains pending. Exact duplicate action ID returns success with unchanged log count; a conflicting final action returns `DOSE_ALREADY_FINALIZED`; cross-family ID returns 404; `occurred_at > server_now + 5min` returns 422.

For Review Focus #1, reuse action ID on another dose or another action and expect `409 IDEMPOTENCY_KEY_REUSED`.

- [ ] **Step 2: Write RED correction/preference tests**

```python
{
    "client_action_id": str(uuid4()),
    "occurred_at": "2026-09-24T10:00:00Z",
    "new_status": "taken",
    "effective_at": "2026-09-23T12:12:00Z",
    "reason": "Recorded late by caregiver",
}
```

Prior missed timestamp/log remain; corrected metadata records previous/new status. `effective_at > occurred_at` returns 422.

Preference GET without a row returns disabled + 15 minutes. PATCH accepts `enabled` and snooze 1–1440 minutes and rejects escalation fields.

- [ ] **Step 3: Run RED**

```bash
cd backend
uv run pytest tests/test_dose_actions.py tests/test_notification_preferences.py -v
```

- [ ] **Step 4: Implement ownership/idempotency and services**

`require_accessible_dose()` joins dose → family member → active membership and returns existing 404 on absence.

Lookup `client_action_id` before state validation. It is idempotent only when both dose ID and mapped log action match; otherwise `IDEMPOTENCY_KEY_REUSED`.

Each action reconciles, validates, mutates, logs once, commits, returns `DoseProjection`. Correction retains old timestamps/logs and sets target timestamp from `effective_at`.

- [ ] **Step 5: Verify GREEN and commit**

```bash
cd backend
uv run ruff check .
uv run pytest tests/test_dose_actions.py tests/test_notification_preferences.py -v
git add app/doses app/notifications app/main.py tests/test_dose_actions.py tests/test_notification_preferences.py
git commit -m "feat: add idempotent dose actions"
```

---

### Task 5: Add Today, history, and a 30-day reminder feed

**Files:**
- Create: `backend/app/doses/projections.py`
- Modify: `backend/app/doses/schemas.py`
- Modify: `backend/app/doses/router.py`
- Test: `backend/tests/test_today.py`
- Test: `backend/tests/test_history.py`
- Test: `backend/tests/test_reminder_feed.py`

**Interfaces:**
- Consumes: generation/reconciliation/actions.
- Produces `/today`, member history, and `/reminder-doses?days=30`.

- [ ] **Step 1: Write RED Today/history tests**

Today groups by each member's local date, includes zero-dose members, orders by effective reminder time, and returns taken/total counts.

History defaults to 30 local days and caps at 90. Pin:

```python
# taken, taken, skipped, missed, pending
assert history.marked_adherence_percentage == Decimal("50.00")
```

No final statuses → null; event/correction logs included; cross-family member → 404.

- [ ] **Step 2: Write RED reminder-feed tests**

`GET /api/v1/reminder-doses?days=30` returns accessible non-final upcoming/pending doses only for family members whose current user's notification preference is enabled. It reconciles/generates before query and returns dose ID, member ID, medication display, timezone, local date/time, UTC scheduled time, status, snooze, quantity/unit/meal relation.

Disabled preference excludes member. `days=0|31` → 422. Cross-family rows never appear.

- [ ] **Step 3: Run RED**

```bash
cd backend
uv run pytest tests/test_today.py tests/test_history.py tests/test_reminder_feed.py -v
```

- [ ] **Step 4: Implement projections**

Reconcile accessible schedules before reads. Today includes all accessible family members. Reminder feed bounds days 1–30 and excludes final states.

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

### Task 6: Add Flutter schedule/Today/reminder contracts and Drift storage

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
- Consumes: existing ApiClient/Riverpod/Drift patterns.
- Produces `ScheduleRepository`, `TodayRepository`, `ReminderDoseRepository`, `DoseProjection`, `TodayMemberGroup` and future cached doses.

- [ ] **Step 1: Write RED Drift migration tests**

Schema v2 tables:

- `CachedTodayMembers`: member ID/name/relationship/local date/timezone/updatedAt.
- `CachedDoses`: dose ID, member ID, medication ID/name/strength, scheduled local date/time, timezone, UTC scheduled time, quantity text, unit, meal relation, status, snooze, updatedAt.
- `SyncOperations`: operation ID, dose ID, action, JSON payload, createdAt, attempt count, last error, terminal failure.

Use text quantity to avoid float display drift.

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

`TodayRepository.loadToday()` parses `/today`, atomically updates current-day cache, and on network failure returns cached groups with `isOffline=true`.

`ScheduleRepository`:

```dart
Future<MedicationSchedule> createSchedule(String medicationId, ScheduleDraft draft);
Future<MedicationSchedule?> getCurrentSchedule(String medicationId);
Future<MedicationSchedule> updateSchedule(String scheduleId, ScheduleDraft draft);
```

`ReminderDoseRepository.refreshWindow()` calls `/reminder-doses?days=30`, upserts current/future non-final rows, removes stale future rows with no queued sync operation, and returns a result containing the `List<DoseProjection>` plus `isOffline=false`.

On network failure it returns cached non-final doses with `isOffline=true`; it must not delete or overwrite any dose with a pending `SyncOperation`.

- [ ] **Step 5: Implement and verify GREEN**

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
- Consumes: schedule repo, reminder feed, cached doses.
- Produces `NotificationScheduler`, `ReminderCoordinator.refresh()`, `ReminderCoordinator.cancelMember(memberId)`.

- [ ] **Step 1: Add verified notification dependencies**

```bash
cd mobile
flutter pub add flutter_local_notifications timezone
```

Commit resolver-selected compatible versions. Manifest adds only:

```xml
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
```

No exact-alarm permission.

- [ ] **Step 2: Write RED routine/notification tests**

Assert exact disclaimer and validate 1–8 rows, unique minute times, positive quantity, retained form after API failure, create/edit routes.

For Review Focus #5, permission denial and scheduler platform failure both leave server routine active and offer “Continue to Today”.

Test offline reminder refresh uses cached feed rather than surfacing an error to an already successful dose/routine operation.

- [ ] **Step 3: Implement notification abstraction**

```dart
abstract interface class NotificationScheduler {
  Future<bool> requestPermission();
  Future<void> reconcile(List<DoseProjection> doses);
  Future<void> cancelDose(String doseId);
  Future<void> snoozeDose(DoseProjection dose);
}
```

Production derives deterministic 31-bit notification IDs from dose ID, payload `dose:<uuid>`, initializes timezone data once, and schedules with `AndroidScheduleMode.inexactAllowWhileIdle`.

`reconcile()` compares pending plugin notifications with refreshed dose IDs: schedules missing non-final reminders and cancels plugin dose notifications absent from feed.

- [ ] **Step 4: Implement reminder coordinator and screens**

```text
ReminderCoordinator.refresh()
→ ReminderDoseRepository.refreshWindow()
→ NotificationScheduler.reconcile(result.doses)
```

The coordinator is single-flight and treats cached `isOffline=true` results as valid input.

`cancelMember(memberId)` reads cached member dose IDs and cancels them explicitly.

After create/edit routine, refresh. Enable reminders: request permission → if granted PATCH preference enabled → refresh. Denial leaves preference/routine safe. “Not now” keeps disabled, cancels that member's locally cached notifications if any, routes `/today`.

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
- Consumes `TodayRepository`.
- Produces protected `/today`; dose cards target `/doses/:doseId`.

- [ ] **Step 1: Write RED routing/rendering tests**

Returning login/restored session defaults to Today; zero-member registration/login still uses care-for.

```dart
expect(find.text('Amma'), findsOneWidget);
expect(find.text('2 / 3 marked taken'), findsOneWidget);
expect(find.text('Metformin 500 mg'), findsWidgets);
```

Status uses text/icon semantics, never color only. Cached `isOffline=true` data renders with offline indicator.

- [ ] **Step 2: Implement Today/router**

Add `/today` protected route. Authenticated welcome/splash defaults to Today, while explicit zero-member login/register navigation remains care-for.

Use Riverpod `AsyncValue`, pull-to-refresh, grouped member cards, ordered dose cards, offline banner.

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
- Consumes cached doses/sync ops, ApiClient refresh, reminder coordinator.
- Produces offline-capable `DoseRepository.markTaken/snooze/skip/correct`, `SyncCoordinator.drain()`, `/doses/:doseId`.

- [ ] **Step 1: Write RED optimistic/offline tests**

Taken offline changes cache immediately and creates one operation whose UUID equals serialized `client_action_id`; retries preserve it. Snooze remains pending with new snooze time. Skip finalizes locally.

- [ ] **Step 2: Pin replay failure semantics**

409 final conflict → adopt server projection, delete op, emit `recordChanged`.

404 → delete stale cache/op.

Network/5xx → retain and increment attempts.

For Review Focus #4, 422 sets `terminalFailure=true`; later drains leave attempt count unchanged.

- [ ] **Step 3: Implement API activity events without a circular dependency**

```dart
class ApiActivityEvents {
  final _controller = StreamController<void>.broadcast();
  Stream<void> get successes => _controller.stream;
  void notifySuccess() => _controller.add(null);
  Future<void> dispose() => _controller.close();
}
```

Add provider beside current API/auth providers in `auth_controller.dart`, inject into `ApiClient`, emit only after public get/post/patch wrappers succeed. Sync coordinator subscribes with one `_drainFuture` single-flight guard so replay API calls cannot recursively start another drain.

- [ ] **Step 4: Implement optimistic transaction/replay**

In one Drift transaction save prior projection metadata, apply optimistic state, insert sync op. Then drain immediately.

Success replaces cache from server and deletes op. After local update or replay, call reminder coordinator. Its offline cached-feed path must make notification refresh best-effort; notification/network failure must never roll back the dose action.

- [ ] **Step 5: Trigger drain/reminder refresh on lifecycle**

Convert `FamilyMedApp` to `ConsumerStatefulWidget` + `WidgetsBindingObserver`.

On authenticated state and app resume:

```dart
await ref.read(syncCoordinatorProvider).drain();
await ref.read(reminderCoordinatorProvider).refresh();
```

Drain immediately after enqueue; guarded API-success events also trigger drain.

- [ ] **Step 6: Implement dose action screen**

Show medication, quantity/unit, meal relation, scheduled time, Taken/Snooze 15/Skip, and exact copy **“Taken status is based on family/user confirmation.”** Block duplicate local taps while transaction runs.

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
- Consumes history API and Task 9 correction path.
- Produces History access and explicit correction UI.

- [ ] **Step 1: Write RED history/correction tests**

Mock missed then corrected-to-taken history. Both events remain visible and summary label is “Marked adherence”. Correct final dose with target/effective time/reason; action `correct` uses one stable client ID.

- [ ] **Step 2: Implement history/screens**

`HistoryRepository.load(memberId, from, to)` is online-only; transient failure shows an error because full offline history is not required.

Member profile gains History. Group by local date, show current state + event timeline, expose **Correct record** only for final doses.

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

### Task 11: Add vertical-slice acceptance coverage and final gate

**Files:**
- Create: `backend/tests/test_schedules_today_vertical_slice.py`
- Create: `mobile/test/features/schedules_today_acceptance_test.dart`
- Modify: `README.md` only when developer setup/commands actually changed.

**Interfaces:**
- Consumes Tasks 1–10.
- Produces acceptance proof and final verification evidence.

- [ ] **Step 1: Write backend HTTP acceptance test**

```text
register
→ add Amma
→ add Metformin
→ create 08:00 + 20:00 Asia/Dhaka routine
→ active + doses generated
→ Today
→ Taken
→ duplicate retry creates one log
→ Snooze remains pending
→ Skip eligible dose
→ History
→ Correct final record and preserve prior log
→ enabled reminder feed returns non-final window
→ edit schedule preserves event-bearing history
→ second account gets 404 for dose
```

- [ ] **Step 2: Write Flutter acceptance test**

Use fake APIs/scheduler + in-memory Drift:

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

Assert both safety strings and reminder-feed-driven scheduler reconciliation.

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

Expected: all pass on PostgreSQL 17.

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

- [ ] **Step 6: Check branch state**

```bash
git status --short
git diff --check main...HEAD
git log --oneline --decorate main..HEAD
```

Expected: no unintended untracked/generated files; no whitespace errors; only task commits/spec/plan.

- [ ] **Step 7: Commit acceptance/docs**

```bash
git add backend/tests/test_schedules_today_vertical_slice.py mobile/test/features/schedules_today_acceptance_test.dart
git add README.md  # run this line only when README was actually changed
git commit -m "test: verify schedules today dose flow"
```
