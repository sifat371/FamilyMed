async def register_user(client, email: str) -> dict[str, str]:
    response = await client.post(
        "/api/v1/auth/register",
        json={"name": "Caregiver", "email": email, "password": "password123"},
    )
    assert response.status_code == 201
    return response.json()


def auth_headers(auth: dict[str, str]) -> dict[str, str]:
    return {"Authorization": f"Bearer {auth['access_token']}"}


async def create_member(client, auth: dict[str, str], name: str = "Amma") -> dict[str, object]:
    response = await client.post(
        "/api/v1/family-members",
        headers=auth_headers(auth),
        json={
            "name": name,
            "relationship": "mother" if name == "Amma" else "father",
            "preferred_language": "bn",
            "timezone": "Asia/Dhaka",
        },
    )
    assert response.status_code == 201
    return response.json()


async def create_metformin(client, auth: dict[str, str], member_id: str):
    return await client.post(
        f"/api/v1/family-members/{member_id}/medications",
        headers=auth_headers(auth),
        json={
            "display_name": "Metformin",
            "strength": "500 mg",
            "dosage_form": "tablet",
            "start_date": "2026-09-23",
        },
    )


async def test_create_list_get_and_update_manual_medication(client):
    auth = await register_user(client, "med-owner@example.com")
    amma = await create_member(client, auth)

    created = await create_metformin(client, auth, str(amma["id"]))
    assert created.status_code == 201
    medication = created.json()
    assert medication["display_name"] == "Metformin"
    assert medication["strength"] == "500 mg"
    assert medication["dosage_form"] == "tablet"
    assert medication["status"] == "draft"
    assert medication["medicine_master_id"] is None

    listed = await client.get(
        f"/api/v1/family-members/{amma['id']}/medications",
        headers=auth_headers(auth),
    )
    assert listed.status_code == 200
    assert [item["id"] for item in listed.json()] == [medication["id"]]

    fetched = await client.get(
        f"/api/v1/member-medications/{medication['id']}",
        headers=auth_headers(auth),
    )
    assert fetched.status_code == 200
    assert fetched.json()["display_name"] == "Metformin"

    updated = await client.patch(
        f"/api/v1/member-medications/{medication['id']}",
        headers=auth_headers(auth),
        json={
            "display_name": "Metformin XR",
            "strength": "750 mg",
            "dosage_form": "tablet",
            "start_date": "2026-09-24",
            "end_date": "2026-10-24",
        },
    )
    assert updated.status_code == 200
    assert updated.json()["display_name"] == "Metformin XR"
    assert updated.json()["strength"] == "750 mg"
    assert updated.json()["status"] == "draft"
    assert updated.json()["end_date"] == "2026-10-24"


async def test_manual_medication_validation_and_blank_optional_values(client):
    auth = await register_user(client, "med-validation@example.com")
    amma = await create_member(client, auth)
    url = f"/api/v1/family-members/{amma['id']}/medications"

    blank_name = await client.post(
        url,
        headers=auth_headers(auth),
        json={"display_name": "   ", "start_date": "2026-09-23"},
    )
    bad_dates = await client.post(
        url,
        headers=auth_headers(auth),
        json={
            "display_name": "Metformin",
            "start_date": "2026-09-23",
            "end_date": "2026-09-22",
        },
    )
    for response in (blank_name, bad_dates):
        assert response.status_code == 422
        assert response.json()["error"]["code"] == "VALIDATION_ERROR"

    blank_optional = await client.post(
        url,
        headers=auth_headers(auth),
        json={
            "display_name": "Metformin",
            "strength": "   ",
            "dosage_form": " ",
            "start_date": "2026-09-23",
        },
    )
    assert blank_optional.status_code == 201
    assert blank_optional.json()["strength"] is None
    assert blank_optional.json()["dosage_form"] is None


async def test_medication_list_is_scoped_to_requested_member_and_status_cannot_patch(client):
    auth = await register_user(client, "med-scope@example.com")
    amma = await create_member(client, auth, "Amma")
    abbu = await create_member(client, auth, "Abbu")
    amma_med = await create_metformin(client, auth, str(amma["id"]))
    assert amma_med.status_code == 201
    abbu_med = await client.post(
        f"/api/v1/family-members/{abbu['id']}/medications",
        headers=auth_headers(auth),
        json={"display_name": "Amlodipine", "strength": "5 mg", "start_date": "2026-09-23"},
    )
    assert abbu_med.status_code == 201

    amma_list = await client.get(
        f"/api/v1/family-members/{amma['id']}/medications",
        headers=auth_headers(auth),
    )
    assert [item["display_name"] for item in amma_list.json()] == ["Metformin"]

    status_patch = await client.patch(
        f"/api/v1/member-medications/{amma_med.json()['id']}",
        headers=auth_headers(auth),
        json={"status": "active"},
    )
    assert status_patch.status_code == 422

    fetched = await client.get(
        f"/api/v1/member-medications/{amma_med.json()['id']}",
        headers=auth_headers(auth),
    )
    assert fetched.json()["status"] == "draft"


async def test_cross_family_medication_paths_return_scoped_404(client):
    owner_a = await register_user(client, "med-a@example.com")
    owner_b = await register_user(client, "med-b@example.com")
    member_b = await create_member(client, owner_b)
    created_b = await create_metformin(client, owner_b, str(member_b["id"]))
    assert created_b.status_code == 201
    medication_id = created_b.json()["id"]

    list_probe = await client.get(
        f"/api/v1/family-members/{member_b['id']}/medications",
        headers=auth_headers(owner_a),
    )
    create_probe = await create_metformin(client, owner_a, str(member_b["id"]))
    for response in (list_probe, create_probe):
        assert response.status_code == 404
        assert response.json()["error"]["code"] == "FAMILY_MEMBER_NOT_FOUND"

    read_probe = await client.get(
        f"/api/v1/member-medications/{medication_id}",
        headers=auth_headers(owner_a),
    )
    update_probe = await client.patch(
        f"/api/v1/member-medications/{medication_id}",
        headers=auth_headers(owner_a),
        json={"display_name": "Probe"},
    )
    for response in (read_probe, update_probe):
        assert response.status_code == 404
        assert response.json()["error"]["code"] == "MEDICATION_NOT_FOUND"
