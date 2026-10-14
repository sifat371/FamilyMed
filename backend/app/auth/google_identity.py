"""Server-side verification of Google ID tokens; never trust client email claims."""

import asyncio
from dataclasses import dataclass

from google.auth.exceptions import GoogleAuthError
from google.auth.transport.requests import Request
from google.oauth2 import id_token

from app.common.errors import ApiError
from app.config import get_settings


@dataclass(frozen=True)
class GoogleIdentity:
    subject: str
    email: str
    name: str


async def verify_google_identity(token: str) -> GoogleIdentity:
    audience = get_settings().google_web_client_id.strip()
    if not audience:
        raise ApiError(503, "GOOGLE_SIGN_IN_UNAVAILABLE", "Google sign-in is not configured.")

    try:
        claims = await asyncio.to_thread(id_token.verify_oauth2_token, token, Request(), audience)
    except (ValueError, GoogleAuthError) as exc:
        raise ApiError(
            401, "INVALID_GOOGLE_TOKEN", "Google authentication was not verified."
        ) from exc

    # Never use an unverified email or the mutable email as a Google identity key.
    if claims.get("email_verified") is not True:
        raise ApiError(401, "INVALID_GOOGLE_TOKEN", "Google email address is not verified.")
    subject = claims.get("sub")
    email = claims.get("email")
    if not isinstance(subject, str) or not subject or len(subject) > 255:
        raise ApiError(401, "INVALID_GOOGLE_TOKEN", "Google identity is invalid.")
    if not isinstance(email, str) or not email.strip() or len(email) > 255:
        raise ApiError(401, "INVALID_GOOGLE_TOKEN", "Google email address is invalid.")
    display = claims.get("name")
    name = display.strip() if isinstance(display, str) else ""
    return GoogleIdentity(
        subject=subject,
        email=email.strip().lower(),
        name=(name or email.split("@", 1)[0])[:120],
    )
