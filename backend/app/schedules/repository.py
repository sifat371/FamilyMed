from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.common.errors import ApiError
from app.medications.models import MemberMedication
from app.medications.repository import require_accessible_medication
from app.schedules.models import MedicationSchedule, ScheduleTime


async def get_current_schedule(
    session: AsyncSession,
    user_id: UUID,
    medication_id: UUID,
    *,
    for_write: bool = False,
) -> tuple[MemberMedication, MedicationSchedule | None]:
    medication = await require_accessible_medication(
        session,
        user_id,
        medication_id,
        for_write=for_write,
    )
    schedule = await session.scalar(
        select(MedicationSchedule).where(
            MedicationSchedule.member_medication_id == medication.id,
            MedicationSchedule.status.in_(["active", "paused"]),
        )
    )
    return medication, schedule


async def require_current_schedule(
    session: AsyncSession,
    user_id: UUID,
    medication_id: UUID,
    *,
    for_write: bool = False,
) -> tuple[MemberMedication, MedicationSchedule]:
    medication, schedule = await get_current_schedule(
        session,
        user_id,
        medication_id,
        for_write=for_write,
    )
    if schedule is None:
        raise ApiError(404, "SCHEDULE_NOT_FOUND", "Medication schedule was not found.")
    return medication, schedule


async def require_accessible_schedule(
    session: AsyncSession,
    user_id: UUID,
    schedule_id: UUID,
    *,
    for_write: bool = False,
) -> tuple[MemberMedication, MedicationSchedule]:
    schedule = await session.get(MedicationSchedule, schedule_id)
    if schedule is None:
        raise ApiError(404, "SCHEDULE_NOT_FOUND", "Medication schedule was not found.")
    medication = await require_accessible_medication(
        session,
        user_id,
        schedule.member_medication_id,
        for_write=for_write,
    )
    return medication, schedule


async def list_schedule_times(
    session: AsyncSession,
    schedule_id: UUID,
) -> list[ScheduleTime]:
    result = await session.scalars(
        select(ScheduleTime)
        .where(ScheduleTime.schedule_id == schedule_id)
        .order_by(ScheduleTime.sort_order, ScheduleTime.local_time, ScheduleTime.id)
    )
    return list(result.all())
