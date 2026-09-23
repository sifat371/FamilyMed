from app.doses.projections import build_member_history


async def _register(client, email: str) -> dict[str, object]:
    response = await client.post(
        "/api/v1/auth/register",
        json={"name": "Caregiver", "email": email, "password": "test-pass-123"},
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


async def test_empty_history_has_null_marked_adherence(client):
    auth = await _register(client, "history@example.com")
    member = await _member(client, auth)
    response = await client.get(
        f"/api/v1/family-members/{member['id']}/history",
        headers=_headers(auth),
    )
    assert response.status_code == 200
    assert response.json()["marked_adherence_percentage"] is None
    assert response.json()["days"] == []


async def test_history_range_and_cross_family_scope(client):
    owner = await _register(client, "history-owner@example.com")
    outsider = await _register(client, "history-outsider@example.com")
    member = await _member(client, owner)

    too_wide = await client.get(
        f"/api/v1/family-members/{member['id']}/history?from=2026-01-01&to=2026-05-01",
        headers=_headers(owner),
    )
    assert too_wide.status_code == 422

    hidden = await client.get(
        f"/api/v1/family-members/{member['id']}/history",
        headers=_headers(outsider),
    )
    assert hidden.status_code == 404


def test_history_projection_function_is_exposed():
    assert build_member_history is not None
