import pytest
from pydantic import ValidationError

from app.config import Settings

DEV_DB = "postgresql+asyncpg://familymed:familymed@localhost:5432/familymed"


def test_settings_accept_explicit_development_values():
    settings = Settings(
        env="development",
        database_url=DEV_DB,
        jwt_secret="secret",
        cors_origins="http://localhost:3000",
    )
    assert settings.env == "development"
    assert settings.cors_origin_list == ["http://localhost:3000"]


def test_production_rejects_development_secret():
    with pytest.raises(ValidationError):
        Settings(
            env="production",
            database_url="postgresql+asyncpg://u:p@db:5432/familymed",
            jwt_secret="change-me-in-local-env",
            cors_origins="https://familymed.example",
        )


def test_production_rejects_development_database_url():
    with pytest.raises(ValidationError):
        Settings(
            env="production",
            database_url=DEV_DB,
            jwt_secret="production-secret",
            cors_origins="https://familymed.example",
        )
