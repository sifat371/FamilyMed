from uuid import UUID

from sqlalchemy.ext.asyncio import AsyncSession

from app.families.models import FamilyMember
from app.families.repository import (
    list_accessible_members,
    require_accessible_member,
    require_writable_family_id,
)
from app.families.schemas import FamilyMemberCreate, FamilyMemberUpdate


async def list_members(session: AsyncSession, user_id: UUID) -> list[FamilyMember]:
    return await list_accessible_members(session, user_id)


async def create_member(
    session: AsyncSession,
    user_id: UUID,
    payload: FamilyMemberCreate,
) -> FamilyMember:
    family_id = await require_writable_family_id(session, user_id)
    member = FamilyMember(
        family_id=family_id,
        name=payload.name,
        relationship=payload.relationship,
        date_of_birth=payload.date_of_birth,
        preferred_language=payload.preferred_language,
        timezone=payload.timezone,
    )
    session.add(member)
    await session.commit()
    await session.refresh(member)
    return member


async def get_member(session: AsyncSession, user_id: UUID, member_id: UUID) -> FamilyMember:
    return await require_accessible_member(session, user_id, member_id)


async def update_member(
    session: AsyncSession,
    user_id: UUID,
    member_id: UUID,
    payload: FamilyMemberUpdate,
) -> FamilyMember:
    member = await require_accessible_member(
        session,
        user_id,
        member_id,
        for_write=True,
    )
    for field_name, value in payload.model_dump(exclude_unset=True).items():
        setattr(member, field_name, value)
    await session.commit()
    await session.refresh(member)
    return member
