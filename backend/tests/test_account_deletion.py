from uuid import UUID

from sqlalchemy import select

from app.families.models import Family, FamilyMember
from app.medications.models import MemberMedication
from app.schedules.models import MedicationSchedule
from app.users.models import User


async def _register(client, email: str) -> dict:
    response = await client.post(
        "/api/v1/auth/register",
        json={"name": "Caregiver", "email": email, "password": "password123"},
    )
    assert response.status_code == 201
    return response.json()


def _headers(auth: dict) -> dict[str, str]:
    return {"Authorization": f"Bearer {auth['access_token']}"}


async def test_password_confirmed_deletion_removes_account_medication_and_schedule(
    client, db_session
):
    owned = await _register(client, "delete-owner@example.com")
    other = await _register(client, "delete-other@example.com")
    member = await client.post(
        "/api/v1/family-members",
        headers=_headers(owned),
        json={
            "name": "Care recipient",
            "relationship": "parent",
            "preferred_language": "bn",
            "timezone": "Asia/Dhaka",
        },
    )
    assert member.status_code == 201
    medication = await client.post(
        f"/api/v1/family-members/{member.json()['id']}/medications",
        headers=_headers(owned),
        json={"display_name": "Test medication", "start_date": "2026-10-10"},
    )
    assert medication.status_code == 201
    schedule = await client.post(
        f"/api/v1/member-medications/{medication.json()['id']}/schedules",
        headers=_headers(owned),
        json={
            "raw_instruction": "once daily",
            "meal_relation": "after_food",
            "timezone": "Asia/Dhaka",
            "start_date": "2026-10-10",
            "times": [
                {"period": "morning", "local_time": "08:00", "quantity": "1", "unit": "tablet"}
            ],
        },
    )
    assert schedule.status_code == 201

    bad = await client.post(
        "/api/v1/auth/me/delete",
        headers=_headers(owned),
        json={"password": "wrongpassword"},
    )
    assert bad.status_code == 401
    assert (await client.get("/api/v1/auth/me", headers=_headers(owned))).status_code == 200

    deleted = await client.post(
        "/api/v1/auth/me/delete",
        headers=_headers(owned),
        json={"password": "password123"},
    )
    assert deleted.status_code == 204
    assert (await client.get("/api/v1/auth/me", headers=_headers(owned))).status_code == 401
    assert (
        await client.post(
            "/api/v1/auth/login",
            json={"email": "delete-owner@example.com", "password": "password123"},
        )
    ).status_code == 401

    assert await db_session.get(User, UUID(owned["user"]["id"])) is None
    assert await db_session.get(FamilyMember, UUID(member.json()["id"])) is None
    assert await db_session.get(MemberMedication, UUID(medication.json()["id"])) is None
    assert await db_session.get(MedicationSchedule, UUID(schedule.json()["id"])) is None
    assert await db_session.scalar(
        select(Family.id).where(Family.created_by_user_id == UUID(owned["user"]["id"]))
    ) is None

    # Deleting one caregiver must never affect unrelated families.
    still_there = await client.get("/api/v1/auth/me", headers=_headers(other))
    assert still_there.status_code == 200


async def test_deletion_requires_authenticated_password(client):
    await _register(client, "delete-protected@example.com")
    unauthenticated = await client.post(
        "/api/v1/auth/me/delete", json={"password": "password123"}
    )
    assert unauthenticated.status_code == 401
