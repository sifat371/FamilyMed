from datetime import UTC, datetime
from uuid import UUID
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.common.errors import ApiError
from app.doses.models import DoseLog, ScheduledDose
from app.medications.models import MemberMedication
from app.schedules.generation import generate_schedule_window
from app.schedules.models import MedicationSchedule, ScheduleTime
from app.schedules.repository import (
    get_current_schedule,
    list_schedule_times,
    require_accessible_schedule,
    require_current_schedule,
)
from app.schedules.schemas import (
    ScheduleCreate,
    ScheduleResponse,
    ScheduleTimeResponse,
    ScheduleUpdate,
)


def _utc_now() -> datetime:
    return datetime.now(UTC)


def _minute_floor(value: datetime) -> datetime:
    return value.astimezone(UTC).replace(second=0, microsecond=0)


def _validate_timezone(timezone_name: str) -> None:
    try:
        ZoneInfo(timezone_name)
    except ZoneInfoNotFoundError as exc:
        raise ApiError(
            422,
            "INVALID_TIMEZONE",
            "Timezone identifier is invalid.",
        ) from exc


async def schedule_response(
    session: AsyncSession,
    schedule: MedicationSchedule,
) -> ScheduleResponse:
    times = await list_schedule_times(session, schedule.id)
    return ScheduleResponse(
        id=schedule.id,
        member_medication_id=schedule.member_medication_id,
        raw_instruction=schedule.raw_instruction,
        meal_relation=schedule.meal_relation,
        timezone=schedule.timezone,
        start_date=schedule.start_date,
        end_date=schedule.end_date,
        status=schedule.status,
        times=[
            ScheduleTimeResponse(
                id=item.id,
                period=item.period,
                local_time=item.local_time,
                quantity=item.quantity,
                unit=item.unit,
                sort_order=item.sort_order,
            )
            for item in times
        ],
    )


async def create_schedule(
    session: AsyncSession,
    user_id: UUID,
    medication_id: UUID,
    payload: ScheduleCreate,
    *,
    now_utc: datetime | None = None,
) -> ScheduleResponse:
    medication, existing = await get_current_schedule(
        session,
        user_id,
        medication_id,
        for_write=True,
    )
    if existing is not None:
        raise ApiError(
            409,
            "ACTIVE_SCHEDULE_EXISTS",
            "This medication already has a current schedule.",
        )
    if medication.status in {"ended", "completed"}:
        raise ApiError(
            409,
            "MEDICATION_NOT_ACTIVE",
            "An ended or completed medication cannot receive a new schedule.",
        )
    _validate_timezone(payload.timezone)

    now = now_utc or _utc_now()
    schedule = MedicationSchedule(
        member_medication_id=medication.id,
        raw_instruction=payload.raw_instruction,
        meal_relation=payload.meal_relation,
        timezone=payload.timezone,
        start_date=payload.start_date,
        end_date=payload.end_date,
        generation_not_before_at=_minute_floor(now),
        status="active",
        created_by_user_id=user_id,
    )
    session.add(schedule)
    await session.flush()
    for index, item in enumerate(payload.times):
        session.add(
            ScheduleTime(
                schedule_id=schedule.id,
                period=item.period,
                local_time=item.local_time,
                quantity=item.quantity,
                unit=item.unit,
                sort_order=index,
            )
        )
    if medication.status == "draft":
        medication.status = "active"
    await session.flush()
    await generate_schedule_window(session, schedule.id, now)
    await session.commit()
    return await schedule_response(session, schedule)


async def read_current_schedule(
    session: AsyncSession,
    user_id: UUID,
    medication_id: UUID,
) -> ScheduleResponse:
    _, schedule = await require_current_schedule(
        session,
        user_id,
        medication_id,
    )
    return await schedule_response(session, schedule)


async def update_schedule(
    session: AsyncSession,
    user_id: UUID,
    schedule_id: UUID,
    payload: ScheduleUpdate,
    *,
    now_utc: datetime | None = None,
) -> ScheduleResponse:
    medication, schedule = await require_accessible_schedule(
        session,
        user_id,
        schedule_id,
        for_write=True,
    )
    _validate_timezone(payload.timezone)
    now = now_utc or _utc_now()

    event_exists = (
        select(DoseLog.id)
        .where(DoseLog.scheduled_dose_id == ScheduledDose.id)
        .exists()
    )
    await session.execute(
        delete(ScheduledDose).where(
            ScheduledDose.schedule_id == schedule.id,
            ScheduledDose.status == "upcoming",
            ScheduledDose.scheduled_at > now,
            ~event_exists,
        )
    )
    await session.execute(
        delete(ScheduleTime).where(ScheduleTime.schedule_id == schedule.id)
    )
    await session.flush()

    schedule.raw_instruction = payload.raw_instruction
    schedule.meal_relation = payload.meal_relation
    schedule.timezone = payload.timezone
    schedule.start_date = payload.start_date
    schedule.end_date = payload.end_date
    for index, item in enumerate(payload.times):
        session.add(
            ScheduleTime(
                schedule_id=schedule.id,
                period=item.period,
                local_time=item.local_time,
                quantity=item.quantity,
                unit=item.unit,
                sort_order=index,
            )
        )
    await session.flush()
    if schedule.status == "active":
        await generate_schedule_window(session, schedule.id, now)
    await session.commit()
    return await schedule_response(session, schedule)
