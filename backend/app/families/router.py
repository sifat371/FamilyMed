from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.common.auth import get_current_user
from app.db import get_db_session
from app.families.schemas import (
    FamilyMemberCreate,
    FamilyMemberResponse,
    FamilyMemberUpdate,
)
from app.families.service import create_member, get_member, list_members, update_member
from app.users.models import User

router = APIRouter(prefix="/family-members", tags=["family"])
DbSession = Annotated[AsyncSession, Depends(get_db_session)]
CurrentUser = Annotated[User, Depends(get_current_user)]


@router.get("", response_model=list[FamilyMemberResponse])
async def list_family_members(
    session: DbSession,
    current_user: CurrentUser,
) -> list[FamilyMemberResponse]:
    members = await list_members(session, current_user.id)
    return [FamilyMemberResponse.model_validate(item) for item in members]


@router.post("", response_model=FamilyMemberResponse, status_code=status.HTTP_201_CREATED)
async def create_family_member(
    payload: FamilyMemberCreate,
    session: DbSession,
    current_user: CurrentUser,
) -> FamilyMemberResponse:
    member = await create_member(session, current_user.id, payload)
    return FamilyMemberResponse.model_validate(member)


@router.get("/{member_id}", response_model=FamilyMemberResponse)
async def get_family_member(
    member_id: UUID,
    session: DbSession,
    current_user: CurrentUser,
) -> FamilyMemberResponse:
    member = await get_member(session, current_user.id, member_id)
    return FamilyMemberResponse.model_validate(member)


@router.patch("/{member_id}", response_model=FamilyMemberResponse)
async def patch_family_member(
    member_id: UUID,
    payload: FamilyMemberUpdate,
    session: DbSession,
    current_user: CurrentUser,
) -> FamilyMemberResponse:
    member = await update_member(session, current_user.id, member_id, payload)
    return FamilyMemberResponse.model_validate(member)
