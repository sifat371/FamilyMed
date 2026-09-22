import sqlalchemy as sa

from app.families.models import Family, FamilyMembership
from app.users.models import User

REGISTER_URL = "/api/v1/auth/register"
LOGIN_URL = "/api/v1/auth/login"
REFRESH_URL = "/api/v1/auth/refresh"
ME_URL = "/api/v1/auth/me"


async def register(client, *, email="user@example.com", password="password123", name="Sifat"):
    return await client.post(
        REGISTER_URL,
        json={"name": name, "email": email, "password": password},
    )


async def test_user_family_membership_models_persist(db_session):
    user = User(name="Sifat", email="sifat@example.com", password_hash="argon2-hash")
    db_session.add(user)
    await db_session.flush()
    family = Family(name="Sifat's family", created_by_user_id=user.id)
    db_session.add(family)
    await db_session.flush()
    membership = FamilyMembership(
        family_id=family.id,
        user_id=user.id,
        role="owner",
        status="active",
    )
    db_session.add(membership)
    await db_session.flush()
    saved = await db_session.scalar(sa.select(User).where(User.id == user.id))
    assert saved is not None
    assert saved.email == "sifat@example.com"
    assert membership.role == "owner"
    assert membership.status == "active"


async def test_register_normalizes_email_hashes_password_and_creates_family(client, db_session):
    response = await register(client, email=" USER@Example.com ", name=" Sifat ")

    assert response.status_code == 201
    body = response.json()
    assert body["user"]["name"] == "Sifat"
    assert body["user"]["email"] == "user@example.com"
    assert body["access_token"]
    assert body["refresh_token"]
    assert body["token_type"] == "bearer"
    assert "password_hash" not in body["user"]

    user = await db_session.scalar(sa.select(User).where(User.email == "user@example.com"))
    assert user is not None
    assert user.password_hash != "password123"
    assert user.password_hash.startswith("$argon2")
    family_count = await db_session.scalar(
        sa.select(sa.func.count(Family.id)).where(Family.created_by_user_id == user.id)
    )
    membership_count = await db_session.scalar(
        sa.select(sa.func.count(FamilyMembership.id)).where(
            FamilyMembership.user_id == user.id,
            FamilyMembership.role == "owner",
            FamilyMembership.status == "active",
        )
    )
    assert family_count == 1
    assert membership_count == 1


async def test_duplicate_normalized_email_returns_standard_409(client):
    first = await register(client, email="user@example.com")
    assert first.status_code == 201

    response = await register(client, email=" USER@EXAMPLE.COM ")

    assert response.status_code == 409
    assert response.json()["error"]["code"] == "EMAIL_ALREADY_REGISTERED"


async def test_wrong_password_and_unknown_email_share_generic_error(client):
    await register(client)

    wrong = await client.post(
        LOGIN_URL,
        json={"email": "user@example.com", "password": "wrongpass"},
    )
    missing = await client.post(
        LOGIN_URL,
        json={"email": "nobody@example.com", "password": "wrongpass"},
    )

    assert wrong.status_code == 401
    assert missing.status_code == 401
    assert wrong.json() == missing.json()
    assert wrong.json()["error"]["code"] == "INVALID_CREDENTIALS"


async def test_password_length_validation_uses_standard_envelope(client):
    too_short = await register(client, email="short@example.com", password="1234567")
    too_long = await register(client, email="long@example.com", password="x" * 129)

    for response in (too_short, too_long):
        assert response.status_code == 422
        assert response.json()["error"]["code"] == "VALIDATION_ERROR"


async def test_jwt_type_enforcement_refresh_and_me(client):
    registration = await register(client)
    tokens = registration.json()

    access_as_refresh = await client.post(
        REFRESH_URL,
        json={"refresh_token": tokens["access_token"]},
    )
    assert access_as_refresh.status_code == 401
    assert access_as_refresh.json()["error"]["code"] == "INVALID_TOKEN"

    refresh_as_access = await client.get(
        ME_URL,
        headers={"Authorization": f"Bearer {tokens['refresh_token']}"},
    )
    assert refresh_as_access.status_code == 401
    assert refresh_as_access.json()["error"]["code"] == "INVALID_TOKEN"

    refreshed = await client.post(
        REFRESH_URL,
        json={"refresh_token": tokens["refresh_token"]},
    )
    assert refreshed.status_code == 200
    assert set(refreshed.json()) == {"access_token", "token_type"}
    assert refreshed.json()["token_type"] == "bearer"

    me = await client.get(
        ME_URL,
        headers={"Authorization": f"Bearer {refreshed.json()['access_token']}"},
    )
    assert me.status_code == 200
    assert set(me.json()) == {"id", "name", "email", "preferred_language", "timezone"}
    assert me.json()["email"] == "user@example.com"


async def test_me_without_bearer_token_returns_standard_invalid_token(client):
    response = await client.get(ME_URL)
    assert response.status_code == 401
    assert response.json()["error"]["code"] == "INVALID_TOKEN"
