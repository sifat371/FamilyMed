from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.common.auth import get_current_user
from app.db import get_db_session
from app.schedules.schemas import ScheduleCreate, ScheduleResponse, ScheduleUpdate
from app.schedules.service import create_schedule, read_current_schedule, update_schedule
from app.users.models import User

router = APIRouter(tags=["schedules"])
DbSession = Annotated[AsyncSession, Depends(get_db_session)]
CurrentUser = Annotated[User, Depends(get_current_user)]


@router.post(
    "/member-medications/{medication_id}/schedules",
    response_model=ScheduleResponse,
    status_code=status.HTTP_201_CREATED,
)
async def post_schedule(
    medication_id: UUID,
    payload: ScheduleCreate,
    session: DbSession,
    current_user: CurrentUser,
) -> ScheduleResponse:
    return await create_schedule(
        session,
        current_user.id,
        medication_id,
        payload,
    )


@router.get(
    "/member-medications/{medication_id}/schedule",
    response_model=ScheduleResponse,
)
async def get_schedule(
    medication_id: UUID,
    session: DbSession,
    current_user: CurrentUser,
) -> ScheduleResponse:
    return await read_current_schedule(session, current_user.id, medication_id)


@router.patch(
    "/schedules/{schedule_id}",
    response_model=ScheduleResponse,
)
async def patch_schedule(
    schedule_id: UUID,
    payload: ScheduleUpdate,
    session: DbSession,
    current_user: CurrentUser,
) -> ScheduleResponse:
    return await update_schedule(
        session,
        current_user.id,
        schedule_id,
        payload,
    )
