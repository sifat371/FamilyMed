from datetime import UTC, datetime, timedelta
from uuid import uuid4
from zoneinfo import ZoneInfo


def _headers(auth: dict[str, object]) -> dict[str, str]:
    return {"Authorization": f"Bearer {auth['access_token']}"}


async def _register(client, email: str) -> dict[str, object]:
    response = await client.post(
        "/api/v1/auth/register",
        json={"name": "Caregiver", "email": email, "password": "password123"},
    )
    assert response.status_code == 201
    return response.json()


async def test_reminder_feed_only_returns_enabled_members(client):
    auth = await _register(client, f"reminder-pref-{uuid4()}@example.com")
    member_response = await client.post(
        "/api/v1/family-members",
        headers=_headers(auth),
        json={
            "name": "Amma",
            "relationship": "mother",
            "preferred_language": "bn",
            "timezone": "Asia/Dhaka",
        },
    )
    assert member_response.status_code == 201
    member = member_response.json()

    local_tomorrow = (
        datetime.now(UTC).astimezone(ZoneInfo("Asia/Dhaka")).date()
        + timedelta(days=1)
    )
    medication_response = await client.post(
        f"/api/v1/family-members/{member['id']}/medications",
        headers=_headers(auth),
        json={
            "display_name": "Metformin",
            "strength": "500 mg",
            "dosage_form": "tablet",
            "start_date": local_tomorrow.isoformat(),
        },
    )
    assert medication_response.status_code == 201
    medication = medication_response.json()

    schedule_response = await client.post(
        f"/api/v1/member-medications/{medication['id']}/schedules",
        headers=_headers(auth),
        json={
            "raw_instruction": "1+0+0",
            "meal_relation": "after_food",
            "timezone": "Asia/Dhaka",
            "start_date": local_tomorrow.isoformat(),
            "times": [
                {
                    "period": "morning",
                    "local_time": "08:00",
                    "quantity": "1",
                    "unit": "tablet",
                }
            ],
        },
    )
    assert schedule_response.status_code == 201

    disabled = await client.get(
        "/api/v1/reminder-doses?days=30",
        headers=_headers(auth),
    )
    assert disabled.status_code == 200
    assert disabled.json() == []

    preference = await client.patch(
        f"/api/v1/family-members/{member['id']}/notification-preference",
        headers=_headers(auth),
        json={"enabled": True},
    )
    assert preference.status_code == 200

    enabled = await client.get(
        "/api/v1/reminder-doses?days=30",
        headers=_headers(auth),
    )
    assert enabled.status_code == 200
    assert enabled.json()
    assert {dose["family_member_id"] for dose in enabled.json()} == {member["id"]}


async def test_reminder_feed_validates_days(client):
    auth = await _register(client, f"reminder-days-{uuid4()}@example.com")

    too_small = await client.get(
        "/api/v1/reminder-doses?days=0",
        headers=_headers(auth),
    )
    assert too_small.status_code == 422

    too_large = await client.get(
        "/api/v1/reminder-doses?days=31",
        headers=_headers(auth),
    )
    assert too_large.status_code == 422
