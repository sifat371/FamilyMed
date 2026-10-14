"""OAuth regressions: the third-party identity boundary is mocked explicitly."""

from uuid import UUID

from sqlalchemy import select

import app.auth.google_service as google_service
import app.auth.router as auth_router
from app.auth.google_identity import GoogleIdentity
from app.common.errors import ApiError
from app.families.models import Family, FamilyMembership
from app.users.models import User

GOOGLE_URL = "/api/v1/auth/google"
LINK_URL = "/api/v1/auth/me/google"
DELETE_URL = "/api/v1/auth/me/delete"


def headers(auth: dict) -> dict[str, str]:
    return {"Authorization": f"Bearer {auth['access_token']}"}


def mock_google(monkeypatch, *, email="new@example.com", subject="google-123", name="Google User"):
    async def verify(_token: str) -> GoogleIdentity:
        return GoogleIdentity(subject=subject, email=email, name=name)
    monkeypatch.setattr(google_service, "verify_google_identity", verify)
    monkeypatch.setattr(auth_router, "verify_google_identity", verify)


async def test_google_creates_one_passwordless_account_and_is_idempotent(
    client, db_session, monkeypatch
):
    mock_google(monkeypatch)
    first = await client.post(GOOGLE_URL, json={"id_token": "a" * 64})
    assert first.status_code == 200, first.text
    auth = first.json()
    assert auth["user"]["has_password"] is False
    assert auth["user"]["google_linked"] is True
    assert auth["user"]["email"] == "new@example.com"

    second = await client.post(GOOGLE_URL, json={"id_token": "b" * 64})
    assert second.status_code == 200
    assert second.json()["user"]["id"] == auth["user"]["id"]
    user_id = UUID(auth["user"]["id"])
    assert await db_session.scalar(
        select(Family.id).where(Family.created_by_user_id == user_id)
    ) is not None
    count = await db_session.scalar(
        select(FamilyMembership.id).where(FamilyMembership.user_id == user_id)
    )
    assert count is not None

    password_attempt = await client.post(
        "/api/v1/auth/login",
        json={"email": "new@example.com", "password": "password123"},
    )
    assert password_attempt.status_code == 401


async def test_same_verified_email_does_not_automatically_take_over_password_account(
    client, monkeypatch
):
    registered = await client.post(
        "/api/v1/auth/register",
        json={"name": "Caregiver", "email": "owner@example.com", "password": "password123"},
    )
    assert registered.status_code == 201
    mock_google(monkeypatch, email="owner@example.com")
    blocked = await client.post(GOOGLE_URL, json={"id_token": "c" * 64})
    assert blocked.status_code == 409
    assert blocked.json()["error"]["code"] == "ACCOUNT_LINK_REQUIRED"

    linked = await client.post(LINK_URL, headers=headers(registered.json()), json={
        "id_token": "d" * 64,
    })
    assert linked.status_code == 204
    google_login = await client.post(GOOGLE_URL, json={"id_token": "e" * 64})
    assert google_login.status_code == 200
    assert google_login.json()["user"]["id"] == registered.json()["user"]["id"]
    assert google_login.json()["user"]["has_password"] is True


async def test_google_linking_requires_same_email_and_distinct_verified_identity(
    client, monkeypatch
):
    registered = await client.post(
        "/api/v1/auth/register",
        json={"name": "Caregiver", "email": "first@example.com", "password": "password123"},
    )
    mock_google(monkeypatch, email="other@example.com")
    denied = await client.post(
        LINK_URL, headers=headers(registered.json()), json={"id_token": "f" * 64}
    )
    assert denied.status_code == 409
    assert denied.json()["error"]["code"] == "GOOGLE_EMAIL_MISMATCH"


async def test_google_only_deletion_requires_matching_fresh_google_identity(
    client, db_session, monkeypatch
):
    mock_google(monkeypatch)
    auth = (await client.post(GOOGLE_URL, json={"id_token": "a" * 64})).json()
    without_credential = await client.post(
        DELETE_URL, headers=headers(auth), json={}
    )
    assert without_credential.status_code == 422

    async def wrong_identity(_token: str) -> GoogleIdentity:
        return GoogleIdentity(subject="attacker", email="new@example.com", name="Attacker")
    monkeypatch.setattr(auth_router, "verify_google_identity", wrong_identity)
    wrong = await client.post(
        DELETE_URL, headers=headers(auth), json={"google_id_token": "d" * 64}
    )
    assert wrong.status_code == 401

    mock_google(monkeypatch)
    deleted = await client.post(
        DELETE_URL, headers=headers(auth), json={"google_id_token": "b" * 64}
    )
    assert deleted.status_code == 204
    assert await db_session.get(User, UUID(auth["user"]["id"])) is None


async def test_invalid_google_token_does_not_issue_familymed_tokens(client, monkeypatch):
    async def reject(_token: str) -> GoogleIdentity:
        raise ApiError(401, "INVALID_GOOGLE_TOKEN", "Google authentication was not verified.")
    monkeypatch.setattr(google_service, "verify_google_identity", reject)
    denied = await client.post(GOOGLE_URL, json={"id_token": "invalid" * 8})
    assert denied.status_code == 401
    assert denied.json()["error"]["code"] == "INVALID_GOOGLE_TOKEN"
    assert "access_token" not in denied.text
