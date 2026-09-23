from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.common.auth import get_current_user
from app.db import get_db_session
from app.medications.schemas import (
    ManualMedicationCreate,
    ManualMedicationUpdate,
    MemberMedicationResponse,
)
from app.medications.service import (
    create_manual_medication,
    end_medication,
    get_medication,
    list_for_member,
    pause_medication,
    resume_medication,
    update_medication,
)
from app.users.models import User

router = APIRouter(tags=["medications"])
DbSession = Annotated[AsyncSession, Depends(get_db_session)]
CurrentUser = Annotated[User, Depends(get_current_user)]


@router.get(
    "/family-members/{member_id}/medications",
    response_model=list[MemberMedicationResponse],
)
async def list_medications(
    member_id: UUID,
    session: DbSession,
    current_user: CurrentUser,
) -> list[MemberMedicationResponse]:
    medications = await list_for_member(session, current_user.id, member_id)
    return [MemberMedicationResponse.model_validate(item) for item in medications]


@router.post(
    "/family-members/{member_id}/medications",
    response_model=MemberMedicationResponse,
    status_code=status.HTTP_201_CREATED,
)
async def create_medication(
    member_id: UUID,
    payload: ManualMedicationCreate,
    session: DbSession,
    current_user: CurrentUser,
) -> MemberMedicationResponse:
    medication = await create_manual_medication(
        session,
        current_user.id,
        member_id,
        payload,
    )
    return MemberMedicationResponse.model_validate(medication)


@router.get(
    "/member-medications/{medication_id}",
    response_model=MemberMedicationResponse,
)
async def get_member_medication(
    medication_id: UUID,
    session: DbSession,
    current_user: CurrentUser,
) -> MemberMedicationResponse:
    medication = await get_medication(session, current_user.id, medication_id)
    return MemberMedicationResponse.model_validate(medication)


@router.patch(
    "/member-medications/{medication_id}",
    response_model=MemberMedicationResponse,
)
async def patch_member_medication(
    medication_id: UUID,
    payload: ManualMedicationUpdate,
    session: DbSession,
    current_user: CurrentUser,
) -> MemberMedicationResponse:
    medication = await update_medication(
        session,
        current_user.id,
        medication_id,
        payload,
    )
    return MemberMedicationResponse.model_validate(medication)


@router.post(
    "/member-medications/{medication_id}/pause",
    response_model=MemberMedicationResponse,
)
async def pause_member_medication(
    medication_id: UUID,
    session: DbSession,
    current_user: CurrentUser,
) -> MemberMedicationResponse:
    medication = await pause_medication(session, current_user.id, medication_id)
    return MemberMedicationResponse.model_validate(medication)


@router.post(
    "/member-medications/{medication_id}/resume",
    response_model=MemberMedicationResponse,
)
async def resume_member_medication(
    medication_id: UUID,
    session: DbSession,
    current_user: CurrentUser,
) -> MemberMedicationResponse:
    medication = await resume_medication(session, current_user.id, medication_id)
    return MemberMedicationResponse.model_validate(medication)


@router.post(
    "/member-medications/{medication_id}/end",
    response_model=MemberMedicationResponse,
)
async def end_member_medication(
    medication_id: UUID,
    session: DbSession,
    current_user: CurrentUser,
) -> MemberMedicationResponse:
    medication = await end_medication(session, current_user.id, medication_id)
    return MemberMedicationResponse.model_validate(medication)
