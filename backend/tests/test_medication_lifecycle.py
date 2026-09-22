from datetime import UTC, datetime
from uuid import UUID

from sqlalchemy import func, select

from app.doses.models import ScheduledDose
from app.medications.models import MemberMedication
from app.schedules.models import MedicationSchedule


async def _register(client, email: str) -> dict[str, object]:
    response = await client.post(
        "/api/v1/auth/register",
        json={"name": "Caregiver", "email": email, "password": "password123"},
    )
    assert response.status_code == 201
    return response.json()


def _headers(auth: dict[str, object]) -> dict[str, str]:
    return {"Authorization": f"Bearer {auth['access_token']}"}


def _uuid(value: object) -> UUID:
    return UUID(str(value))


async def _setup(client, email: str):
    auth = await _register(client, email)
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
    medication = await client.post(
        f"/api/v1/family-members/{member.json()['id']}/medications",
        headers=_headers(auth),
        json={
            "display_name": "Metformin",
            "strength": "500 mg",
            "dosage_form": "tablet",
            "start_date": "2026-09-23",
        },
    )
    assert medication.status_code == 201
    schedule = await client.post(
        f"/api/v1/member-medications/{medication.json()['id']}/schedules",
        headers=_headers(auth),
        json={
            "timezone": "Asia/Dhaka",
            "start_date": "2026-09-23",
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
    assert schedule.status_code == 201
    return auth, medication.json(), schedule.json()


async def test_pause_preserves_pending_resume_uses_new_boundary_and_end_preserves_history(
    client,
    db_session,
):
    auth, medication, schedule = await _setup(client, "lifecycle@example.com")
    medication_id = _uuid(medication["id"])
    schedule_id = _uuid(schedule["id"])

    pending = await db_session.scalar(
        select(ScheduledDose)
        .where(ScheduledDose.schedule_id == schedule_id)
        .order_by(ScheduledDose.scheduled_at)
        .limit(1)
    )
    assert pending is not None
    pending.status = "pending"
    await db_session.flush()
    pending_id = pending.id

    paused = await client.post(
        f"/api/v1/member-medications/{medication_id}/pause",
        headers=_headers(auth),
    )
    assert paused.status_code == 200
    assert paused.json()["status"] == "paused"
    persisted_schedule = await db_session.get(MedicationSchedule, schedule_id)
    assert persisted_schedule is not None
    assert persisted_schedule.status == "paused"
    assert await db_session.get(ScheduledDose, pending_id) is not None
    remaining = await db_session.scalar(
        select(func.count())
        .select_from(ScheduledDose)
        .where(ScheduledDose.schedule_id == schedule_id)
    )
    assert remaining == 1

    old_boundary = persisted_schedule.generation_not_before_at
    resumed = await client.post(
        f"/api/v1/member-medications/{medication_id}/resume",
        headers=_headers(auth),
    )
    assert resumed.status_code == 200
    assert resumed.json()["status"] == "active"
    await db_session.refresh(persisted_schedule)
    assert persisted_schedule.status == "active"
    assert persisted_schedule.generation_not_before_at >= old_boundary
    generated_before_boundary = await db_session.scalar(
        select(func.count())
        .select_from(ScheduledDose)
        .where(
            ScheduledDose.schedule_id == schedule_id,
            ScheduledDose.status == "upcoming",
            ScheduledDose.scheduled_at < persisted_schedule.generation_not_before_at,
        )
    )
    assert generated_before_boundary == 0

    ended = await client.post(
        f"/api/v1/member-medications/{medication_id}/end",
        headers=_headers(auth),
    )
    assert ended.status_code == 200
    assert ended.json()["status"] == "ended"
    await db_session.refresh(persisted_schedule)
    assert persisted_schedule.status == "ended"
    assert await db_session.get(ScheduledDose, pending_id) is not None
    upcoming = await db_session.scalar(
        select(func.count())
        .select_from(ScheduledDose)
        .where(
            ScheduledDose.schedule_id == schedule_id,
            ScheduledDose.status == "upcoming",
        )
    )
    assert upcoming == 0


async def test_cross_family_lifecycle_action_returns_404(client):
    owner_a = await _register(client, "lifecycle-a@example.com")
    owner_b, medication_b, _ = await _setup(client, "lifecycle-b@example.com")
    response = await client.post(
        f"/api/v1/member-medications/{medication_b['id']}/pause",
        headers=_headers(owner_a),
    )
    assert response.status_code == 404
    assert response.json()["error"]["code"] == "MEDICATION_NOT_FOUND"


def test_lifecycle_test_clock_is_explicit_utc():
    assert datetime(2026, 9, 23, 0, 0, tzinfo=UTC).utcoffset().total_seconds() == 0
