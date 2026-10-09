async def test_privacy_policy_is_public_and_describes_collected_care_data(client):
    response = await client.get("/privacy")
    assert response.status_code == 200
    assert "text/html" in response.headers["content-type"]
    assert "Privacy Policy" in response.text
    assert "medication" in response.text.lower()
    assert "deletion" in response.text.lower()


async def test_account_deletion_help_is_public_without_sign_in(client):
    response = await client.get("/account-deletion")
    assert response.status_code == 200
    assert "Delete account" in response.text
    assert "without reinstalling" in response.text
    assert "Never send your password" in response.text
