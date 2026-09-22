from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.common.errors import ApiError
from app.doses.models import DoseLog, ScheduledDose
from app.families.models import FamilyMember, FamilyMembership


async def require_accessible_dose(
    session: AsyncSession,
    user_id: UUID,
    dose_id: UUID,
    *,
    for_write: bool = False,
) -> ScheduledDose:
    conditions = [
        ScheduledDose.id == dose_id,
        FamilyMembership.user_id == user_id,
        FamilyMembership.status == "active",
        FamilyMember.archived_at.is_(None),
    ]
    if for_write:
        conditions.append(FamilyMembership.role.in_(["owner", "caregiver"]))

    dose = await session.scalar(
        select(ScheduledDose)
        .join(FamilyMember, FamilyMember.id == ScheduledDose.family_member_id)
        .join(FamilyMembership, FamilyMembership.family_id == FamilyMember.family_id)
        .where(*conditions)
    )
    if dose is None:
        raise ApiError(404, "DOSE_NOT_FOUND", "Dose was not found.")
    return dose


async def get_log_by_client_action_id(
    session: AsyncSession,
    client_action_id: UUID,
) -> DoseLog | None:
    return await session.scalar(
        select(DoseLog).where(DoseLog.client_action_id == client_action_id)
    )
