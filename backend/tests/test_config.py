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


def test_managed_postgres_url_normalizes_for_asyncpg():
    settings = Settings(
        env="production",
        database_url="postgresql://user:pass@private-host:5432/familymed",
        jwt_secret="unique-production-secret-over-32-chars-long",
    )
    assert settings.database_url == (
        "postgresql+asyncpg://user:pass@private-host:5432/familymed"
    )


def test_legacy_postgres_scheme_normalizes_for_asyncpg():
    settings = Settings(
        env="staging",
        database_url="postgres://user:pass@private-host:5432/familymed",
        jwt_secret="unique-staging-secret-over-32-chars-long",
    )
    assert settings.database_url.startswith("postgresql+asyncpg://")


def test_production_rejects_weak_nondefault_secret():
    with pytest.raises(ValidationError, match="32\\+ character"):
        Settings(
            env="production",
            database_url="postgresql://user:pass@private-host:5432/familymed",
            jwt_secret="weak-secret",
        )
