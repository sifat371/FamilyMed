from datetime import UTC, date, datetime, time, timedelta
from uuid import UUID
from zoneinfo import ZoneInfo

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.doses.models import ScheduledDose
from app.medications.models import MemberMedication
from app.schedules.models import MedicationSchedule, ScheduleTime


def local_occurrence_to_utc(
    local_date: date,
    local_time: time,
    timezone_name: str,
) -> datetime:
    local_value = datetime.combine(
        local_date,
        local_time,
        tzinfo=ZoneInfo(timezone_name),
    )
    return local_value.astimezone(UTC)


async def generate_schedule_window(
    session: AsyncSession,
    schedule_id: UUID,
    now_utc: datetime,
) -> list[ScheduledDose]:
    schedule = await session.get(MedicationSchedule, schedule_id)
    if schedule is None or schedule.status != "active":
        return []

    medication = await session.get(MemberMedication, schedule.member_medication_id)
    if medication is None:
        return []

    times = list(
        (
            await session.scalars(
                select(ScheduleTime)
                .where(ScheduleTime.schedule_id == schedule.id)
                .order_by(ScheduleTime.sort_order, ScheduleTime.local_time)
            )
        ).all()
    )
    if not times:
        return []

    zone = ZoneInfo(schedule.timezone)
    now_floor = now_utc.astimezone(UTC).replace(second=0, microsecond=0)
    local_today = now_utc.astimezone(zone).date()
    window_end = local_today + timedelta(days=29)

    start_date = max(local_today, schedule.start_date, medication.start_date)
    end_candidates = [window_end]
    if schedule.end_date is not None:
        end_candidates.append(schedule.end_date)
    if medication.end_date is not None:
        end_candidates.append(medication.end_date)
    end_date = min(end_candidates)
    if end_date < start_date:
        return []

    lower_bound = max(schedule.generation_not_before_at, now_floor)
    existing = set(
        (
            await session.execute(
                select(
                    ScheduledDose.scheduled_local_date,
                    ScheduledDose.scheduled_local_time,
                ).where(
                    ScheduledDose.schedule_id == schedule.id,
                    ScheduledDose.scheduled_local_date >= start_date,
                    ScheduledDose.scheduled_local_date <= end_date,
                )
            )
        ).all()
    )

    created: list[ScheduledDose] = []
    current_date = start_date
    while current_date <= end_date:
        for schedule_time in times:
            occurrence_key = (current_date, schedule_time.local_time)
            if occurrence_key in existing:
                continue
            scheduled_at = local_occurrence_to_utc(
                current_date,
                schedule_time.local_time,
                schedule.timezone,
            )
            if scheduled_at < lower_bound:
                continue
            dose = ScheduledDose(
                schedule_id=schedule.id,
                schedule_time_id=schedule_time.id,
                family_member_id=medication.family_member_id,
                member_medication_id=medication.id,
                scheduled_at=scheduled_at,
                scheduled_local_date=current_date,
                scheduled_local_time=schedule_time.local_time,
                timezone=schedule.timezone,
                quantity=schedule_time.quantity,
                unit=schedule_time.unit,
                meal_relation=schedule.meal_relation,
                status="upcoming",
            )
            session.add(dose)
            created.append(dose)
            existing.add(occurrence_key)
        current_date += timedelta(days=1)

    if created:
        await session.flush()
    return created
