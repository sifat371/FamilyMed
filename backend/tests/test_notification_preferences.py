async def _register(client, email: str) -> dict[str, object]:
    response = await client.post(
        "/api/v1/auth/register",
        json={"name": "Caregiver", "email": email, "password": "password123"},
    )
    assert response.status_code == 201
    return response.json()


def _headers(auth: dict[str, object]) -> dict[str, str]:
    return {"Authorization": f"Bearer {auth['access_token']}"}


async def _member(client, auth: dict[str, object], name: str = "Amma") -> dict[str, object]:
    response = await client.post(
        "/api/v1/family-members",
        headers=_headers(auth),
        json={
            "name": name,
            "relationship": "mother",
            "preferred_language": "bn",
            "timezone": "Asia/Dhaka",
        },
    )
    assert response.status_code == 201
    return response.json()


async def test_notification_preference_defaults_and_patch(client):
    auth = await _register(client, "notify@example.com")
    member = await _member(client, auth)
    path = f"/api/v1/family-members/{member['id']}/notification-preference"

    defaults = await client.get(path, headers=_headers(auth))
    assert defaults.status_code == 200
    assert defaults.json()["enabled"] is False
    assert defaults.json()["default_snooze_minutes"] == 15
    assert defaults.json()["caregiver_escalation_enabled"] is False

    updated = await client.patch(
        path,
        headers=_headers(auth),
        json={"enabled": True, "default_snooze_minutes": 20},
    )
    assert updated.status_code == 200
    assert updated.json()["enabled"] is True
    assert updated.json()["default_snooze_minutes"] == 20

    persisted = await client.get(path, headers=_headers(auth))
    assert persisted.json()["enabled"] is True
    assert persisted.json()["default_snooze_minutes"] == 20


async def test_notification_preference_rejects_escalation_and_cross_family_access(client):
    owner = await _register(client, "notify-owner@example.com")
    outsider = await _register(client, "notify-outsider@example.com")
    member = await _member(client, owner)
    path = f"/api/v1/family-members/{member['id']}/notification-preference"

    invalid = await client.patch(
        path,
        headers=_headers(owner),
        json={"caregiver_escalation_enabled": True},
    )
    assert invalid.status_code == 422

    hidden = await client.get(path, headers=_headers(outsider))
    assert hidden.status_code == 404
