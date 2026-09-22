from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.common.auth import get_current_user
from app.db import get_db_session
from app.doses.schemas import CorrectionRequest, DoseActionRequest, DoseProjection, SnoozeRequest
from app.doses.service import correct_dose, mark_taken, skip_dose, snooze_dose
from app.users.models import User

router = APIRouter(tags=["doses"])
DbSession = Annotated[AsyncSession, Depends(get_db_session)]
CurrentUser = Annotated[User, Depends(get_current_user)]


@router.post("/doses/{dose_id}/taken", response_model=DoseProjection)
async def taken(
    dose_id: UUID,
    payload: DoseActionRequest,
    session: DbSession,
    current_user: CurrentUser,
) -> DoseProjection:
    dose = await mark_taken(session, current_user.id, dose_id, payload)
    return DoseProjection.model_validate(dose)


@router.post("/doses/{dose_id}/snooze", response_model=DoseProjection)
async def snooze(
    dose_id: UUID,
    payload: SnoozeRequest,
    session: DbSession,
    current_user: CurrentUser,
) -> DoseProjection:
    dose = await snooze_dose(session, current_user.id, dose_id, payload)
    return DoseProjection.model_validate(dose)


@router.post("/doses/{dose_id}/skip", response_model=DoseProjection)
async def skip(
    dose_id: UUID,
    payload: DoseActionRequest,
    session: DbSession,
    current_user: CurrentUser,
) -> DoseProjection:
    dose = await skip_dose(session, current_user.id, dose_id, payload)
    return DoseProjection.model_validate(dose)


@router.post("/doses/{dose_id}/correct", response_model=DoseProjection)
async def correct(
    dose_id: UUID,
    payload: CorrectionRequest,
    session: DbSession,
    current_user: CurrentUser,
) -> DoseProjection:
    dose = await correct_dose(session, current_user.id, dose_id, payload)
    return DoseProjection.model_validate(dose)
