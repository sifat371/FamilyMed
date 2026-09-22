from datetime import UTC, datetime, timedelta
from uuid import UUID

import jwt
from pwdlib import PasswordHash

from app.common.errors import ApiError
from app.config import get_settings

settings = get_settings()
password_hasher = PasswordHash.recommended()
DUMMY_PASSWORD_HASH = password_hasher.hash("familymed-login-timing-dummy")


def invalid_token_error() -> ApiError:
    return ApiError(
        401,
        "INVALID_TOKEN",
        "Authentication is invalid or expired.",
    )


def hash_password(value: str) -> str:
    return password_hasher.hash(value)


def verify_password(value: str, encoded: str) -> bool:
    return password_hasher.verify(value, encoded)


def _create_token(user_id: UUID, token_type: str, lifetime: timedelta) -> str:
    now = datetime.now(UTC)
    return jwt.encode(
        {
            "sub": str(user_id),
            "type": token_type,
            "iat": now,
            "exp": now + lifetime,
        },
        settings.jwt_secret,
        algorithm=settings.jwt_algorithm,
    )


def create_access_token(user_id: UUID) -> str:
    return _create_token(
        user_id,
        "access",
        timedelta(minutes=settings.access_token_minutes),
    )


def create_refresh_token(user_id: UUID) -> str:
    return _create_token(
        user_id,
        "refresh",
        timedelta(days=settings.refresh_token_days),
    )


def decode_token(token: str, expected_type: str) -> UUID:
    try:
        payload = jwt.decode(
            token,
            settings.jwt_secret,
            algorithms=[settings.jwt_algorithm],
            options={"require": ["sub", "type", "iat", "exp"]},
        )
        if payload["type"] != expected_type:
            raise invalid_token_error()
        return UUID(payload["sub"])
    except ApiError:
        raise
    except (
        jwt.ExpiredSignatureError,
        jwt.InvalidTokenError,
        KeyError,
        TypeError,
        ValueError,
    ) as exc:
        raise invalid_token_error() from exc
