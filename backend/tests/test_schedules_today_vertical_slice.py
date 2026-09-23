from datetime import UTC, datetime, time, timedelta
from uuid import UUID, uuid4
from zoneinfo import ZoneInfo

from sqlalchemy import delete, func, select

from app.doses.models import DoseLog, ScheduledDose
from app.schedules.generation import generate_schedule_window
from app.schedules.models import MedicationSchedule


def _headers(auth: dict[str, object]) -> dict[str, str]:
    return {"Authorization": f"Bearer {auth['access_token']}"}


async def _register(client, email: str) -> dict[str, object]:
    response = await client.post(
        "/api/v1/auth/register",
        json={"name": "Caregiver", "email": email, "password": "password123"},
    )
    assert response.status_code == 201
    return response.json()


async def test_schedules_today_vertical_slice(client, db_session):
    owner = await _register(client, f"vertical-{uuid4()}@example.com")
    outsider = await _register(client, f"outsider-{uuid4()}@example.com")

    member_response = await client.post(
        "/api/v1/family-members",
        headers=_headers(owner),
        json={
            "name": "Amma",
            "relationship": "mother",
            "preferred_language": "bn",
            "timezone": "Asia/Dhaka",
        },
    )
    assert member_response.status_code == 201
    member = member_response.json()

    local_today = datetime.now(UTC).astimezone(ZoneInfo("Asia/Dhaka")).date()
    medication_response = await client.post(
        f"/api/v1/family-members/{member['id']}/medications",
        headers=_headers(owner),
        json={
            "display_name": "Metformin",
            "strength": "500 mg",
            "dosage_form": "tablet",
            "start_date": local_today.isoformat(),
        },
    )
    assert medication_response.status_code == 201
    medication = medication_response.json()

    schedule_response = await client.post(
        f"/api/v1/member-medications/{medication['id']}/schedules",
        headers=_headers(owner),
        json={
            "raw_instruction": "1+0+1 PC",
            "meal_relation": "after_food",
            "timezone": "Asia/Dhaka",
            "start_date": local_today.isoformat(),
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
    schedule_body = schedule_response.json()
    assert schedule_body["status"] == "active"

    schedule_id = UUID(schedule_body["id"])
    schedule = await db_session.get(MedicationSchedule, schedule_id)
    assert schedule is not None

    # Rebuild today's window from 07:00 local so both 08:00 and 20:00
    # occurrences exist regardless of the wall-clock time at which CI runs.
    await db_session.execute(
        delete(ScheduledDose).where(ScheduledDose.schedule_id == schedule_id)
    )
    controlled_now = datetime.combine(
        local_today,
        time(7, 0),
        tzinfo=ZoneInfo("Asia/Dhaka"),
    ).astimezone(UTC)
    schedule.generation_not_before_at = controlled_now
    await db_session.flush()
    await generate_schedule_window(db_session, schedule_id, controlled_now)
    await db_session.flush()

    doses = list(
        (
            await db_session.scalars(
                select(ScheduledDose)
                .where(
                    ScheduledDose.schedule_id == schedule_id,
                    ScheduledDose.scheduled_local_date == local_today,
                )
                .order_by(ScheduledDose.scheduled_local_time)
            )
        ).all()
    )
    assert [dose.scheduled_local_time.strftime("%H:%M") for dose in doses] == [
        "08:00",
        "20:00",
    ]
    morning, evening = doses

    # Force the two due states needed for a deterministic acceptance flow.
    morning.status = "pending"
    evening.status = "pending"
    await db_session.flush()

    today = await client.get("/api/v1/today", headers=_headers(owner))
    assert today.status_code == 200
    amma = next(group for group in today.json() if group["member_id"] == member["id"])
    assert amma["total_count"] == 2

    now = datetime.now(UTC)
    taken_action_id = uuid4()
    taken_payload = {
        "client_action_id": str(taken_action_id),
        "occurred_at": now.isoformat(),
    }
    taken = await client.post(
        f"/api/v1/doses/{morning.id}/taken",
        headers=_headers(owner),
        json=taken_payload,
    )
    assert taken.status_code == 200
    assert taken.json()["status"] == "taken"

    duplicate = await client.post(
        f"/api/v1/doses/{morning.id}/taken",
        headers=_headers(owner),
        json=taken_payload,
    )
    assert duplicate.status_code == 200
    duplicate_log_count = await db_session.scalar(
        select(func.count())
        .select_from(DoseLog)
        .where(DoseLog.client_action_id == taken_action_id)
    )
    assert duplicate_log_count == 1

    snooze = await client.post(
        f"/api/v1/doses/{evening.id}/snooze",
        headers=_headers(owner),
        json={
            "client_action_id": str(uuid4()),
            "occurred_at": now.isoformat(),
            "snoozed_until": (now.replace(microsecond=0) + timedelta(minutes=15)).isoformat(),
        },
    )
    assert snooze.status_code == 200
    assert snooze.json()["status"] == "pending"
    assert snooze.json()["snoozed_until"] is not None

    skipped = await client.post(
        f"/api/v1/doses/{evening.id}/skip",
        headers=_headers(owner),
        json={
            "client_action_id": str(uuid4()),
            "occurred_at": datetime.now(UTC).isoformat(),
        },
    )
    assert skipped.status_code == 200
    assert skipped.json()["status"] == "skipped"

    history = await client.get(
        f"/api/v1/family-members/{member['id']}/history",
        headers=_headers(owner),
    )
    assert history.status_code == 200
    history_body = history.json()
    assert history_body["marked_adherence_percentage"] == "50.00"
    day = next(\n        item\n        for item in history_body["days"]\n        if item["local_date"] == local_today.isoformat()\n    )
    history_doses = {item["id"]: item for item in day["doses"]}
    assert [event["action"] for event in history_doses[str(evening.id)]["events"]] == [
        "snoozed",
        "skipped",
    ]

    corrected = await client.post(
        f"/api/v1/doses/{evening.id}/correct",
        headers=_headers(owner),
        json={
            "client_action_id": str(uuid4()),
            "occurred_at": datetime.now(UTC).isoformat(),
            "new_status": "taken",
            "effective_at": (datetime.now(UTC) - timedelta(minutes=1)).isoformat(),
            "reason": "Recorded late by caregiver",
        },
    )
    assert corrected.status_code == 200
    assert corrected.json()["status"] == "taken"

    preserved_ids = {morning.id, evening.id}
    edited = await client.patch(
        f"/api/v1/schedules/{schedule_id}",
        headers=_headers(owner),
        json={
            "raw_instruction": "1+0+1 PC",
            "meal_relation": "after_food",
            "timezone": "Asia/Dhaka",
            "start_date": local_today.isoformat(),
            "times": [
                {
                    "period": "morning",
                    "local_time": "09:00",
                    "quantity": "1",
                    "unit": "tablet",
                },
                {
                    "period": "night",
                    "local_time": "21:00",
                    "quantity": "1",
                    "unit": "tablet",
                },
            ],
        },
    )
    assert edited.status_code == 200
    for dose_id in preserved_ids:
        assert await db_session.get(ScheduledDose, dose_id) is not None

    hidden = await client.post(
        f"/api/v1/doses/{morning.id}/taken",
        headers=_headers(outsider),
        json={
            "client_action_id": str(uuid4()),
            "occurred_at": datetime.now(UTC).isoformat(),
        },
    )
    assert hidden.status_code == 404
