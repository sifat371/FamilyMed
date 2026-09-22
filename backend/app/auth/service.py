from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.schemas import AuthResponse, LoginRequest, RefreshResponse, RegisterRequest
from app.auth.security import (
    create_access_token,
    create_refresh_token,
    decode_token,
    hash_password,
    verify_password,
)
from app.common.errors import ApiError
from app.families.models import Family, FamilyMembership
from app.users.models import User


async def register_user(session: AsyncSession, payload: RegisterRequest) -> AuthResponse:
    email = str(payload.email)
    try:
        async with session.begin():
            existing = await session.scalar(select(User).where(User.email == email))
            if existing is not None:
                raise ApiError(
                    409,
                    "EMAIL_ALREADY_REGISTERED",
                    "An account with this email already exists.",
                )

            user = User(
                name=payload.name,
                email=email,
                password_hash=hash_password(payload.password),
            )
            session.add(user)
            await session.flush()

            family = Family(
                name=f"{payload.name}'s family",
                created_by_user_id=user.id,
            )
            session.add(family)
            await session.flush()

            session.add(
                FamilyMembership(
                    family_id=family.id,
                    user_id=user.id,
                    role="owner",
                    status="active",
                )
            )
    except IntegrityError as exc:
        raise ApiError(
            409,
            "EMAIL_ALREADY_REGISTERED",
            "An account with this email already exists.",
        ) from exc

    return AuthResponse(
        user=user,
        access_token=create_access_token(user.id),
        refresh_token=create_refresh_token(user.id),
    )


async def login_user(session: AsyncSession, payload: LoginRequest) -> AuthResponse:
    user = await session.scalar(select(User).where(User.email == str(payload.email)))
    if user is None or not verify_password(payload.password, user.password_hash):
        raise ApiError(
            401,
            "INVALID_CREDENTIALS",
            "Email or password is incorrect.",
        )

    return AuthResponse(
        user=user,
        access_token=create_access_token(user.id),
        refresh_token=create_refresh_token(user.id),
    )


def refresh_access_token(refresh_token: str) -> RefreshResponse:
    user_id = decode_token(refresh_token, "refresh")
    return RefreshResponse(access_token=create_access_token(user_id))
