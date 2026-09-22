# Schedules, Doses, Today, and Reminders Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn an existing FamilyMed medication into a durable reminder routine with backend-generated dose occurrences, Today, Taken/Snooze/Skip, marked history, local Android notifications, and offline dose-action sync.

**Architecture:** FastAPI/PostgreSQL remains canonical for schedules, generated doses, lifecycle state, idempotent actions, and history. Flutter adds routine setup, Today, notifications, and a Drift-backed cache/action queue; offline user actions update local projections optimistically and replay to the same idempotent APIs. Time-derived transitions are centralized in backend generation/reconciliation services so later worker infrastructure can reuse them without changing semantics.

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

## Review Focus

1. **Idempotency key misuse:** Reusing one `client_action_id` for a different dose or different action must return `409 IDEMPOTENCY_KEY_REUSED`, not silently return an unrelated projection. Pinned in Task 4.
2. **Future dose already acted on:** A schedule edit must preserve an early-marked future dose because it is final/event-bearing even though `scheduled_at > now`. Pinned in Task 2.
3. **Duplicate reminder times:** Two times with the same local clock value but different period labels must still be rejected as one duplicate occurrence. Pinned in Task 2.
4. **Permanent offline replay failure:** A queued action receiving permanent `422` must stop automatic retry, retain visible failed state, and avoid a retry loop. Pinned in Task 9.
5. **Notification denial/scheduling failure:** OS permission denial or platform scheduling failure must never deactivate or roll back a successfully created routine. Pinned in Task 7.

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
- Consumes: existing `Base`, `TimestampMixin`, `MemberMedication`, `FamilyMember`, and `User` tables.
- Produces: `MedicationSchedule`, `ScheduleTime`, `ScheduledDose`, `DoseLog`, `NotificationPreference` SQLAlchemy models used by all later backend tasks.

- [ ] **Step 1: Write failing persistence tests**

Create `backend/tests/test_schedule_models.py` with PostgreSQL-backed tests that insert the complete graph and assert constraints:

```python
@pytest.mark.asyncio
async def test_schedule_dose_log_and_notification_preference_persist(db_session, seeded_medication):
    schedule = MedicationSchedule(
        member_medication_id=seeded_medication.id,
        timezone="Asia/Dhaka",
        start_date=date(2026, 9, 23),
        generation_not_before_at=datetime(2026, 9, 23, 3, 0, tzinfo=timezone.utc),
        status="active",
        created_by_user_id=seeded_medication.created_by_user_id,
    )
    db_session.add(schedule)
    await db_session.flush()

    schedule_time = ScheduleTime(
        schedule_id=schedule.id,
        period="morning",
        local_time=time(8, 0),
        quantity=Decimal("1"),
        unit="tablet",
        sort_order=0,
    )
    db_session.add(schedule_time)
    await db_session.flush()

    dose = ScheduledDose(
        schedule_id=schedule.id,
        schedule_time_id=schedule_time.id,
        family_member_id=seeded_medication.family_member_id,
        member_medication_id=seeded_medication.id,
        scheduled_at=datetime(2026, 9, 24, 2, 0, tzinfo=timezone.utc),
        scheduled_local_date=date(2026, 9, 24),
        scheduled_local_time=time(8, 0),
        timezone="Asia/Dhaka",
        quantity=Decimal("1"),
        unit="tablet",
        status="upcoming",
    )
    db_session.add(dose)
    await db_session.commit()
    assert dose.id is not None
```

Also assert:

```python
assert set(ScheduledDose.__table__.c.status.type.enums) == {
    "upcoming", "pending", "taken", "skipped", "missed"
}
```

If status columns remain `String` instead of SQL enums, assert the migration CHECK constraints by attempting an invalid insert and expecting `IntegrityError`.

- [ ] **Step 2: Run the tests and verify RED**

Run:

```bash
cd backend
uv run pytest tests/test_schedule_models.py -v
```

Expected: collection/import failure because the new model modules do not exist.

- [ ] **Step 3: Add the SQLAlchemy models with database constraints**

Implement focused models. The important column shapes are:

```python
class MedicationSchedule(TimestampMixin, Base):
    __tablename__ = "medication_schedules"
    id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
    member_medication_id: Mapped[UUID] = mapped_column(
        Uuid, ForeignKey("member_medications.id"), nullable=False
    )
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
    id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
    schedule_id: Mapped[UUID] = mapped_column(
        Uuid, ForeignKey("medication_schedules.id", ondelete="CASCADE"), nullable=False
    )
    period: Mapped[str] = mapped_column(String(20), nullable=False)
    local_time: Mapped[time] = mapped_column(Time, nullable=False)
    quantity: Mapped[Decimal] = mapped_column(Numeric(10, 3), nullable=False)
    unit: Mapped[str] = mapped_column(String(40), nullable=False)
    sort_order: Mapped[int] = mapped_column(Integer, nullable=False)
```

```python
class ScheduledDose(TimestampMixin, Base):
    __tablename__ = "scheduled_doses"
    id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
    schedule_id: Mapped[UUID] = mapped_column(Uuid, ForeignKey("medication_schedules.id"), nullable=False)
    schedule_time_id: Mapped[UUID | None] = mapped_column(
        Uuid, ForeignKey("schedule_times.id", ondelete="SET NULL"), nullable=True
    )
    family_member_id: Mapped[UUID] = mapped_column(Uuid, ForeignKey("family_members.id"), nullable=False)
    member_medication_id: Mapped[UUID] = mapped_column(Uuid, ForeignKey("member_medications.id"), nullable=False)
    scheduled_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    scheduled_local_date: Mapped[date] = mapped_column(nullable=False)
    scheduled_local_time: Mapped[time] = mapped_column(Time, nullable=False)
    timezone: Mapped[str] = mapped_column(String(64), nullable=False)
    quantity: Mapped[Decimal] = mapped_column(Numeric(10, 3), nullable=False)
    unit: Mapped[str] = mapped_column(String(40), nullable=False)
    meal_relation: Mapped[str | None] = mapped_column(String(32), nullable=True)
    status: Mapped[str] = mapped_column(String(20), nullable=False, default="upcoming")
    snoozed_until: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    taken_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    skipped_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    missed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
```

`DoseLog` contains `action`, nullable `performed_by_user_id`, nullable unique `client_action_id`, `occurred_at`, server `recorded_at`, and PostgreSQL `JSONB metadata`. `NotificationPreference` is unique on `(user_id, family_member_id)`.

Add database checks for allowed statuses/periods, positive quantity, nonblank unit, `end_date >= start_date`, and unique `(schedule_id, local_time)` plus unique `(schedule_id, scheduled_local_date, scheduled_local_time)`.

Add a partial unique index on `medication_schedules(member_medication_id)` where status is `active` or `paused`.

- [ ] **Step 4: Add migration and model registration**

Create `0003_schedules_doses_today.py` with:

```python
revision = "0003_schedules_doses_today"
down_revision = "0002_auth_family_medications"
```

Create tables in FK-safe order: `medication_schedules`, `schedule_times`, `scheduled_doses`, `dose_logs`, `notification_preferences`. Downgrade in reverse order. Import the new models from `backend/app/models.py` so Alembic metadata sees them.

- [ ] **Step 5: Verify GREEN including migration**

Run:

```bash
cd backend
uv run ruff check .
uv run alembic upgrade head
uv run pytest tests/test_schedule_models.py -v
```

Expected: all commands pass.

- [ ] **Step 6: Commit Task 1**

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
- Consumes: `MedicationSchedule`, `ScheduleTime`, `ScheduledDose`; existing `require_accessible_medication(..., for_write=True)` ownership helper.
- Produces:
  - `local_occurrence_to_utc(local_date: date, local_time: time, timezone_name: str) -> datetime`
  - `generate_schedule_window(session: AsyncSession, schedule_id: UUID, now_utc: datetime) -> list[ScheduledDose]`
  - `create_schedule(...) -> MedicationSchedule`
  - `update_schedule(...) -> MedicationSchedule`
  - schedule REST endpoints used by Flutter Task 6.

- [ ] **Step 1: Write RED API/generation tests**

Create tests for:

```python
@pytest.mark.asyncio
async def test_create_schedule_activates_draft_medication_and_generates_window(client, auth_headers, medication_id):
    response = await client.post(
        f"/api/v1/member-medications/{medication_id}/schedules",
        headers=auth_headers,
        json={
            "raw_instruction": "1+0+1 PC",
            "meal_relation": "after_food",
            "timezone": "Asia/Dhaka",
            "start_date": "2026-09-23",
            "end_date": None,
            "times": [
                {"period": "morning", "local_time": "08:00", "quantity": "1", "unit": "tablet"},
                {"period": "night", "local_time": "20:00", "quantity": "1", "unit": "tablet"},
            ],
        },
    )
    assert response.status_code == 201
    assert response.json()["status"] == "active"
```

Pin time through an explicit `now_utc` parameter in service/generation tests rather than monkeypatching `datetime` globally.

Add tests asserting:

```python
assert local_occurrence_to_utc(date(2026, 9, 24), time(8, 0), "Asia/Dhaka") == datetime(
    2026, 9, 24, 2, 0, tzinfo=timezone.utc
)
```

Also test: invalid timezone → `422 INVALID_TIMEZONE`; 0 or 9 times → 422; duplicate `08:00` with periods `morning` and `custom` → 422; second active schedule → `409 ACTIVE_SCHEDULE_EXISTS`; repeated generation creates no duplicate dose rows; another account gets 404.

For Review Focus #2, create an upcoming future dose, mark it final with a `DoseLog`, edit the schedule, and assert that dose ID still exists unchanged while untouched future rows are regenerated.

- [ ] **Step 2: Run tests and verify RED**

```bash
cd backend
uv run pytest tests/test_schedules.py -v
```

Expected: imports/routes fail because schedule services do not exist.

- [ ] **Step 3: Implement strict schemas and timezone validation**

Use Pydantic models whose time list validation normalizes clock values and rejects duplicates regardless of `period`:

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

Validate timezone with `ZoneInfo(name)` and convert `ZoneInfoNotFoundError` into `ApiError(422, "INVALID_TIMEZONE", ...)`.

- [ ] **Step 4: Implement generation as one focused service**

`local_occurrence_to_utc()` combines wall clock and `ZoneInfo` then converts to UTC. `generate_schedule_window()`:

1. loads schedule, medication, member, and times;
2. derives member-local `today` from `now_utc` in schedule timezone;
3. iterates today through today + 29 days;
4. respects schedule/medication start and end dates;
5. skips candidates `< max(schedule.generation_not_before_at, floor_to_minute(now_utc))`;
6. inserts missing occurrences using the unique occurrence key;
7. snapshots quantity/unit/meal relation/timezone.

Do not add a `DoseLog` during generation.

- [ ] **Step 5: Implement create/update behavior and router**

On create, set:

```python
now_floor = now_utc.replace(second=0, microsecond=0)
schedule = MedicationSchedule(
    ...,
    generation_not_before_at=now_floor,
    status="active",
)
if medication.status == "draft":
    medication.status = "active"
```

On update, preserve all final/pending/event-bearing rows and delete only rows satisfying:

```python
ScheduledDose.status == "upcoming"
ScheduledDose.scheduled_at > now_utc
~exists(select(DoseLog.id).where(DoseLog.scheduled_dose_id == ScheduledDose.id))
```

Replace schedule times transactionally, then regenerate.

Expose POST/GET/PATCH endpoints from the spec and include `schedule_router` under `/api/v1` in `main.py`.

- [ ] **Step 6: Verify GREEN**

```bash
cd backend
uv run ruff check .
uv run pytest tests/test_schedules.py tests/test_medications.py -v
```

Expected: all pass.

- [ ] **Step 7: Commit Task 2**

```bash
git add backend/app/schedules backend/app/main.py backend/tests/test_schedules.py
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
- Consumes: Task 2 generation API and schedule models.
- Produces:
  - `reconcile_schedule(session: AsyncSession, schedule_id: UUID, now_utc: datetime) -> None`
  - `pause_medication(...)`, `resume_medication(...)`, `end_medication(...)`
  - lifecycle REST endpoints from the spec.

- [ ] **Step 1: Write failing reconciliation/lifecycle tests**

Pin these transitions:

```python
await reconcile_schedule(session, schedule.id, datetime(2026, 9, 23, 2, 0, tzinfo=timezone.utc))
assert morning_dose.status == "pending"
assert [log.action for log in morning_dose.logs] == ["became_pending"]
```

For missed behavior, a Dhaka dose from `2026-09-23` becomes missed only after local midnight (`2026-09-23 18:00 UTC`). For a snoozed dose whose `snoozed_until` is `18:30 UTC`, reconciliation at `18:10` keeps pending and reconciliation after `18:30` marks missed.

Add lifecycle tests asserting pause removes only untouched future upcoming rows; resume sets `generation_not_before_at` to the resume minute and does not backfill the paused interval; manual end preserves pending/final rows; natural completion waits until end local date is fully elapsed and no non-final dose remains.

- [ ] **Step 2: Run tests and verify RED**

```bash
cd backend
uv run pytest tests/test_reconciliation.py tests/test_medication_lifecycle.py -v
```

Expected: missing reconciliation/lifecycle functions.

- [ ] **Step 3: Implement reconciliation**

Use one transaction and explicit `now_utc`. For each active/paused schedule dose:

```python
if dose.status == "upcoming" and dose.scheduled_at <= now_utc:
    dose.status = "pending"
    session.add(DoseLog(
        scheduled_dose_id=dose.id,
        action="became_pending",
        performed_by_user_id=None,
        occurred_at=dose.scheduled_at,
        recorded_at=now_utc,
        metadata={},
    ))
```

Compute local-day end as next local midnight converted to UTC. For pending doses:

```python
miss_threshold = max(local_day_end_utc, dose.snoozed_until or local_day_end_utc)
if now_utc >= miss_threshold:
    dose.status = "missed"
    dose.missed_at = miss_threshold
```

Append exactly one `missed` event.

- [ ] **Step 4: Implement pause/resume/end/natural completion**

Lifecycle functions require writable medication access. Pause/end delete only untouched future upcoming rows using the same predicate as Task 2. Resume sets schedule and medication active, updates `generation_not_before_at` to the current minute, and calls generation.

Natural completion changes medication to `completed` and schedule to `ended` only when the schedule end local date has elapsed and no non-final dose on/before that date remains.

Expose:

```text
POST /api/v1/member-medications/{id}/pause
POST /api/v1/member-medications/{id}/resume
POST /api/v1/member-medications/{id}/end
```

- [ ] **Step 5: Verify GREEN**

```bash
cd backend
uv run ruff check .
uv run pytest tests/test_reconciliation.py tests/test_medication_lifecycle.py -v
```

- [ ] **Step 6: Commit Task 3**

```bash
git add backend/app/doses/reconciliation.py backend/app/medications backend/app/schedules/service.py backend/tests/test_reconciliation.py backend/tests/test_medication_lifecycle.py
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
- Consumes: dose reconciliation from Task 3 and current membership ownership tables.
- Produces:
  - `DoseProjection` response schema.
  - taken/snooze/skip/correct endpoints.
  - notification preference GET/PATCH endpoints.

- [ ] **Step 1: Write RED dose-action tests**

Use payloads such as:

```python
payload = {
    "client_action_id": str(uuid4()),
    "occurred_at": "2026-09-23T12:00:00Z",
}
```

Assert Taken from upcoming/pending sets `taken`, clears snooze, records `taken_at`, and adds exactly one `marked_taken` log. Skip mirrors this. Snooze requires pending and returns pending with `snoozed_until`.

Test same payload twice: second request returns success and log count remains one. Test conflicting different final action returns `409 DOSE_ALREADY_FINALIZED`.

For Review Focus #1, send one action ID to dose A then reuse it for dose B and for a different action on dose A. Both must return:

```json
{"error":{"code":"IDEMPOTENCY_KEY_REUSED"}}
```

Test cross-family dose IDs return 404. Test `occurred_at` > server now + 5 minutes returns 422.

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

Assert prior `missed_at` and missed log remain, `taken_at` is set from `effective_at`, and a `corrected` log contains previous/new status.

Notification preference GET with no row returns logical defaults `enabled=false`, `default_snooze_minutes=15`; PATCH persists only `enabled` and snooze minutes and rejects escalation changes.

- [ ] **Step 3: Run tests and verify RED**

```bash
cd backend
uv run pytest tests/test_dose_actions.py tests/test_notification_preferences.py -v
```

- [ ] **Step 4: Implement ownership and idempotency repository helpers**

`require_accessible_dose()` joins `scheduled_doses → family_members → families → family_memberships` and returns 404 on no membership.

Before mutating, query `DoseLog.client_action_id`. If found, verify both `scheduled_dose_id` and `action` match the attempted operation. Otherwise raise:

```python
ApiError(409, "IDEMPOTENCY_KEY_REUSED", "This action identifier was already used for a different operation.")
```

- [ ] **Step 5: Implement action services and routers**

Each action accepts an injected/default server `now_utc`, calls reconciliation first, validates the timestamp, checks idempotency, applies the state transition, appends one log, commits, and returns `DoseProjection`.

Correction preserves previous timestamps/logs and changes only current projection plus the newly relevant timestamp.

Include `dose_router` and `notification_router` in `main.py`.

- [ ] **Step 6: Verify GREEN**

```bash
cd backend
uv run ruff check .
uv run pytest tests/test_dose_actions.py tests/test_notification_preferences.py -v
```

- [ ] **Step 7: Commit Task 4**

```bash
git add backend/app/doses backend/app/notifications backend/app/main.py backend/tests/test_dose_actions.py backend/tests/test_notification_preferences.py
git commit -m "feat: add idempotent dose actions"
```

---

### Task 5: Add Today and marked-history projections

**Files:**
- Create: `backend/app/doses/projections.py`
- Modify: `backend/app/doses/schemas.py`
- Modify: `backend/app/doses/router.py`
- Test: `backend/tests/test_today.py`
- Test: `backend/tests/test_history.py`

**Interfaces:**
- Consumes: reconciliation and dose action models from Tasks 3–4.
- Produces:
  - `build_today(session, user_id, now_utc) -> list[TodayMemberResponse]`
  - `build_member_history(session, user_id, member_id, from_date, to_date, now_utc) -> MemberHistoryResponse`
  - `GET /api/v1/today`
  - `GET /api/v1/family-members/{member_id}/history`.

- [ ] **Step 1: Write RED Today tests**

Seed Amma and another family member in distinct timezones/dates. Assert `/today` groups each member by that member's local current date, orders doses by effective reminder time, and returns:

```python
assert group["taken_count"] == 2
assert group["total_count"] == 3
assert group["doses"][2]["status"] == "pending"
```

Effective reminder time is `snoozed_until` when a pending dose has a snooze later than scheduled time; otherwise it is `scheduled_at`.

Members with zero doses still appear with counts zero.

- [ ] **Step 2: Write RED history/adherence tests**

Assert default range is most recent 30 member-local days and >90 day request returns 422. Pin:

```python
# statuses: taken, taken, skipped, missed, pending
assert history.marked_adherence_percentage == Decimal("50.00")
```

because denominator is the four final current statuses. With no final statuses assert `None`.

History includes dose event logs and correction metadata. Cross-family member ID returns 404.

- [ ] **Step 3: Run tests and verify RED**

```bash
cd backend
uv run pytest tests/test_today.py tests/test_history.py -v
```

- [ ] **Step 4: Implement projection queries**

Before returning Today/history, reconcile schedules accessible to the user. Query dose rows with medication/member display information and construct Pydantic responses rather than leaking ORM rows.

Calculate marked adherence with Decimal arithmetic:

```python
final_count = taken + skipped + missed
percentage = None if final_count == 0 else (Decimal(taken) * 100 / Decimal(final_count)).quantize(Decimal("0.01"))
```

- [ ] **Step 5: Wire routes and verify GREEN**

```bash
cd backend
uv run ruff check .
uv run pytest tests/test_today.py tests/test_history.py -v
uv run pytest -v
```

Expected: full backend suite passes.

- [ ] **Step 6: Commit Task 5**

```bash
git add backend/app/doses backend/tests/test_today.py backend/tests/test_history.py
git commit -m "feat: add today and marked history APIs"
```

---

### Task 6: Add Flutter schedule/Today domain contracts and Drift offline storage

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
- Test: `mobile/test/core/database/today_cache_test.dart`
- Test: `mobile/test/features/schedules/schedule_repository_test.dart`
- Test: `mobile/test/features/today/today_repository_test.dart`

**Interfaces:**
- Consumes: existing `ApiClient`, Riverpod provider pattern, Drift database.
- Produces: local cache tables, `ScheduleRepository`, `TodayRepository`, `DoseProjection`, `TodayMemberGroup` used by Tasks 7–10.

- [ ] **Step 1: Add RED Drift migration/cache tests**

Test a fresh schema version 2 database and migration from version 1:

```dart
expect(db.schemaVersion, 2);
await db.into(db.cachedTodayMembers).insert(...);
await db.into(db.cachedDoses).insert(...);
expect(await db.select(db.cachedDoses).get(), hasLength(1));
```

Use text for decimal quantity snapshots (`quantityText`) so SQLite does not introduce floating-point display drift.

- [ ] **Step 2: Run database test and verify RED**

```bash
cd mobile
flutter test test/core/database/today_cache_test.dart
```

Expected: tables/schema version do not exist.

- [ ] **Step 3: Add Drift tables and v1→v2 migration**

`CachedTodayMembers`: `memberId`, `name`, `relationship`, `localDate`, `timezone`, `updatedAt`.

`CachedDoses`: `doseId`, `memberId`, `medicationId`, `medicationName`, nullable `strength`, `quantityText`, `unit`, nullable `mealRelation`, `scheduledAt`, `scheduledLocalTime`, `status`, nullable `snoozedUntil`, `updatedAt`.

`SyncOperations`: `operationId` PK, `doseId`, `action`, `payloadJson`, `createdAt`, `attemptCount`, nullable `lastError`, `terminalFailure` boolean default false.

Set `schemaVersion => 2` and migration strategy:

```dart
onUpgrade: (m, from, to) async {
  if (from < 2) {
    await m.createTable(cachedTodayMembers);
    await m.createTable(cachedDoses);
    await m.createTable(syncOperations);
  }
}
```

- [ ] **Step 4: Add RED repository parsing/cache tests**

Mock `/today` and schedule endpoints. Assert API Today response is parsed, atomically replaces that day's cached member/dose projection, and network failure returns cached data with `isOffline=true` from repository result:

```dart
final result = await repository.loadToday();
expect(result.groups.single.name, 'Amma');
expect(result.isOffline, isTrue);
```

Schedule repository exposes:

```dart
Future<MedicationSchedule> createSchedule(String medicationId, ScheduleDraft draft);
Future<MedicationSchedule?> getCurrentSchedule(String medicationId);
Future<MedicationSchedule> updateSchedule(String scheduleId, ScheduleDraft draft);
```

- [ ] **Step 5: Implement domain/repository contracts**

Keep JSON parsing in domain factories and DB mapping inside `TodayRepository`. Do not put widget logic in repositories.

- [ ] **Step 6: Generate code and verify GREEN**

```bash
cd mobile
flutter pub get
flutter gen-l10n
dart run build_runner build --delete-conflicting-outputs
flutter analyze
flutter test test/core/database/today_cache_test.dart test/features/schedules/schedule_repository_test.dart test/features/today/today_repository_test.dart
```

- [ ] **Step 7: Commit Task 6**

```bash
git add mobile/lib/core/database mobile/lib/features/schedules mobile/lib/features/today mobile/test/core/database/today_cache_test.dart mobile/test/features/schedules/schedule_repository_test.dart mobile/test/features/today/today_repository_test.dart
git commit -m "feat: add mobile schedule and today data layer"
```

---

### Task 7: Build routine setup, reminder preference, and local notification abstraction

**Files:**
- Modify: `mobile/pubspec.yaml`
- Modify: `mobile/android/app/src/main/AndroidManifest.xml`
- Create: `mobile/lib/core/notifications/notification_scheduler.dart`
- Create: `mobile/lib/core/notifications/flutter_notification_scheduler.dart`
- Create: `mobile/lib/features/schedules/presentation/set_routine_screen.dart`
- Create: `mobile/lib/features/schedules/presentation/enable_reminders_screen.dart`
- Create: `mobile/lib/features/schedules/data/notification_preference_repository.dart`
- Modify: `mobile/lib/features/family/presentation/member_profile_screen.dart`
- Modify: `mobile/lib/app/router.dart`
- Modify: `mobile/lib/l10n/app_en.arb`
- Modify: `mobile/lib/l10n/app_bn.arb`
- Test: `mobile/test/features/schedules/set_routine_flow_test.dart`
- Test: `mobile/test/core/notifications/notification_scheduler_test.dart`

**Interfaces:**
- Consumes: `ScheduleRepository`, Today dose projection model.
- Produces: routine creation UI; `NotificationScheduler` interface used by Task 9 sync/action logic.

- [ ] **Step 1: Add notification dependencies**

Run:

```bash
cd mobile
flutter pub add flutter_local_notifications timezone
```

Commit the resulting compatible resolved versions in `pubspec.yaml`/`pubspec.lock`; do not hand-edit an unverified package version.

Add Android 13+ notification manifest permission:

```xml
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
```

Do not add `SCHEDULE_EXACT_ALARM` or `USE_EXACT_ALARM`.

- [ ] **Step 2: Write RED routine-flow tests**

Pin validation and copy:

```dart
expect(find.text('Reminder times are not part of the prescription.'), findsOneWidget);
```

Test required 1–8 rows, unique local times, positive quantity, retained values after API failure, successful create navigates to `/family/:memberId/medications/:medicationId/reminders`.

For Review Focus #5, fake the scheduler permission request as denied and separately fake `scheduleDose()` throwing a platform error. In both cases assert the schedule repository's successful routine remains active and the UI offers “Continue to Today” rather than deleting/pausing the routine.

- [ ] **Step 3: Define the notification abstraction and fake-friendly API**

```dart
abstract interface class NotificationScheduler {
  Future<bool> requestPermission();
  Future<void> reconcile(List<DoseProjection> doses);
  Future<void> scheduleDose(DoseProjection dose);
  Future<void> cancelDose(String doseId);
  Future<void> snoozeDose(DoseProjection dose);
}
```

Production scheduler derives a deterministic 31-bit Android notification ID from the UUID bytes/string hash and uses `AndroidScheduleMode.inexactAllowWhileIdle`. Initialize timezone data once and schedule using the dose timezone/scheduled instant. Tapping payload `dose:<uuid>` is routed to `/doses/<uuid>`.

- [ ] **Step 4: Implement routine and reminder screens**

Member medication cards gain **Set routine** for draft medications and **Edit routine** when current schedule exists. Routine submission is online-only.

Enable flow:

1. “Enable reminders” requests OS permission.
2. If granted, PATCH preference `enabled=true`, then reconcile cached dose notifications.
3. If denied or platform scheduling fails, keep the schedule active and show a non-destructive explanation.
4. “Not now” leaves preference disabled and routes to `/today`.

- [ ] **Step 5: Verify GREEN**

```bash
cd mobile
flutter gen-l10n
dart run build_runner build --delete-conflicting-outputs
flutter analyze
flutter test test/features/schedules/set_routine_flow_test.dart test/core/notifications/notification_scheduler_test.dart
```

- [ ] **Step 6: Commit Task 7**

```bash
git add mobile/pubspec.yaml mobile/pubspec.lock mobile/android/app/src/main/AndroidManifest.xml mobile/lib/core/notifications mobile/lib/features/schedules mobile/lib/features/family/presentation/member_profile_screen.dart mobile/lib/app/router.dart mobile/lib/l10n mobile/test/features/schedules/set_routine_flow_test.dart mobile/test/core/notifications/notification_scheduler_test.dart
git commit -m "feat: add routine setup and local reminders"
```

---

### Task 8: Make Today the authenticated home with cached/offline rendering

**Files:**
- Create: `mobile/lib/features/today/presentation/today_screen.dart`
- Create: `mobile/lib/features/today/presentation/dose_card.dart`
- Modify: `mobile/lib/app/router.dart`
- Modify: `mobile/lib/features/auth/presentation/login_screen.dart`
- Modify: `mobile/lib/core/auth/auth_controller.dart` only if route-target metadata is currently hard-coded there
- Modify: `mobile/lib/l10n/app_en.arb`
- Modify: `mobile/lib/l10n/app_bn.arb`
- Test: `mobile/test/features/today/today_screen_test.dart`
- Modify/Test: `mobile/test/features/auth/auth_flow_test.dart`

**Interfaces:**
- Consumes: `TodayRepository` from Task 6.
- Produces: `/today` protected route and Today UI; dose cards navigate to `/doses/:doseId` in Task 9.

- [ ] **Step 1: Write RED routing/Today tests**

Assert authenticated returning users and restored sessions route to `/today`; registration/login with zero family members still routes to `/care-for`.

Render a group:

```dart
expect(find.text('Amma'), findsOneWidget);
expect(find.text('2 / 3 marked taken'), findsOneWidget);
expect(find.text('Metformin 500 mg'), findsWidgets);
```

Assert status semantics include text/icon labels so tests can find “Taken”, “Pending”, “Skipped”, or “Missed” independent of color.

When repository returns cached data with `isOffline=true`, assert an offline indicator is visible and dose cards still render.

- [ ] **Step 2: Run tests and verify RED**

```bash
cd mobile
flutter test test/features/today/today_screen_test.dart test/features/auth/auth_flow_test.dart
```

- [ ] **Step 3: Implement Today screen and route**

Add protected `/today`. Router redirect becomes:

```dart
if (auth.status == AuthStatus.authenticated &&
    (path == '/welcome' || path == '/splash')) {
  return '/today';
}
```

Do not force `/today` when the explicit post-login family count is zero; preserve existing care-for decision in login/register flow.

Today screen uses `AsyncValue`, pull-to-refresh, member cards, ordered dose cards, and the offline banner. Summary copy is marked status, not clinical adherence.

- [ ] **Step 4: Verify GREEN**

```bash
cd mobile
flutter gen-l10n
flutter analyze
flutter test test/features/today/today_screen_test.dart test/features/auth/auth_flow_test.dart
```

- [ ] **Step 5: Commit Task 8**

```bash
git add mobile/lib/features/today mobile/lib/app/router.dart mobile/lib/features/auth mobile/lib/core/auth mobile/lib/l10n mobile/test/features/today/today_screen_test.dart mobile/test/features/auth/auth_flow_test.dart
git commit -m "feat: add today dashboard"
```

---

### Task 9: Add optimistic dose actions and durable offline sync queue

**Files:**
- Create: `mobile/lib/features/doses/data/dose_repository.dart`
- Create: `mobile/lib/features/doses/presentation/dose_action_screen.dart`
- Create: `mobile/lib/core/sync/sync_coordinator.dart`
- Create: `mobile/lib/core/sync/api_activity_events.dart`
- Modify: `mobile/lib/core/api/api_client.dart`
- Modify: `mobile/lib/app/app.dart`
- Modify: `mobile/lib/app/router.dart`
- Modify: `mobile/lib/features/today/data/today_repository.dart`
- Modify: `mobile/lib/core/notifications/notification_scheduler.dart`
- Modify: `mobile/lib/l10n/app_en.arb`
- Modify: `mobile/lib/l10n/app_bn.arb`
- Test: `mobile/test/core/sync/sync_coordinator_test.dart`
- Test: `mobile/test/features/doses/dose_action_screen_test.dart`

**Interfaces:**
- Consumes: Drift `sync_operations`, `cached_doses`, ApiClient refresh behavior, `NotificationScheduler`.
- Produces:
  - `DoseRepository.markTaken/snooze/skip/correct`
  - `SyncCoordinator.enqueueAndTry(...)`, `drain()`
  - `/doses/:doseId` screen.

- [ ] **Step 1: Write RED queue/action tests**

Test Taken offline:

```dart
await repository.markTaken(doseId, occurredAt: now);
final cached = await db.findDose(doseId);
expect(cached.status, 'taken');
expect(await db.pendingOperations(), hasLength(1));
```

Assert one UUID is generated when action is first created and the same `operationId/client_action_id` remains in serialized payload on every retry.

Test Snooze keeps cached status `pending`, changes `snoozedUntil`, and calls fake scheduler reschedule. Skip cancels notification.

- [ ] **Step 2: Pin conflict/permanent failure semantics**

For 409 final-state conflict, fake server response with current projection; drain must replace local dose, delete operation, and emit a non-destructive “record changed” sync event.

For Review Focus #4, fake `422 VALIDATION_ERROR`; after drain assert:

```dart
expect(op.terminalFailure, isTrue);
expect(op.attemptCount, 1);
await coordinator.drain();
expect((await db.operation(op.id)).attemptCount, 1); // no retry loop
```

For 404 remove stale operation/cache. For network/5xx retain operation and increment attempt count.

- [ ] **Step 3: Implement API activity event without a circular dependency**

Create:

```dart
class ApiActivityEvents {
  final _controller = StreamController<void>.broadcast();
  Stream<void> get successes => _controller.stream;
  void notifySuccess() => _controller.add(null);
  Future<void> dispose() => _controller.close();
}
```

Inject it into `ApiClient`. After each successful public `get/post/patch` wrapper returns, call `notifySuccess()`. Do not emit from the low-level retry callback itself.

`SyncCoordinator` subscribes to this stream and uses a single-flight `_drainFuture` guard so API calls made by queue draining cannot recursively start another drain.

- [ ] **Step 4: Implement optimistic queue transaction**

Within one Drift transaction:

1. save previous local projection in operation payload metadata;
2. apply optimistic cache state;
3. insert `SyncOperation` with UUID used as `client_action_id`.

Then call `drain()` immediately. Network errors leave the optimistic state plus operation.

`drain()` ignores rows with `terminalFailure=true`, posts the stored payload to the action-specific endpoint, replaces cache from server response on success, and deletes the operation.

- [ ] **Step 5: Trigger drain on required lifecycle points**

Convert `FamilyMedApp` to `ConsumerStatefulWidget` + `WidgetsBindingObserver`.

- when auth changes to authenticated: `ref.read(syncCoordinatorProvider).drain()`;
- on `AppLifecycleState.resumed`: drain;
- after queue insertion: drain;
- on `ApiActivityEvents.successes`: guarded drain.

- [ ] **Step 6: Implement dose action screen**

Show medication, quantity/unit, meal relation, scheduled time, confirmation disclaimer, Taken, Snooze 15 min, Skip. Disable duplicate taps while local transaction is in progress; network replay may continue asynchronously afterward.

Route `/doses/:doseId` reads cached dose first and refreshes Today after successful server sync.

- [ ] **Step 7: Verify GREEN**

```bash
cd mobile
flutter gen-l10n
dart run build_runner build --delete-conflicting-outputs
flutter analyze
flutter test test/core/sync/sync_coordinator_test.dart test/features/doses/dose_action_screen_test.dart test/features/today/today_screen_test.dart
```

- [ ] **Step 8: Commit Task 9**

```bash
git add mobile/lib/core/api mobile/lib/core/sync mobile/lib/core/notifications mobile/lib/app mobile/lib/features/doses mobile/lib/features/today mobile/lib/l10n mobile/test/core/sync/sync_coordinator_test.dart mobile/test/features/doses/dose_action_screen_test.dart mobile/test/features/today/today_screen_test.dart
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
- Consumes: backend history endpoint and Task 9 `DoseRepository.correct` queue path.
- Produces: member History access and correction flow.

- [ ] **Step 1: Write RED history/correction tests**

Mock history containing a missed event followed by correction to taken. Assert both are represented and summary says “Marked adherence”.

Open a final dose and correct to taken with effective time. Assert correction calls the same offline-capable queue machinery with action `correct` and leaves prior event display intact.

- [ ] **Step 2: Run tests and verify RED**

```bash
cd mobile
flutter test test/features/history/history_flow_test.dart
```

- [ ] **Step 3: Implement repository and screens**

`HistoryRepository.load(memberId, from, to)` calls the API online; temporary API failure may show an error because the spec only requires Today cache, not full offline history browsing.

Member profile adds **History**. History groups by local date, displays current status and event timeline, and shows **Correct record** only for final statuses.

Correction form requires target final status, effective time, and optional reason; it generates one stable client action through `DoseRepository.correct`.

- [ ] **Step 4: Verify GREEN**

```bash
cd mobile
flutter gen-l10n
flutter analyze
flutter test test/features/history/history_flow_test.dart
```

- [ ] **Step 5: Commit Task 10**

```bash
git add mobile/lib/features/history mobile/lib/features/family/presentation/member_profile_screen.dart mobile/lib/app/router.dart mobile/lib/l10n mobile/test/features/history/history_flow_test.dart
git commit -m "feat: add marked medication history"
```

---

### Task 11: Add full vertical-slice acceptance coverage and final verification

**Files:**
- Create: `backend/tests/test_schedules_today_vertical_slice.py`
- Create: `mobile/test/features/schedules_today_acceptance_test.dart`
- Modify: `README.md` for local reminder/offline behavior only if commands or developer setup changed.

**Interfaces:**
- Consumes: all prior tasks.
- Produces: executable acceptance proof and final branch verification evidence.

- [ ] **Step 1: Write backend acceptance test through HTTP**

Exercise a single real PostgreSQL test flow:

```text
register
→ add Amma
→ add Metformin
→ create 08:00 + 20:00 Asia/Dhaka schedule
→ assert medication active
→ reconcile at controlled now
→ GET /today
→ Taken with client_action_id
→ Snooze pending dose
→ Skip another eligible dose
→ GET history
→ Correct one final dose
→ edit schedule
→ verify old event-bearing dose IDs/logs remain
→ second account receives 404 for dose
```

The test must assert exact log counts after duplicate retries.

- [ ] **Step 2: Write Flutter acceptance test**

Use fake repositories/scheduler plus in-memory Drift to drive widgets through:

```text
member profile
→ Set routine
→ Enable reminders or Not now
→ Today
→ dose screen
→ Taken
→ offline Snooze queued
→ reconnect/drain
→ History
→ Correct record
```

Assert the routine disclaimer and family-confirmation disclaimer appear in the appropriate screens.

- [ ] **Step 3: Run focused acceptance tests**

```bash
cd backend
uv run pytest tests/test_schedules_today_vertical_slice.py -v
cd ../mobile
flutter test test/features/schedules_today_acceptance_test.dart
```

Expected: both pass.

- [ ] **Step 4: Run the entire backend gate**

```bash
cd backend
uv sync --all-groups
uv run ruff check .
uv run alembic upgrade head
uv run pytest -v
```

Expected: all steps pass on PostgreSQL 17.

- [ ] **Step 5: Run the entire mobile gate**

```bash
cd mobile
flutter pub get
flutter gen-l10n
dart run build_runner build --delete-conflicting-outputs
flutter analyze
flutter test
flutter build apk --debug
```

Expected: analyzer clean, all tests pass, debug APK builds.

- [ ] **Step 6: Check scope and repository state**

```bash
git status --short
git diff --check main...HEAD
git log --oneline --decorate main..HEAD
```

Expected: no unintended generated/untracked files; no whitespace errors; commits correspond to Tasks 1–11.

- [ ] **Step 7: Commit acceptance/docs if changed**

```bash
git add backend/tests/test_schedules_today_vertical_slice.py mobile/test/features/schedules_today_acceptance_test.dart README.md
git commit -m "test: verify schedules today dose flow"
```

If `README.md` did not require a change, omit it from `git add` rather than creating documentation churn.
