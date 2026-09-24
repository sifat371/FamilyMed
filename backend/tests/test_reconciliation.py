from datetime import UTC, date, datetime, time
from decimal import Decimal
from uuid import uuid4

from sqlalchemy import func, select

from app.doses.models import DoseLog, ScheduledDose
from app.doses.projections import build_today
from app.doses.reconciliation import reconcile_schedule
from app.families.models import Family, FamilyMember, FamilyMembership
from app.medications.models import MemberMedication
from app.schedules.models import MedicationSchedule, ScheduleTime
from app.users.models import User


async def _seed_dose(db_session, *, snoozed_until=None, end_date=None):
    user = User(
        name="Caregiver",
        email=f"reconcile-{uuid4()}@example.com",
        password_hash="test-hash",
        preferred_language="en",
        timezone="Asia/Dhaka",
    )
    db_session.add(user)
    await db_session.flush()
    family = Family(name="Family", created_by_user_id=user.id)
    db_session.add(family)
    await db_session.flush()
    db_session.add(
        FamilyMembership(
            family_id=family.id,
            user_id=user.id,
            role="owner",
            status="active",
        )
    )
    member = FamilyMember(
        family_id=family.id,
        name="Amma",
        relationship="mother",
        preferred_language="bn",
        timezone="Asia/Dhaka",
    )
    db_session.add(member)
    await db_session.flush()
    medication = MemberMedication(
        family_member_id=member.id,
        display_name="Metformin",
        strength="500 mg",
        dosage_form="tablet",
        status="active",
        start_date=date(2026, 9, 23),
        end_date=end_date,
        created_by_user_id=user.id,
    )
    db_session.add(medication)
    await db_session.flush()
    schedule = MedicationSchedule(
        member_medication_id=medication.id,
        raw_instruction=None,
        meal_relation="after_food",
        timezone="Asia/Dhaka",
        start_date=date(2026, 9, 23),
        end_date=end_date,
        generation_not_before_at=datetime(2026, 9, 23, 0, 0, tzinfo=UTC),
        status="active",
        created_by_user_id=user.id,
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
        family_member_id=member.id,
        member_medication_id=medication.id,
        scheduled_at=datetime(2026, 9, 23, 2, 0, tzinfo=UTC),
        scheduled_local_date=date(2026, 9, 23),
        scheduled_local_time=time(8, 0),
        timezone="Asia/Dhaka",
        quantity=Decimal("1"),
        unit="tablet",
        meal_relation="after_food",
        status="pending" if snoozed_until is not None else "upcoming",
        snoozed_until=snoozed_until,
    )
    db_session.add(dose)
    await db_session.flush()
    return medication, schedule, dose


async def _actions(db_session, dose_id):
    result = await db_session.scalars(
        select(DoseLog.action)
        .where(DoseLog.scheduled_dose_id == dose_id)
        .order_by(DoseLog.recorded_at, DoseLog.id)
    )
    return list(result.all())


async def test_upcoming_becomes_pending_once_and_missed_at_dhaka_day_end(db_session):
    _, schedule, dose = await _seed_dose(db_session)

    await reconcile_schedule(
        db_session,
        schedule.id,
        datetime(2026, 9, 23, 2, 0, tzinfo=UTC),
    )
    await db_session.refresh(dose)
    assert dose.status == "pending"
    assert await _actions(db_session, dose.id) == ["became_pending"]

    await reconcile_schedule(
        db_session,
        schedule.id,
        datetime(2026, 9, 23, 2, 5, tzinfo=UTC),
    )
    assert await _actions(db_session, dose.id) == ["became_pending"]

    await reconcile_schedule(
        db_session,
        schedule.id,
        datetime(2026, 9, 23, 17, 59, tzinfo=UTC),
    )
    await db_session.refresh(dose)
    assert dose.status == "pending"

    await reconcile_schedule(
        db_session,
        schedule.id,
        datetime(2026, 9, 23, 18, 0, tzinfo=UTC),
    )
    await db_session.refresh(dose)
    assert dose.status == "missed"
    assert dose.missed_at == datetime(2026, 9, 23, 18, 0, tzinfo=UTC)
    assert await _actions(db_session, dose.id) == ["became_pending", "missed"]


async def test_snooze_past_midnight_delays_missed_transition(db_session):
    snoozed_until = datetime(2026, 9, 23, 18, 30, tzinfo=UTC)
    _, schedule, dose = await _seed_dose(
        db_session,
        snoozed_until=snoozed_until,
    )

    await reconcile_schedule(
        db_session,
        schedule.id,
        datetime(2026, 9, 23, 18, 10, tzinfo=UTC),
    )
    await db_session.refresh(dose)
    assert dose.status == "pending"

    await reconcile_schedule(
        db_session,
        schedule.id,
        datetime(2026, 9, 23, 18, 30, tzinfo=UTC),
    )
    await db_session.refresh(dose)
    assert dose.status == "missed"
    assert dose.missed_at == snoozed_until
    assert await _actions(db_session, dose.id) == ["missed"]


async def test_natural_completion_waits_for_final_end_date_dose(db_session):
    medication, schedule, dose = await _seed_dose(
        db_session,
        end_date=date(2026, 9, 23),
    )
    dose.status = "pending"
    await db_session.flush()

    await reconcile_schedule(
        db_session,
        schedule.id,
        datetime(2026, 9, 23, 17, 59, tzinfo=UTC),
    )
    await db_session.refresh(medication)
    await db_session.refresh(schedule)
    assert medication.status == "active"
    assert schedule.status == "active"

    await reconcile_schedule(
        db_session,
        schedule.id,
        datetime(2026, 9, 23, 18, 0, tzinfo=UTC),
    )
    await db_session.refresh(medication)
    await db_session.refresh(schedule)
    assert medication.status == "completed"
    assert schedule.status == "ended"
    missed_count = await db_session.scalar(
        select(func.count())
        .select_from(DoseLog)
        .where(DoseLog.scheduled_dose_id == dose.id, DoseLog.action == "missed")
    )
    assert missed_count == 1


async def test_local_day_rollover_shows_new_occurrence_without_resetting_prior_final(
    db_session,
):
    medication, schedule, prior = await _seed_dose(db_session)
    prior.scheduled_at = datetime(2026, 9, 24, 2, 0, tzinfo=UTC)
    prior.scheduled_local_date = date(2026, 9, 24)
    prior.scheduled_local_time = time(8, 0)
    prior.status = "taken"
    prior.taken_at = datetime(2026, 9, 24, 2, 5, tzinfo=UTC)
    await db_session.flush()

    before_midnight = await build_today(
        db_session,
        medication.created_by_user_id,
        datetime(2026, 9, 24, 17, 59, tzinfo=UTC),
    )
    assert before_midnight[0].local_date == date(2026, 9, 24)
    assert any(
        item.id == prior.id and item.status == "taken"
        for item in before_midnight[0].doses
    )

    after_midnight = await build_today(
        db_session,
        medication.created_by_user_id,
        datetime(2026, 9, 24, 18, 1, tzinfo=UTC),
    )
    assert after_midnight[0].local_date == date(2026, 9, 25)
    assert any(
        item.scheduled_local_date == date(2026, 9, 25)
        for item in after_midnight[0].doses
    )

    await db_session.refresh(prior)
    assert prior.status == "taken"
    assert prior.taken_at == datetime(2026, 9, 24, 2, 5, tzinfo=UTC)
