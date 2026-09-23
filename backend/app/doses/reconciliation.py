from datetime import UTC, datetime, time, timedelta
from uuid import UUID
from zoneinfo import ZoneInfo

from sqlalchemy import exists, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.doses.models import DoseLog, ScheduledDose
from app.medications.models import MemberMedication
from app.schedules.models import MedicationSchedule


async def reconcile_schedule(
    session: AsyncSession,
    schedule_id: UUID,
    now_utc: datetime,
) -> None:
    schedule = await session.get(MedicationSchedule, schedule_id)
    if schedule is None:
        return

    now_utc = now_utc.astimezone(UTC)
    doses = list(
        (
            await session.scalars(
                select(ScheduledDose)
                .where(ScheduledDose.schedule_id == schedule.id)
                .order_by(ScheduledDose.scheduled_at, ScheduledDose.id)
            )
        ).all()
    )

    for dose in doses:
        if dose.status == "upcoming" and dose.scheduled_at <= now_utc:
            dose.status = "pending"
            has_pending_log = await session.scalar(
                select(
                    exists().where(
                        DoseLog.scheduled_dose_id == dose.id,
                        DoseLog.action == "became_pending",
                    )
                )
            )
            if not has_pending_log:
                session.add(
                    DoseLog(
                        scheduled_dose_id=dose.id,
                        action="became_pending",
                        performed_by_user_id=None,
                        client_action_id=None,
                        occurred_at=dose.scheduled_at,
                        recorded_at=now_utc,
                        event_metadata={},
                    )
                )

        if dose.status != "pending":
            continue

        zone = ZoneInfo(dose.timezone)
        next_local_midnight = datetime.combine(
            dose.scheduled_local_date + timedelta(days=1),
            time.min,
            tzinfo=zone,
        )
        local_day_end_utc = next_local_midnight.astimezone(UTC)
        miss_threshold = local_day_end_utc
        if dose.snoozed_until is not None:
            snoozed_until = dose.snoozed_until.astimezone(UTC)
            if snoozed_until > miss_threshold:
                miss_threshold = snoozed_until

        if now_utc >= miss_threshold:
            dose.status = "missed"
            dose.missed_at = miss_threshold
            has_missed_log = await session.scalar(
                select(
                    exists().where(
                        DoseLog.scheduled_dose_id == dose.id,
                        DoseLog.action == "missed",
                    )
                )
            )
            if not has_missed_log:
                session.add(
                    DoseLog(
                        scheduled_dose_id=dose.id,
                        action="missed",
                        performed_by_user_id=None,
                        client_action_id=None,
                        occurred_at=miss_threshold,
                        recorded_at=now_utc,
                        event_metadata={},
                    )
                )

    await session.flush()
    await _complete_schedule_if_finished(session, schedule, now_utc)
    await session.flush()


async def _complete_schedule_if_finished(
    session: AsyncSession,
    schedule: MedicationSchedule,
    now_utc: datetime,
) -> None:
    if schedule.status != "active" or schedule.end_date is None:
        return

    zone = ZoneInfo(schedule.timezone)
    completion_boundary = datetime.combine(
        schedule.end_date + timedelta(days=1),
        time.min,
        tzinfo=zone,
    ).astimezone(UTC)
    if now_utc < completion_boundary:
        return

    non_final = await session.scalar(
        select(
            exists().where(
                ScheduledDose.schedule_id == schedule.id,
                ScheduledDose.scheduled_local_date <= schedule.end_date,
                ScheduledDose.status.in_(["upcoming", "pending"]),
            )
        )
    )
    if non_final:
        return

    medication = await session.get(MemberMedication, schedule.member_medication_id)
    if medication is None:
        return
    schedule.status = "ended"
    medication.status = "completed"
