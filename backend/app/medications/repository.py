from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.common.errors import ApiError
from app.families.models import FamilyMember, FamilyMembership
from app.families.repository import require_accessible_member
from app.medications.models import MemberMedication


async def list_member_medications(
    session: AsyncSession,
    user_id: UUID,
    member_id: UUID,
) -> list[MemberMedication]:
    await require_accessible_member(session, user_id, member_id)
    result = await session.scalars(
        select(MemberMedication)
        .where(MemberMedication.family_member_id == member_id)
        .order_by(MemberMedication.created_at, MemberMedication.id)
    )
    return list(result.all())


async def require_writable_member(
    session: AsyncSession,
    user_id: UUID,
    member_id: UUID,
) -> FamilyMember:
    return await require_accessible_member(
        session,
        user_id,
        member_id,
        for_write=True,
    )


async def require_accessible_medication(
    session: AsyncSession,
    user_id: UUID,
    medication_id: UUID,
    *,
    for_write: bool = False,
) -> MemberMedication:
    conditions = [
        MemberMedication.id == medication_id,
        FamilyMembership.user_id == user_id,
        FamilyMembership.status == "active",
        FamilyMember.archived_at.is_(None),
    ]
    if for_write:
        conditions.append(FamilyMembership.role.in_(["owner", "caregiver"]))

    medication = await session.scalar(
        select(MemberMedication)
        .join(FamilyMember, FamilyMember.id == MemberMedication.family_member_id)
        .join(FamilyMembership, FamilyMembership.family_id == FamilyMember.family_id)
        .where(*conditions)
    )
    if medication is None:
        raise ApiError(
            404,
            "MEDICATION_NOT_FOUND",
            "Medication was not found.",
        )
    return medication
