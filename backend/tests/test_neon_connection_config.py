import pytest

from app.db import asyncpg_tls_configuration


def test_neon_libpq_ssl_parameters_remain_private_and_are_mapped_to_asyncpg():
    raw_url = (
        "postgresql+asyncpg://owner:secret@ep-demo.aws.neon.tech/neondb"
        "?sslmode=require&channel_binding=require"
    )
    url, kwargs = asyncpg_tls_configuration(raw_url, "production")

    assert str(url).startswith("postgresql+asyncpg://")
    assert "sslmode" not in url.query
    assert "channel_binding" not in url.query
    assert kwargs == {"ssl": "require"}


def test_cloud_databases_require_tls_even_without_url_query():
    url, kwargs = asyncpg_tls_configuration(
        "postgresql+asyncpg://owner:secret@db-host/db", "production"
    )
    assert not url.query
    assert kwargs == {"ssl": "require"}


@pytest.mark.parametrize("sslmode", ["disable", "allow", "prefer"])
def test_cloud_database_rejects_tls_downgrade(sslmode):
    with pytest.raises(ValueError, match="requires sslmode=require"):
        asyncpg_tls_configuration(
            f"postgresql+asyncpg://u:p@db-host/db?sslmode={sslmode}", "staging"
        )


def test_local_development_preserves_non_tls_default():
    _, args = asyncpg_tls_configuration(
        "postgresql+asyncpg://owner:secret@localhost:5432/db", "development"
    )
    assert args == {}
