from datetime import UTC, date, datetime, time
from uuid import uuid4

import pytest
from sqlalchemy import delete, func, select

from app.doses.models import DoseLog, ScheduledDose
from app.medications.models import MemberMedication
from app.schedules.generation import generate_schedule_window, local_occurrence_to_utc
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


async def _member(client, auth: dict[str, object]) -> dict[str, object]:
    response = await client.post(
        "/api/v1/family-members",
        headers=_headers(auth),
        json={
            "name": "Amma",
            "relationship": "mother",
            "preferred_language": "bn",
            "timezone": "Asia/Dhaka",
        },
    )
    assert response.status_code == 201
    return response.json()


async def _medication(
    client,
    auth: dict[str, object],
    member_id: str,
) -> dict[str, object]:
    response = await client.post(
        f"/api/v1/family-members/{member_id}/medications",
        headers=_headers(auth),
        json={
            "display_name": "Metformin",
            "strength": "500 mg",
            "dosage_form": "tablet",
            "start_date": "2026-09-23",
        },
    )
    assert response.status_code == 201
    return response.json()


def _schedule_payload() -> dict[str, object]:
    return {
        "raw_instruction": "1+0+1 PC",
        "meal_relation": "after_food",
        "timezone": "Asia/Dhaka",
        "start_date": "2026-09-23",
        "end_date": None,
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
    }


async def _setup_medication(client, email: str):
    auth = await _register(client, email)
    member = await _member(client, auth)
    medication = await _medication(client, auth, str(member["id"]))
    return auth, member, medication


def test_local_occurrence_to_utc_converts_dhaka_wall_clock():
    assert local_occurrence_to_utc(
        date(2026, 9, 24),
        time(8, 0),
        "Asia/Dhaka",
    ) == datetime(2026, 9, 24, 2, 0, tzinfo=UTC)


async def test_create_schedule_activates_medication_and_exposes_current_schedule(
    client,
    db_session,
):
    auth, _, medication = await _setup_medication(client, "schedule-owner@example.com")
    response = await client.post(
        f"/api/v1/member-medications/{medication['id']}/schedules",
        headers=_headers(auth),
        json=_schedule_payload(),
    )
    assert response.status_code == 201
    body = response.json()
    assert body["status"] == "active"
    assert body["timezone"] == "Asia/Dhaka"
    assert [item["local_time"] for item in body["times"]] == ["08:00:00", "20:00:00"]

    persisted_medication = await db_session.get(MemberMedication, medication["id"])
    assert persisted_medication is not None
    assert persisted_medication.status == "active"

    current = await client.get(
        f"/api/v1/member-medications/{medication['id']}/schedule",
        headers=_headers(auth),
    )
    assert current.status_code == 200
    assert current.json()["id"] == body["id"]


async def test_generation_is_idempotent_and_respects_30_day_window(client, db_session):
    auth, _, medication = await _setup_medication(client, "schedule-window@example.com")
    created = await client.post(
        f"/api/v1/member-medications/{medication['id']}/schedules",
        headers=_headers(auth),
        json=_schedule_payload(),
    )
    assert created.status_code == 201
    schedule_id = created.json()["id"]

    await db_session.execute(delete(ScheduledDose).where(ScheduledDose.schedule_id == schedule_id))
    await db_session.flush()
    controlled_now = datetime(2026, 9, 23, 3, 0, tzinfo=UTC)
    first = await generate_schedule_window(db_session, schedule_id, controlled_now)
    second = await generate_schedule_window(db_session, schedule_id, controlled_now)
    await db_session.flush()

    count = await db_session.scalar(
        select(func.count()).select_from(ScheduledDose).where(ScheduledDose.schedule_id == schedule_id)
    )
    assert len(first) == 60
    assert second == []
    assert count == 60


@pytest.mark.parametrize(
    ("mutate", "expected_code"),
    [
        (lambda payload: payload.update({"timezone": "Mars/Olympus"}), "INVALID_TIMEZONE"),
        (lambda payload: payload.update({"times": []}), "VALIDATION_ERROR"),
        (
            lambda payload: payload.update(
                {
                    "times": [
                        {
                            "period": "custom",
                            "local_time": f"{hour:02d}:00",
                            "quantity": "1",
                            "unit": "tablet",
                        }
                        for hour in range(9)
                    ]
                }
            ),
            "VALIDATION_ERROR",
        ),
        (
            lambda payload: payload.update(
                {
                    "times": [
                        {
                            "period": "morning",
                            "local_time": "08:00",
                            "quantity": "1",
                            "unit": "tablet",
                        },
                        {
                            "period": "custom",
                            "local_time": "08:00",
                            "quantity": "1",
                            "unit": "tablet",
                        },
                    ]
                }
            ),
            "VALIDATION_ERROR",
        ),
        (
            lambda payload: payload["times"][0].update({"local_time": "08:00:30"}),
            "VALIDATION_ERROR",
        ),
    ],
)
async def test_schedule_validation(client, mutate, expected_code):
    auth, _, medication = await _setup_medication(client, f"validation-{uuid4()}@example.com")
    payload = _schedule_payload()
    mutate(payload)
    response = await client.post(
        f"/api/v1/member-medications/{medication['id']}/schedules",
        headers=_headers(auth),
        json=payload,
    )
    assert response.status_code == 422
    assert response.json()["error"]["code"] == expected_code


async def test_second_current_schedule_is_rejected(client):
    auth, _, medication = await _setup_medication(client, "schedule-duplicate@example.com")
    url = f"/api/v1/member-medications/{medication['id']}/schedules"
    first = await client.post(url, headers=_headers(auth), json=_schedule_payload())
    second = await client.post(url, headers=_headers(auth), json=_schedule_payload())
    assert first.status_code == 201
    assert second.status_code == 409
    assert second.json()["error"]["code"] == "ACTIVE_SCHEDULE_EXISTS"


async def test_cross_family_schedule_paths_return_404(client):
    owner_a = await _register(client, "schedule-a@example.com")
    owner_b, _, medication_b = await _setup_medication(client, "schedule-b@example.com")
    created = await client.post(
        f"/api/v1/member-medications/{medication_b['id']}/schedules",
        headers=_headers(owner_b),
        json=_schedule_payload(),
    )
    assert created.status_code == 201

    create_probe = await client.post(
        f"/api/v1/member-medications/{medication_b['id']}/schedules",
        headers=_headers(owner_a),
        json=_schedule_payload(),
    )
    read_probe = await client.get(
        f"/api/v1/member-medications/{medication_b['id']}/schedule",
        headers=_headers(owner_a),
    )
    for response in (create_probe, read_probe):
        assert response.status_code == 404
        assert response.json()["error"]["code"] == "MEDICATION_NOT_FOUND"


async def test_schedule_edit_preserves_event_bearing_future_dose(client, db_session):
    auth, _, medication = await _setup_medication(client, "schedule-edit@example.com")
    created = await client.post(
        f"/api/v1/member-medications/{medication['id']}/schedules",
        headers=_headers(auth),
        json=_schedule_payload(),
    )
    schedule_id = created.json()["id"]
    schedule = await db_session.get(MedicationSchedule, schedule_id)
    assert schedule is not None

    future_dose = await db_session.scalar(
        select(ScheduledDose)
        .where(ScheduledDose.schedule_id == schedule.id)
        .order_by(ScheduledDose.scheduled_at.desc())
        .limit(1)
    )
    assert future_dose is not None
    future_dose.status = "taken"
    db_session.add(
        DoseLog(
            scheduled_dose_id=future_dose.id,
            action="marked_taken",
            performed_by_user_id=medication["created_by_user_id"],
            client_action_id=uuid4(),
            occurred_at=future_dose.scheduled_at,
            recorded_at=future_dose.scheduled_at,
            event_metadata={},
        )
    )
    await db_session.flush()
    preserved_id = future_dose.id

    payload = _schedule_payload()
    payload["times"] = [
        {
            "period": "morning",
            "local_time": "09:00",
            "quantity": "1",
            "unit": "tablet",
        }
    ]
    updated = await client.patch(
        f"/api/v1/schedules/{schedule_id}",
        headers=_headers(auth),
        json=payload,
    )
    assert updated.status_code == 200
    assert await db_session.get(ScheduledDose, preserved_id) is not None
    log_count = await db_session.scalar(
        select(func.count()).select_from(DoseLog).where(DoseLog.scheduled_dose_id == preserved_id)
    )
    assert log_count == 1


async def test_editing_paused_schedule_does_not_generate_future_doses(client, db_session):
    auth, _, medication = await _setup_medication(client, "schedule-paused@example.com")
    created = await client.post(
        f"/api/v1/member-medications/{medication['id']}/schedules",
        headers=_headers(auth),
        json=_schedule_payload(),
    )
    schedule_id = created.json()["id"]
    schedule = await db_session.get(MedicationSchedule, schedule_id)
    persisted_medication = await db_session.get(MemberMedication, medication["id"])
    assert schedule is not None and persisted_medication is not None
    schedule.status = "paused"
    persisted_medication.status = "paused"
    await db_session.execute(delete(ScheduledDose).where(ScheduledDose.schedule_id == schedule.id))
    await db_session.flush()

    payload = _schedule_payload()
    payload["times"] = [
        {
            "period": "night",
            "local_time": "21:00",
            "quantity": "1",
            "unit": "tablet",
        }
    ]
    response = await client.patch(
        f"/api/v1/schedules/{schedule.id}",
        headers=_headers(auth),
        json=payload,
    )
    assert response.status_code == 200
    count = await db_session.scalar(
        select(func.count()).select_from(ScheduledDose).where(ScheduledDose.schedule_id == schedule.id)
    )
    assert count == 0
