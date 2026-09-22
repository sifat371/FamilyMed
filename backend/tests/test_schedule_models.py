from datetime import date, datetime, time, timezone
from decimal import Decimal
from uuid import uuid4

import pytest
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.doses.models import DoseLog, ScheduledDose
from app.families.models import Family, FamilyMember, FamilyMembership
from app.medications.models import MemberMedication
from app.notifications.models import NotificationPreference
from app.schedules.models import MedicationSchedule, ScheduleTime
from app.users.models import User


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
    session.add(
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
    session.add(member)
    await session.flush()

    medication = MemberMedication(
        family_member_id=member.id,
        medicine_master_id=None,
        prescription_id=None,
        extraction_id=None,
        display_name="Metformin",
        strength="500 mg",
        dosage_form="tablet",
        status="draft",
        start_date=date(2026, 9, 23),
        end_date=None,
        created_by_user_id=user.id,
    )
    session.add(medication)
    await session.flush()
    return medication


async def _seed_schedule(
    session: AsyncSession,
    *,
    status: str = "active",
    quantity: Decimal = Decimal("1"),
    unit: str = "tablet",
) -> tuple[MemberMedication, MedicationSchedule, ScheduleTime]:
    medication = await _seed_medication(session)
    schedule = MedicationSchedule(
        member_medication_id=medication.id,
        raw_instruction="1+0+1 PC",
        meal_relation="after_food",
        timezone="Asia/Dhaka",
        start_date=date(2026, 9, 23),
        end_date=None,
        generation_not_before_at=datetime(2026, 9, 23, 3, 0, tzinfo=timezone.utc),
        status=status,
        created_by_user_id=medication.created_by_user_id,
    )
    session.add(schedule)
    await session.flush()
    schedule_time = ScheduleTime(
        schedule_id=schedule.id,
        period="morning",
        local_time=time(8, 0),
        quantity=quantity,
        unit=unit,
        sort_order=0,
    )
    session.add(schedule_time)
    await session.flush()
    return medication, schedule, schedule_time


@pytest.mark.asyncio
async def test_schedule_dose_log_and_notification_preference_persist(db_session):
    medication, schedule, schedule_time = await _seed_schedule(db_session)

    dose = ScheduledDose(
        schedule_id=schedule.id,
        schedule_time_id=schedule_time.id,
        family_member_id=medication.family_member_id,
        member_medication_id=medication.id,
        scheduled_at=datetime(2026, 9, 24, 2, 0, tzinfo=timezone.utc),
        scheduled_local_date=date(2026, 9, 24),
        scheduled_local_time=time(8, 0),
        timezone="Asia/Dhaka",
        quantity=Decimal("1"),
        unit="tablet",
        meal_relation="after_food",
        status="upcoming",
    )
    db_session.add(dose)
    await db_session.flush()

    log = DoseLog(
        scheduled_dose_id=dose.id,
        action="became_pending",
        performed_by_user_id=None,
        client_action_id=None,
        occurred_at=dose.scheduled_at,
        recorded_at=dose.scheduled_at,
        metadata={},
    )
    preference = NotificationPreference(
        family_member_id=medication.family_member_id,
        user_id=medication.created_by_user_id,
        enabled=False,
        default_snooze_minutes=15,
        caregiver_escalation_enabled=False,
    )
    db_session.add_all([log, preference])
    await db_session.commit()

    assert schedule.id is not None
    assert schedule_time.id is not None
    assert dose.id is not None
    assert log.id is not None
    assert preference.id is not None


@pytest.mark.asyncio
@pytest.mark.parametrize("bad_status", ["invalid", "done"])
async def test_schedule_status_constraint_rejects_invalid_values(db_session, bad_status):
    medication = await _seed_medication(db_session)
    db_session.add(
        MedicationSchedule(
            member_medication_id=medication.id,
            raw_instruction=None,
            meal_relation=None,
            timezone="Asia/Dhaka",
            start_date=date(2026, 9, 23),
            end_date=None,
            generation_not_before_at=datetime(2026, 9, 23, 3, 0, tzinfo=timezone.utc),
            status=bad_status,
            created_by_user_id=medication.created_by_user_id,
        )
    )
    with pytest.raises(IntegrityError):
        await db_session.flush()


@pytest.mark.asyncio
async def test_schedule_time_constraints_reject_invalid_quantity_and_blank_unit(db_session):
    medication = await _seed_medication(db_session)
    schedule = MedicationSchedule(
        member_medication_id=medication.id,
        raw_instruction=None,
        meal_relation=None,
        timezone="Asia/Dhaka",
        start_date=date(2026, 9, 23),
        end_date=None,
        generation_not_before_at=datetime(2026, 9, 23, 3, 0, tzinfo=timezone.utc),
        status="active",
        created_by_user_id=medication.created_by_user_id,
    )
    db_session.add(schedule)
    await db_session.flush()

    db_session.add(
        ScheduleTime(
            schedule_id=schedule.id,
            period="morning",
            local_time=time(8, 0),
            quantity=Decimal("0"),
            unit="tablet",
            sort_order=0,
        )
    )
    with pytest.raises(IntegrityError):
        await db_session.flush()
    await db_session.rollback()


@pytest.mark.asyncio
async def test_duplicate_schedule_clock_is_rejected(db_session):
    _, schedule, _ = await _seed_schedule(db_session)
    db_session.add(
        ScheduleTime(
            schedule_id=schedule.id,
            period="custom",
            local_time=time(8, 0),
            quantity=Decimal("1"),
            unit="tablet",
            sort_order=1,
        )
    )
    with pytest.raises(IntegrityError):
        await db_session.flush()


@pytest.mark.asyncio
async def test_duplicate_dose_occurrence_and_invalid_status_are_rejected(db_session):
    medication, schedule, schedule_time = await _seed_schedule(db_session)
    first = ScheduledDose(
        schedule_id=schedule.id,
        schedule_time_id=schedule_time.id,
        family_member_id=medication.family_member_id,
        member_medication_id=medication.id,
        scheduled_at=datetime(2026, 9, 24, 2, 0, tzinfo=timezone.utc),
        scheduled_local_date=date(2026, 9, 24),
        scheduled_local_time=time(8, 0),
        timezone="Asia/Dhaka",
        quantity=Decimal("1"),
        unit="tablet",
        meal_relation=None,
        status="upcoming",
    )
    db_session.add(first)
    await db_session.flush()

    duplicate = ScheduledDose(
        schedule_id=schedule.id,
        schedule_time_id=schedule_time.id,
        family_member_id=medication.family_member_id,
        member_medication_id=medication.id,
        scheduled_at=datetime(2026, 9, 24, 2, 5, tzinfo=timezone.utc),
        scheduled_local_date=date(2026, 9, 24),
        scheduled_local_time=time(8, 0),
        timezone="Asia/Dhaka",
        quantity=Decimal("1"),
        unit="tablet",
        meal_relation=None,
        status="upcoming",
    )
    db_session.add(duplicate)
    with pytest.raises(IntegrityError):
        await db_session.flush()
