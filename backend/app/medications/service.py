from datetime import UTC, datetime
from uuid import UUID

from sqlalchemy import delete, exists, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.common.errors import ApiError
from app.doses.models import DoseLog, ScheduledDose
from app.medications.models import MemberMedication
from app.medications.repository import (
    list_member_medications,
    require_accessible_medication,
    require_writable_member,
)
from app.medications.schemas import ManualMedicationCreate, ManualMedicationUpdate
from app.schedules.generation import generate_schedule_window
from app.schedules.repository import get_current_schedule


async def list_for_member(
    session: AsyncSession,
    user_id: UUID,
    member_id: UUID,
) -> list[MemberMedication]:
    return await list_member_medications(session, user_id, member_id)


async def create_manual_medication(
    session: AsyncSession,
    user_id: UUID,
    member_id: UUID,
    payload: ManualMedicationCreate,
) -> MemberMedication:
    await require_writable_member(session, user_id, member_id)
    medication = MemberMedication(
        family_member_id=member_id,
        medicine_master_id=None,
        prescription_id=None,
        extraction_id=None,
        display_name=payload.display_name,
        strength=payload.strength,
        dosage_form=payload.dosage_form,
        status="draft",
        start_date=payload.start_date,
        end_date=payload.end_date,
        created_by_user_id=user_id,
    )
    session.add(medication)
    await session.commit()
    await session.refresh(medication)
    return medication


async def get_medication(
    session: AsyncSession,
    user_id: UUID,
    medication_id: UUID,
) -> MemberMedication:
    return await require_accessible_medication(session, user_id, medication_id)


async def update_medication(
    session: AsyncSession,
    user_id: UUID,
    medication_id: UUID,
    payload: ManualMedicationUpdate,
) -> MemberMedication:
    medication = await require_accessible_medication(
        session,
        user_id,
        medication_id,
        for_write=True,
    )
    changes = payload.model_dump(exclude_unset=True)
    next_start = changes.get("start_date", medication.start_date)
    next_end = changes.get("end_date", medication.end_date)
    if next_end is not None and next_end < next_start:
        raise ApiError(
            422,
            "VALIDATION_ERROR",
            "Request validation failed.",
            {"fields": [{"msg": "end date cannot be before start date"}]},
        )
    for field_name, value in changes.items():
        setattr(medication, field_name, value)
    await session.commit()
    await session.refresh(medication)
    return medication


async def pause_medication(
    session: AsyncSession,
    user_id: UUID,
    medication_id: UUID,
    *,
    now_utc: datetime | None = None,
) -> MemberMedication:
    now_utc = (now_utc or datetime.now(UTC)).astimezone(UTC)
    medication, schedule = await get_current_schedule(
        session,
        user_id,
        medication_id,
        for_write=True,
    )
    if schedule is None:
        raise ApiError(404, "SCHEDULE_NOT_FOUND", "Medication schedule was not found.")
    medication.status = "paused"
    schedule.status = "paused"
    await _remove_future_untouched_doses(session, schedule.id, now_utc)
    await session.commit()
    await session.refresh(medication)
    return medication


async def resume_medication(
    session: AsyncSession,
    user_id: UUID,
    medication_id: UUID,
    *,
    now_utc: datetime | None = None,
) -> MemberMedication:
    now_utc = (now_utc or datetime.now(UTC)).astimezone(UTC)
    medication, schedule = await get_current_schedule(
        session,
        user_id,
        medication_id,
        for_write=True,
    )
    if schedule is None:
        raise ApiError(404, "SCHEDULE_NOT_FOUND", "Medication schedule was not found.")
    if medication.status != "paused" or schedule.status != "paused":
        raise ApiError(409, "MEDICATION_NOT_PAUSED", "Medication is not paused.")
    medication.status = "active"
    schedule.status = "active"
    schedule.generation_not_before_at = now_utc.replace(second=0, microsecond=0)
    await generate_schedule_window(session, schedule.id, now_utc)
    await session.commit()
    await session.refresh(medication)
    return medication


async def end_medication(
    session: AsyncSession,
    user_id: UUID,
    medication_id: UUID,
    *,
    now_utc: datetime | None = None,
) -> MemberMedication:
    now_utc = (now_utc or datetime.now(UTC)).astimezone(UTC)
    medication, schedule = await get_current_schedule(
        session,
        user_id,
        medication_id,
        for_write=True,
    )
    if schedule is None:
        raise ApiError(404, "SCHEDULE_NOT_FOUND", "Medication schedule was not found.")
    medication.status = "ended"
    schedule.status = "ended"
    await _remove_future_untouched_doses(session, schedule.id, now_utc)
    await session.commit()
    await session.refresh(medication)
    return medication


async def _remove_future_untouched_doses(
    session: AsyncSession,
    schedule_id: UUID,
    now_utc: datetime,
) -> None:
    has_event = exists(
        select(DoseLog.id).where(DoseLog.scheduled_dose_id == ScheduledDose.id)
    )
    await session.execute(
        delete(ScheduledDose).where(
            ScheduledDose.schedule_id == schedule_id,
            ScheduledDose.status == "upcoming",
            ScheduledDose.scheduled_at > now_utc,
            ~has_event,
        )
    )
