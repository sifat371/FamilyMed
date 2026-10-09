from typing import Annotated

from fastapi import APIRouter, Depends, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.account_deletion import delete_account
from app.auth.schemas import (
    AuthResponse,
    DeleteAccountRequest,
    LoginRequest,
    RefreshRequest,
    RefreshResponse,
    RegisterRequest,
    UpdateAccountRequest,
    UserResponse,
)
from app.auth.service import login_user, refresh_access_token, register_user
from app.common.auth import get_current_user
from app.db import get_db_session
from app.users.models import User

router = APIRouter(prefix="/auth", tags=["auth"])
DbSession = Annotated[AsyncSession, Depends(get_db_session)]
CurrentUser = Annotated[User, Depends(get_current_user)]


@router.post("/register", response_model=AuthResponse, status_code=status.HTTP_201_CREATED)
async def register(payload: RegisterRequest, session: DbSession) -> AuthResponse:
    return await register_user(session, payload)


@router.post("/login", response_model=AuthResponse)
async def login(payload: LoginRequest, session: DbSession) -> AuthResponse:
    return await login_user(session, payload)


@router.post("/refresh", response_model=RefreshResponse)
async def refresh(payload: RefreshRequest) -> RefreshResponse:
    return refresh_access_token(payload.refresh_token)


@router.get("/me", response_model=UserResponse)
async def me(current_user: CurrentUser) -> UserResponse:
    return UserResponse.model_validate(current_user)


@router.patch("/me", response_model=UserResponse)
async def update_me(
    payload: UpdateAccountRequest, current_user: CurrentUser, session: DbSession
) -> UserResponse:
    """Persist preferences only for the authenticated account."""
    current_user.name = payload.name
    current_user.preferred_language = payload.preferred_language
    await session.commit()
    await session.refresh(current_user)
    return UserResponse.model_validate(current_user)


@router.post("/me/delete", status_code=status.HTTP_204_NO_CONTENT)
async def delete_my_account(
    payload: DeleteAccountRequest, session: DbSession, current_user: CurrentUser
) -> None:
    await delete_account(session, current_user, payload.password)
