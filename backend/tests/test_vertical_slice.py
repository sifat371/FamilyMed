from datetime import date


async def test_register_add_family_member_and_manual_medication_persist(client):
    registration = await client.post(
        "/api/v1/auth/register",
        json={
            "name": "Sifat",
            "email": "vertical@example.com",
            "password": "password123",
        },
    )
    assert registration.status_code == 201
    access_token = registration.json()["access_token"]
    headers = {"Authorization": f"Bearer {access_token}"}

    member_response = await client.post(
        "/api/v1/family-members",
        headers=headers,
        json={
            "name": "Amma",
            "relationship": "mother",
            "preferred_language": "bn",
            "timezone": "Asia/Dhaka",
        },
    )
    assert member_response.status_code == 201
    member = member_response.json()

    medication_response = await client.post(
        f"/api/v1/family-members/{member['id']}/medications",
        headers=headers,
        json={
            "display_name": "Metformin",
            "strength": "500 mg",
            "dosage_form": "tablet",
            "start_date": date.today().isoformat(),
            "end_date": None,
        },
    )
    assert medication_response.status_code == 201
    medication = medication_response.json()
    assert medication["family_member_id"] == member["id"]
    assert medication["display_name"] == "Metformin"
    assert medication["strength"] == "500 mg"
    assert medication["dosage_form"] == "tablet"
    assert medication["medicine_master_id"] is None
    assert medication["status"] == "draft"

    members = await client.get("/api/v1/family-members", headers=headers)
    assert members.status_code == 200
    assert [(item["name"], item["relationship"]) for item in members.json()] == [
        ("Amma", "mother")
    ]

    medications = await client.get(
        f"/api/v1/family-members/{member['id']}/medications",
        headers=headers,
    )
    assert medications.status_code == 200
    assert len(medications.json()) == 1
    persisted = medications.json()[0]
    assert persisted["id"] == medication["id"]
    assert persisted["display_name"] == "Metformin"
    assert persisted["status"] == "draft"
