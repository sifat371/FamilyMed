from datetime import UTC, datetime, timedelta
from uuid import UUID, uuid4
from zoneinfo import ZoneInfo

from sqlalchemy import select

from app.doses.models import ScheduledDose


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
    assert {dose["family_member_name"] for dose in enabled.json()} == {"Amma"}


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


async def test_reminder_feed_excludes_paused_and_ended_pending_doses(
    client,
    db_session,
):
    auth = await _register(client, f"reminder-lifecycle-{uuid4()}@example.com")
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
            "display_name": "Napa",
            "strength": "500",
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
    schedule_id = UUID(schedule_response.json()["id"])
    dose = await db_session.scalar(
        select(ScheduledDose)
        .where(ScheduledDose.schedule_id == schedule_id)
        .order_by(ScheduledDose.scheduled_at)
        .limit(1)
    )
    assert dose is not None
    dose.status = "pending"
    await db_session.flush()

    preference = await client.patch(
        f"/api/v1/family-members/{member['id']}/notification-preference",
        headers=_headers(auth),
        json={"enabled": True},
    )
    assert preference.status_code == 200

    active = await client.get(
        "/api/v1/reminder-doses?days=30",
        headers=_headers(auth),
    )
    assert active.status_code == 200
    assert str(dose.id) in {item["id"] for item in active.json()}

    paused = await client.post(
        f"/api/v1/member-medications/{medication['id']}/pause",
        headers=_headers(auth),
    )
    assert paused.status_code == 200
    while_paused = await client.get(
        "/api/v1/reminder-doses?days=30",
        headers=_headers(auth),
    )
    assert while_paused.status_code == 200
    assert str(dose.id) not in {item["id"] for item in while_paused.json()}

    resumed = await client.post(
        f"/api/v1/member-medications/{medication['id']}/resume",
        headers=_headers(auth),
    )
    assert resumed.status_code == 200
    after_resume = await client.get(
        "/api/v1/reminder-doses?days=30",
        headers=_headers(auth),
    )
    assert after_resume.status_code == 200
    assert str(dose.id) in {item["id"] for item in after_resume.json()}

    ended = await client.post(
        f"/api/v1/member-medications/{medication['id']}/end",
        headers=_headers(auth),
    )
    assert ended.status_code == 200
    after_end = await client.get(
        "/api/v1/reminder-doses?days=30",
        headers=_headers(auth),
    )
    assert after_end.status_code == 200
    assert str(dose.id) not in {item["id"] for item in after_end.json()}
