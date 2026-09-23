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
