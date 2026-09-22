from unittest.mock import AsyncMock

from fastapi.testclient import TestClient

from app.api import health as health_module
from app.main import app

client = TestClient(app)


def test_health_reports_process_liveness():
    response = client.get("/api/v1/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok", "service": "familymed-api"}


def test_ready_returns_200_when_database_responds(monkeypatch):
    monkeypatch.setattr(health_module, "database_is_ready", AsyncMock(return_value=True))
    response = client.get("/api/v1/ready")
    assert response.status_code == 200
    assert response.json() == {"status": "ready"}


def test_ready_returns_503_when_database_is_unavailable(monkeypatch):
    monkeypatch.setattr(health_module, "database_is_ready", AsyncMock(return_value=False))
    response = client.get("/api/v1/ready")
    assert response.status_code == 503
    assert response.json()["detail"] == "database unavailable"
