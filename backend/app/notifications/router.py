from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.common.auth import get_current_user
from app.db import get_db_session
from app.notifications.schemas import (
    NotificationPreferenceResponse,
    NotificationPreferenceUpdate,
)
from app.notifications.service import (
    get_notification_preference,
    update_notification_preference,
)
from app.users.models import User

router = APIRouter(tags=["notifications"])
DbSession = Annotated[AsyncSession, Depends(get_db_session)]
CurrentUser = Annotated[User, Depends(get_current_user)]


@router.get(
    "/family-members/{member_id}/notification-preference",
    response_model=NotificationPreferenceResponse,
)
async def get_preference(
    member_id: UUID,
    session: DbSession,
    current_user: CurrentUser,
) -> NotificationPreferenceResponse:
    return await get_notification_preference(session, current_user.id, member_id)


@router.patch(
    "/family-members/{member_id}/notification-preference",
    response_model=NotificationPreferenceResponse,
)
async def patch_preference(
    member_id: UUID,
    payload: NotificationPreferenceUpdate,
    session: DbSession,
    current_user: CurrentUser,
) -> NotificationPreferenceResponse:
    return await update_notification_preference(
        session,
        current_user.id,
        member_id,
        payload,
    )
