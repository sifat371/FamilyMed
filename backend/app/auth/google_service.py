"""Google account sessions and opt-in linking; never auto-merge accounts by email."""

from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.google_identity import verify_google_identity
from app.auth.schemas import AuthResponse
from app.auth.security import create_access_token, create_refresh_token
from app.common.errors import ApiError
from app.families.models import Family, FamilyMembership
from app.users.models import User


async def google_sign_in(session: AsyncSession, token: str) -> AuthResponse:
    identity = await verify_google_identity(token)
    try:
        async with session.begin():
            user = await session.scalar(select(User).where(User.google_subject == identity.subject))
            if user is None:
                existing = await session.scalar(select(User).where(User.email == identity.email))
                if existing is not None:
                    # Proving control of an email at Google does not authorize access
                    # to a previously-created FamilyMed password account.
                    raise ApiError(
                        409,
                        "ACCOUNT_LINK_REQUIRED",
                        "This email is already registered. Sign in with your password and link Google in Me.",
                    )
                user = User(
                    name=identity.name,
                    email=identity.email,
                    password_hash=None,
                    google_subject=identity.subject,
                )
                session.add(user)
                await session.flush()
                family = Family(name=f"{identity.name}'s family", created_by_user_id=user.id)
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
        # Concurrent first login cannot create duplicate accounts or families.
        raise ApiError(409, "GOOGLE_ACCOUNT_CONFLICT", "Try signing in again.") from exc

    return AuthResponse(
        user=user,
        access_token=create_access_token(user.id),
        refresh_token=create_refresh_token(user.id),
    )


async def link_google_to_account(session: AsyncSession, user: User, token: str) -> None:
    identity = await verify_google_identity(token)
    if user.email != identity.email:
        raise ApiError(
            409,
            "GOOGLE_EMAIL_MISMATCH",
            "Choose the Google account with the same verified email as FamilyMed.",
        )
    if user.google_subject is not None and user.google_subject != identity.subject:
        raise ApiError(409, "GOOGLE_ALREADY_LINKED", "This account is already linked to Google.")
    existing = await session.scalar(select(User).where(User.google_subject == identity.subject))
    if existing is not None and existing.id != user.id:
        raise ApiError(409, "GOOGLE_ALREADY_LINKED", "This Google identity is already in use.")
    user.google_subject = identity.subject
    try:
        await session.commit()
    except IntegrityError as exc:
        await session.rollback()
        raise ApiError(409, "GOOGLE_ALREADY_LINKED", "This Google identity is already in use.") from exc
