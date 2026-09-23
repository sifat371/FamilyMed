from collections import defaultdict
from datetime import UTC, date, datetime, timedelta
from decimal import Decimal
from uuid import UUID
from zoneinfo import ZoneInfo

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.common.errors import ApiError
from app.doses.models import DoseLog, ScheduledDose
from app.doses.reconciliation import reconcile_schedule
from app.doses.schemas import (
    DoseEventResponse,
    HistoryDayResponse,
    HistoryDoseResponse,
    MemberHistoryResponse,
    TodayDoseResponse,
    TodayMemberResponse,
)
from app.families.models import FamilyMember, FamilyMembership
from app.families.repository import list_accessible_members, require_accessible_member
from app.medications.models import MemberMedication
from app.notifications.models import NotificationPreference
from app.schedules.generation import generate_schedule_window
from app.schedules.models import MedicationSchedule


async def build_today(
    session: AsyncSession,
    user_id: UUID,
    now_utc: datetime,
) -> list[TodayMemberResponse]:
    now_utc = now_utc.astimezone(UTC)
    await _refresh_accessible_schedules(session, user_id, now_utc)
    members = await list_accessible_members(session, user_id)
    groups: list[TodayMemberResponse] = []
    for member in members:
        local_date = now_utc.astimezone(ZoneInfo(member.timezone)).date()
        rows = list(
            (
                await session.execute(
                    select(ScheduledDose, MemberMedication)
                    .join(
                        MemberMedication,
                        MemberMedication.id == ScheduledDose.member_medication_id,
                    )
                    .where(
                        ScheduledDose.family_member_id == member.id,
                        ScheduledDose.scheduled_local_date == local_date,
                    )
                )
            ).all()
        )
        doses = [_today_dose(dose, medication) for dose, medication in rows]
        doses.sort(key=lambda item: (item.effective_reminder_at, item.id))
        groups.append(
            TodayMemberResponse(
                member_id=member.id,
                member_name=member.name,
                relationship=member.relationship,
                local_date=local_date,
                timezone=member.timezone,
                taken_count=sum(item.status == "taken" for item in doses),
                total_count=len(doses),
                doses=doses,
            )
        )
    return groups


async def build_reminder_feed(
    session: AsyncSession,
    user_id: UUID,
    now_utc: datetime,
    *,
    days: int = 30,
) -> list[TodayDoseResponse]:
    if days < 1 or days > 30:
        raise ApiError(422, "VALIDATION_ERROR", "days must be between 1 and 30.")
    now_utc = now_utc.astimezone(UTC)
    await _refresh_accessible_schedules(session, user_id, now_utc)
    member_ids = [member.id for member in await list_accessible_members(session, user_id)]
    if not member_ids:
        return []
    window_end = now_utc + timedelta(days=days)
    rows = list(
        (
            await session.execute(
                select(ScheduledDose, MemberMedication)
                .join(
                    MemberMedication,
                    MemberMedication.id == ScheduledDose.member_medication_id,
                )
                .join(
                    NotificationPreference,
                    NotificationPreference.family_member_id
                    == ScheduledDose.family_member_id,
                )
                .where(
                    ScheduledDose.family_member_id.in_(member_ids),
                    NotificationPreference.user_id == user_id,
                    NotificationPreference.enabled.is_(True),
                    ScheduledDose.status.in_(["upcoming", "pending"]),
                    ScheduledDose.scheduled_at < window_end,
                )
            )
        ).all()
    )
    result = [_today_dose(dose, medication) for dose, medication in rows]
    result.sort(key=lambda item: (item.effective_reminder_at, item.id))
    return result


async def build_member_history(
    session: AsyncSession,
    user_id: UUID,
    member_id: UUID,
    from_date: date | None,
    to_date: date | None,
    now_utc: datetime,
) -> MemberHistoryResponse:
    now_utc = now_utc.astimezone(UTC)
    member = await require_accessible_member(session, user_id, member_id)
    local_today = now_utc.astimezone(ZoneInfo(member.timezone)).date()
    resolved_to = to_date or local_today
    resolved_from = from_date or (resolved_to - timedelta(days=29))
    if resolved_from > resolved_to or (resolved_to - resolved_from).days > 89:
        raise ApiError(
            422,
            "VALIDATION_ERROR",
            "History range must be between 1 and 90 days.",
        )

    await _refresh_accessible_schedules(session, user_id, now_utc)
    rows = list(
        (
            await session.execute(
                select(ScheduledDose, MemberMedication)
                .join(
                    MemberMedication,
                    MemberMedication.id == ScheduledDose.member_medication_id,
                )
                .where(
                    ScheduledDose.family_member_id == member.id,
                    ScheduledDose.scheduled_local_date >= resolved_from,
                    ScheduledDose.scheduled_local_date <= resolved_to,
                )
                .order_by(
                    ScheduledDose.scheduled_local_date.desc(),
                    ScheduledDose.scheduled_at,
                )
            )
        ).all()
    )

    by_day: dict[date, list[HistoryDoseResponse]] = defaultdict(list)
    taken = skipped = missed = 0
    for dose, medication in rows:
        if dose.status == "taken":
            taken += 1
        elif dose.status == "skipped":
            skipped += 1
        elif dose.status == "missed":
            missed += 1
        logs = list(
            (
                await session.scalars(
                    select(DoseLog)
                    .where(DoseLog.scheduled_dose_id == dose.id)
                    .order_by(DoseLog.recorded_at, DoseLog.id)
                )
            ).all()
        )
        base = _today_dose(dose, medication)
        by_day[dose.scheduled_local_date].append(
            HistoryDoseResponse(
                **base.model_dump(),
                events=[
                    DoseEventResponse(
                        action=log.action,
                        occurred_at=log.occurred_at,
                        recorded_at=log.recorded_at,
                        metadata=log.event_metadata,
                    )
                    for log in logs
                ],
            )
        )

    denominator = taken + skipped + missed
    percentage = None
    if denominator:
        percentage = (Decimal(taken) * 100 / Decimal(denominator)).quantize(
            Decimal("0.01")
        )
    days = [
        HistoryDayResponse(local_date=day, doses=by_day[day])
        for day in sorted(by_day, reverse=True)
    ]
    return MemberHistoryResponse(
        member_id=member.id,
        member_name=member.name,
        timezone=member.timezone,
        from_date=resolved_from,
        to_date=resolved_to,
        marked_adherence_percentage=percentage,
        days=days,
    )


async def _refresh_accessible_schedules(
    session: AsyncSession,
    user_id: UUID,
    now_utc: datetime,
) -> None:
    schedule_ids = list(
        (
            await session.scalars(
                select(MedicationSchedule.id)
                .join(
                    MemberMedication,
                    MemberMedication.id == MedicationSchedule.member_medication_id,
                )
                .join(
                    FamilyMember,
                    FamilyMember.id == MemberMedication.family_member_id,
                )
                .join(
                    FamilyMembership,
                    FamilyMembership.family_id == FamilyMember.family_id,
                )
                .where(
                    FamilyMembership.user_id == user_id,
                    FamilyMembership.status == "active",
                    FamilyMember.archived_at.is_(None),
                    MedicationSchedule.status.in_(["active", "paused"]),
                )
                .distinct()
            )
        ).all()
    )
    for schedule_id in schedule_ids:
        await generate_schedule_window(session, schedule_id, now_utc)
        await reconcile_schedule(session, schedule_id, now_utc)
    if schedule_ids:
        await session.commit()


def _today_dose(
    dose: ScheduledDose,
    medication: MemberMedication,
) -> TodayDoseResponse:
    effective = dose.scheduled_at
    if (
        dose.status == "pending"
        and dose.snoozed_until is not None
        and dose.snoozed_until > effective
    ):
        effective = dose.snoozed_until
    return TodayDoseResponse(
        id=dose.id,
        schedule_id=dose.schedule_id,
        family_member_id=dose.family_member_id,
        member_medication_id=dose.member_medication_id,
        medication_name=medication.display_name,
        strength=medication.strength,
        scheduled_at=dose.scheduled_at,
        scheduled_local_date=dose.scheduled_local_date,
        scheduled_local_time=dose.scheduled_local_time,
        timezone=dose.timezone,
        quantity=dose.quantity,
        unit=dose.unit,
        meal_relation=dose.meal_relation,
        status=dose.status,
        snoozed_until=dose.snoozed_until,
        taken_at=dose.taken_at,
        skipped_at=dose.skipped_at,
        missed_at=dose.missed_at,
        effective_reminder_at=effective,
    )
