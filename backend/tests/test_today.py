from datetime import UTC, datetime, timedelta
from uuid import UUID
from zoneinfo import ZoneInfo

from sqlalchemy import select

from app.doses.models import ScheduledDose
from app.doses.projections import build_reminder_feed, build_today


async def _register(client, email: str) -> dict[str, object]:
    response = await client.post(
        "/api/v1/auth/register",
        json={"name": "Caregiver", "email": email, "password": "test-pass-123"},
    )
    assert response.status_code == 201
    return response.json()


def _headers(auth: dict[str, object]) -> dict[str, str]:
    return {"Authorization": f"Bearer {auth['access_token']}"}


async def test_today_returns_accessible_member_even_without_doses(client):
    auth = await _register(client, "today-empty@example.com")
    member = await client.post(
        "/api/v1/family-members",
        headers=_headers(auth),
        json={
            "name": "Amma",
            "relationship": "mother",
            "preferred_language": "bn",
            "timezone": "Asia/Dhaka",
        },
    )
    assert member.status_code == 201

    response = await client.get("/api/v1/today", headers=_headers(auth))
    assert response.status_code == 200
    assert response.json()[0]["member_name"] == "Amma"
    assert response.json()[0]["taken_count"] == 0
    assert response.json()[0]["total_count"] == 0
    assert response.json()[0]["doses"] == []


async def test_reminder_feed_is_authenticated_and_limited_to_30_days(client):
    auth = await _register(client, "reminder-feed@example.com")
    response = await client.get(
        "/api/v1/reminder-doses?days=30",
        headers=_headers(auth),
    )
    assert response.status_code == 200
    assert response.json() == []

    invalid = await client.get(
        "/api/v1/reminder-doses?days=31",
        headers=_headers(auth),
    )
    assert invalid.status_code == 422


def test_projection_functions_are_exposed():
    assert build_today is not None
    assert build_reminder_feed is not None


async def test_today_hides_ended_pending_but_preserves_final_and_history(
    client,
    db_session,
):
    auth = await _register(client, "today-ended-pending@example.com")
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

    now = datetime.now(UTC)
    local_today = now.astimezone(ZoneInfo("Asia/Dhaka")).date()
    local_tomorrow = local_today + timedelta(days=1)
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
                },
                {
                    "period": "night",
                    "local_time": "20:00",
                    "quantity": "1",
                    "unit": "tablet",
                },
            ],
        },
    )
    assert schedule_response.status_code == 201
    schedule_id = UUID(schedule_response.json()["id"])
    doses = list(
        (
            await db_session.scalars(
                select(ScheduledDose)
                .where(ScheduledDose.schedule_id == schedule_id)
                .order_by(ScheduledDose.scheduled_at)
                .limit(2)
            )
        ).all()
    )
    assert len(doses) == 2
    pending, taken = doses
    pending.scheduled_local_date = local_today
    pending.scheduled_local_time = datetime.strptime("22:00", "%H:%M").time()
    pending.scheduled_at = now - timedelta(minutes=5)
    pending.status = "pending"
    taken.scheduled_local_date = local_today
    taken.scheduled_local_time = datetime.strptime("21:00", "%H:%M").time()
    taken.scheduled_at = now - timedelta(minutes=10)
    taken.status = "taken"
    taken.taken_at = now - timedelta(minutes=9)
    await db_session.flush()

    active_today = await client.get("/api/v1/today", headers=_headers(auth))
    assert active_today.status_code == 200
    active_ids = {
        item["id"]
        for group in active_today.json()
        for item in group["doses"]
    }
    assert str(pending.id) in active_ids
    assert str(taken.id) in active_ids

    paused = await client.post(
        f"/api/v1/member-medications/{medication['id']}/pause",
        headers=_headers(auth),
    )
    assert paused.status_code == 200
    while_paused = await client.get("/api/v1/today", headers=_headers(auth))
    assert while_paused.status_code == 200
    paused_ids = {
        item["id"]
        for group in while_paused.json()
        for item in group["doses"]
    }
    assert str(pending.id) not in paused_ids
    assert str(taken.id) in paused_ids

    resumed = await client.post(
        f"/api/v1/member-medications/{medication['id']}/resume",
        headers=_headers(auth),
    )
    assert resumed.status_code == 200
    after_resume = await client.get("/api/v1/today", headers=_headers(auth))
    assert after_resume.status_code == 200
    resumed_ids = {
        item["id"]
        for group in after_resume.json()
        for item in group["doses"]
    }
    assert str(pending.id) in resumed_ids
    assert str(taken.id) in resumed_ids

    ended = await client.post(
        f"/api/v1/member-medications/{medication['id']}/end",
        headers=_headers(auth),
    )
    assert ended.status_code == 200

    after_end = await client.get("/api/v1/today", headers=_headers(auth))
    assert after_end.status_code == 200
    after_ids = {
        item["id"]
        for group in after_end.json()
        for item in group["doses"]
    }
    assert str(pending.id) not in after_ids
    assert str(taken.id) in after_ids

    history = await client.get(
        f"/api/v1/family-members/{member['id']}/history",
        headers=_headers(auth),
    )
    assert history.status_code == 200
    history_ids = {
        item["id"]
        for day in history.json()["days"]
        for item in day["doses"]
    }
    assert str(pending.id) in history_ids
    assert str(taken.id) in history_ids
