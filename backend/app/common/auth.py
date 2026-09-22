from typing import Annotated

from fastapi import Depends
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.security import decode_token
from app.common.errors import ApiError
from app.db import get_db_session
from app.users.models import User

bearer_scheme = HTTPBearer(auto_error=False)


async def get_current_user(
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer_scheme)],
    session: Annotated[AsyncSession, Depends(get_db_session)],
) -> User:
    if credentials is None or credentials.scheme.lower() != "bearer":
        raise ApiError(
            401,
            "INVALID_TOKEN",
            "Authentication is invalid or expired.",
        )

    user_id = decode_token(credentials.credentials, "access")
    user = await session.scalar(select(User).where(User.id == user_id))
    if user is None:
        raise ApiError(
            401,
            "INVALID_TOKEN",
            "Authentication is invalid or expired.",
        )
    return user
