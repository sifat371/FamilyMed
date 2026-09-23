from datetime import UTC, date, datetime
from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, Query
from sqlalchemy.ext.asyncio import AsyncSession

from app.common.auth import get_current_user
from app.db import get_db_session
from app.doses.projections import build_member_history, build_reminder_feed, build_today
from app.doses.schemas import (
    CorrectionRequest,
    DoseActionRequest,
    DoseProjection,
    MemberHistoryResponse,
    SnoozeRequest,
    TodayDoseResponse,
    TodayMemberResponse,
)
from app.doses.service import correct_dose, mark_taken, skip_dose, snooze_dose
from app.users.models import User

router = APIRouter(tags=["doses"])
DbSession = Annotated[AsyncSession, Depends(get_db_session)]
CurrentUser = Annotated[User, Depends(get_current_user)]


@router.get("/today", response_model=list[TodayMemberResponse])
async def today(session: DbSession, current_user: CurrentUser) -> list[TodayMemberResponse]:
    return await build_today(session, current_user.id, datetime.now(UTC))


@router.get("/reminder-doses", response_model=list[TodayDoseResponse])
async def reminder_doses(
    session: DbSession,
    current_user: CurrentUser,
    days: Annotated[int, Query(ge=1, le=30)] = 30,
) -> list[TodayDoseResponse]:
    return await build_reminder_feed(
        session,
        current_user.id,
        datetime.now(UTC),
        days=days,
    )


@router.get(
    "/family-members/{member_id}/history",
    response_model=MemberHistoryResponse,
)
async def member_history(
    member_id: UUID,
    session: DbSession,
    current_user: CurrentUser,
    from_date: Annotated[date | None, Query(alias="from")] = None,
    to_date: Annotated[date | None, Query(alias="to")] = None,
) -> MemberHistoryResponse:
    return await build_member_history(
        session,
        current_user.id,
        member_id,
        from_date,
        to_date,
        datetime.now(UTC),
    )


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
