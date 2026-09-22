from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.common.errors import ApiError
from app.families.models import FamilyMember, FamilyMembership

FAMILY_MEMBER_NOT_FOUND = (
    404,
    "FAMILY_MEMBER_NOT_FOUND",
    "Family member was not found.",
)


async def list_accessible_members(session: AsyncSession, user_id: UUID) -> list[FamilyMember]:
    result = await session.scalars(
        select(FamilyMember)
        .join(FamilyMembership, FamilyMembership.family_id == FamilyMember.family_id)
        .where(
            FamilyMembership.user_id == user_id,
            FamilyMembership.status == "active",
            FamilyMember.archived_at.is_(None),
        )
        .order_by(FamilyMember.created_at, FamilyMember.id)
    )
    return list(result.all())


async def require_accessible_member(
    session: AsyncSession,
    user_id: UUID,
    member_id: UUID,
    *,
    for_write: bool = False,
) -> FamilyMember:
    conditions = [
        FamilyMember.id == member_id,
        FamilyMembership.user_id == user_id,
        FamilyMembership.status == "active",
        FamilyMember.archived_at.is_(None),
    ]
    if for_write:
        conditions.append(FamilyMembership.role.in_(["owner", "caregiver"]))

    member = await session.scalar(
        select(FamilyMember)
        .join(FamilyMembership, FamilyMembership.family_id == FamilyMember.family_id)
        .where(*conditions)
    )
    if member is None:
        raise ApiError(*FAMILY_MEMBER_NOT_FOUND)
    return member


async def require_writable_family_id(session: AsyncSession, user_id: UUID) -> UUID:
    family_id = await session.scalar(
        select(FamilyMembership.family_id)
        .where(
            FamilyMembership.user_id == user_id,
            FamilyMembership.status == "active",
            FamilyMembership.role.in_(["owner", "caregiver"]),
        )
        .order_by(FamilyMembership.created_at, FamilyMembership.id)
        .limit(1)
    )
    if family_id is None:
        raise ApiError(
            409,
            "FAMILY_CONTEXT_MISSING",
            "No writable family context is available.",
        )
    return family_id
