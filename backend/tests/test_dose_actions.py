from datetime import UTC, datetime, timedelta
from uuid import UUID, uuid4

from sqlalchemy import func, select

from app.doses.models import DoseLog, ScheduledDose


async def _register(client, email: str) -> dict[str, object]:
    response = await client.post(
        "/api/v1/auth/register",
        json={"name": "Caregiver", "email": email, "password": "password123"},
    )
    assert response.status_code == 201
    return response.json()


def _headers(auth: dict[str, object]) -> dict[str, str]:
    return {"Authorization": f"Bearer {auth['access_token']}"}


async def _seed_dose(client, db_session, email: str) -> tuple[dict[str, object], ScheduledDose]:
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
                {"period": "night", "local_time": "20:00", "quantity": "1", "unit": "tablet"}
            ],
        },
    )
    assert schedule.status_code == 201
    dose = await db_session.scalar(
        select(ScheduledDose)
        .where(ScheduledDose.schedule_id == UUID(schedule.json()["id"]))
        .order_by(ScheduledDose.scheduled_at)
        .limit(1)
    )
    assert dose is not None
    return auth, dose


async def test_taken_is_idempotent_and_conflicting_final_action_is_409(client, db_session):
    auth, dose = await _seed_dose(client, db_session, "dose-taken@example.com")
    action_id = uuid4()
    occurred_at = datetime.now(UTC)
    payload = {"client_action_id": str(action_id), "occurred_at": occurred_at.isoformat()}

    first = await client.post(
        f"/api/v1/doses/{dose.id}/taken", headers=_headers(auth), json=payload
    )
    assert first.status_code == 200
    assert first.json()["status"] == "taken"

    duplicate = await client.post(
        f"/api/v1/doses/{dose.id}/taken", headers=_headers(auth), json=payload
    )
    assert duplicate.status_code == 200
    count = await db_session.scalar(
        select(func.count()).select_from(DoseLog).where(DoseLog.client_action_id == action_id)
    )
    assert count == 1

    conflict = await client.post(
        f"/api/v1/doses/{dose.id}/skip",
        headers=_headers(auth),
        json={"client_action_id": str(uuid4()), "occurred_at": occurred_at.isoformat()},
    )
    assert conflict.status_code == 409
    assert conflict.json()["error"]["code"] == "DOSE_ALREADY_FINALIZED"


async def test_snooze_requires_pending_and_remains_pending(client, db_session):
    auth, dose = await _seed_dose(client, db_session, "dose-snooze@example.com")
    dose.status = "pending"
    await db_session.flush()
    now = datetime.now(UTC)
    until = now + timedelta(minutes=15)
    response = await client.post(
        f"/api/v1/doses/{dose.id}/snooze",
        headers=_headers(auth),
        json={
            "client_action_id": str(uuid4()),
            "occurred_at": now.isoformat(),
            "snoozed_until": until.isoformat(),
        },
    )
    assert response.status_code == 200
    assert response.json()["status"] == "pending"
    assert response.json()["snoozed_until"] is not None


async def test_idempotency_key_cannot_be_reused_for_other_operation(client, db_session):
    auth, dose_a = await _seed_dose(client, db_session, "dose-key-a@example.com")
    dose_b = await db_session.scalar(
        select(ScheduledDose)
        .where(
            ScheduledDose.schedule_id == dose_a.schedule_id,
            ScheduledDose.id != dose_a.id,
        )
        .order_by(ScheduledDose.scheduled_at)
        .limit(1)
    )
    assert dose_b is not None
    key = uuid4()
    now = datetime.now(UTC)
    first = await client.post(
        f"/api/v1/doses/{dose_a.id}/taken",
        headers=_headers(auth),
        json={"client_action_id": str(key), "occurred_at": now.isoformat()},
    )
    assert first.status_code == 200

    different_action = await client.post(
        f"/api/v1/doses/{dose_a.id}/skip",
        headers=_headers(auth),
        json={"client_action_id": str(key), "occurred_at": now.isoformat()},
    )
    assert different_action.status_code == 409
    assert different_action.json()["error"]["code"] == "IDEMPOTENCY_KEY_REUSED"

    other_dose = await client.post(
        f"/api/v1/doses/{dose_b.id}/taken",
        headers=_headers(auth),
        json={"client_action_id": str(key), "occurred_at": now.isoformat()},
    )
    assert other_dose.status_code == 409
    assert other_dose.json()["error"]["code"] == "IDEMPOTENCY_KEY_REUSED"


async def test_future_action_time_rejected_and_cross_family_dose_hidden(client, db_session):
    outsider = await _register(client, "dose-outsider@example.com")
    owner, dose = await _seed_dose(client, db_session, "dose-owner@example.com")
    hidden = await client.post(
        f"/api/v1/doses/{dose.id}/taken",
        headers=_headers(outsider),
        json={
            "client_action_id": str(uuid4()),
            "occurred_at": datetime.now(UTC).isoformat(),
        },
    )
    assert hidden.status_code == 404

    future = await client.post(
        f"/api/v1/doses/{dose.id}/taken",
        headers=_headers(owner),
        json={
            "client_action_id": str(uuid4()),
            "occurred_at": (datetime.now(UTC) + timedelta(minutes=10)).isoformat(),
        },
    )
    assert future.status_code == 422


async def test_correction_preserves_prior_missed_log_and_sets_effective_time(client, db_session):
    auth, dose = await _seed_dose(client, db_session, "dose-correct@example.com")
    missed_at = datetime.now(UTC) - timedelta(hours=1)
    dose.status = "missed"
    dose.missed_at = missed_at
    db_session.add(
        DoseLog(
            scheduled_dose_id=dose.id,
            action="missed",
            occurred_at=missed_at,
            recorded_at=missed_at,
            event_metadata={},
        )
    )
    await db_session.flush()
    correction_time = datetime.now(UTC)
    effective = correction_time - timedelta(minutes=20)
    response = await client.post(
        f"/api/v1/doses/{dose.id}/correct",
        headers=_headers(auth),
        json={
            "client_action_id": str(uuid4()),
            "occurred_at": correction_time.isoformat(),
            "effective_at": effective.isoformat(),
            "new_status": "taken",
            "reason": "Recorded late by caregiver",
        },
    )
    assert response.status_code == 200
    assert response.json()["status"] == "taken"
    await db_session.refresh(dose)
    assert dose.missed_at == missed_at
    assert dose.taken_at == effective
    actions = list(
        (
            await db_session.scalars(
                select(DoseLog.action)
                .where(DoseLog.scheduled_dose_id == dose.id)
                .order_by(DoseLog.recorded_at, DoseLog.id)
            )
        ).all()
    )
    assert actions == ["missed", "corrected"]

    invalid = await client.post(
        f"/api/v1/doses/{dose.id}/correct",
        headers=_headers(auth),
        json={
            "client_action_id": str(uuid4()),
            "occurred_at": correction_time.isoformat(),
            "effective_at": (correction_time + timedelta(minutes=1)).isoformat(),
            "new_status": "skipped",
        },
    )
    assert invalid.status_code == 422
