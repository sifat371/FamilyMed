from datetime import date, timedelta
from uuid import UUID

import sqlalchemy as sa

from app.families.models import FamilyMember


async def register_user(client, email: str) -> dict[str, str]:
    response = await client.post(
        "/api/v1/auth/register",
        json={"name": "Caregiver", "email": email, "password": "password123"},
    )
    assert response.status_code == 201
    return response.json()


def auth_headers(auth: dict[str, str]) -> dict[str, str]:
    return {"Authorization": f"Bearer {auth['access_token']}"}


async def create_ammas_profile(client, auth: dict[str, str]):
    return await client.post(
        "/api/v1/family-members",
        headers=auth_headers(auth),
        json={
            "name": "Amma",
            "relationship": "mother",
            "preferred_language": "bn",
            "timezone": "Asia/Dhaka",
        },
    )


async def test_create_list_get_and_update_family_member(client):
    auth = await register_user(client, "owner@example.com")

    created = await create_ammas_profile(client, auth)
    assert created.status_code == 201
    member = created.json()
    assert member["name"] == "Amma"
    assert member["relationship"] == "mother"
    assert member["preferred_language"] == "bn"
    assert member["timezone"] == "Asia/Dhaka"

    listed = await client.get("/api/v1/family-members", headers=auth_headers(auth))
    assert listed.status_code == 200
    assert [item["id"] for item in listed.json()] == [member["id"]]

    fetched = await client.get(
        f"/api/v1/family-members/{member['id']}", headers=auth_headers(auth)
    )
    assert fetched.status_code == 200
    assert fetched.json()["name"] == "Amma"

    updated = await client.patch(
        f"/api/v1/family-members/{member['id']}",
        headers=auth_headers(auth),
        json={
            "name": "Ammu",
            "relationship": "parent",
            "preferred_language": "en",
            "timezone": "Asia/Dhaka",
            "date_of_birth": "1961-01-01",
        },
    )
    assert updated.status_code == 200
    assert updated.json()["name"] == "Ammu"
    assert updated.json()["relationship"] == "parent"
    assert updated.json()["preferred_language"] == "en"
    assert updated.json()["date_of_birth"] == "1961-01-01"


async def test_future_dob_and_invalid_timezone_use_validation_envelope(client):
    auth = await register_user(client, "validation@example.com")
    future = (date.today() + timedelta(days=1)).isoformat()

    future_dob = await client.post(
        "/api/v1/family-members",
        headers=auth_headers(auth),
        json={
            "name": "Amma",
            "relationship": "mother",
            "preferred_language": "bn",
            "timezone": "Asia/Dhaka",
            "date_of_birth": future,
        },
    )
    bad_timezone = await client.post(
        "/api/v1/family-members",
        headers=auth_headers(auth),
        json={
            "name": "Amma",
            "relationship": "mother",
            "preferred_language": "bn",
            "timezone": "Not/A_Real_Zone",
        },
    )

    for response in (future_dob, bad_timezone):
        assert response.status_code == 422
        assert response.json()["error"]["code"] == "VALIDATION_ERROR"


async def test_cross_family_member_read_and_update_return_scoped_404(client):
    owner_a = await register_user(client, "a@example.com")
    owner_b = await register_user(client, "b@example.com")
    created = await create_ammas_profile(client, owner_b)
    member_id = created.json()["id"]

    read = await client.get(
        f"/api/v1/family-members/{member_id}", headers=auth_headers(owner_a)
    )
    update = await client.patch(
        f"/api/v1/family-members/{member_id}",
        headers=auth_headers(owner_a),
        json={"name": "Probe"},
    )

    for response in (read, update):
        assert response.status_code == 404
        assert response.json()["error"]["code"] == "FAMILY_MEMBER_NOT_FOUND"


async def test_archived_member_is_omitted_from_normal_list(client, db_session):
    auth = await register_user(client, "archive@example.com")
    created = await create_ammas_profile(client, auth)
    member_id = UUID(created.json()["id"])

    member = await db_session.scalar(sa.select(FamilyMember).where(FamilyMember.id == member_id))
    assert member is not None
    member.archived_at = sa.func.now()
    await db_session.flush()

    listed = await client.get("/api/v1/family-members", headers=auth_headers(auth))
    assert listed.status_code == 200
    assert listed.json() == []
