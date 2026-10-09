from collections.abc import AsyncIterator
from datetime import datetime

from sqlalchemy import DateTime, func, text
from sqlalchemy.engine import URL, make_url
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column
from sqlalchemy.pool import NullPool

from app.config import get_settings

settings = get_settings()


class Base(DeclarativeBase):
    pass


class TimestampMixin:
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now(), onupdate=func.now()
    )


engine_kwargs: dict[str, object] = {"pool_pre_ping": True}
if settings.env == "test":
    engine_kwargs["poolclass"] = NullPool

def asyncpg_tls_configuration(
    database_url: str, environment: str
) -> tuple[URL, dict[str, object]]:
    """Keep libpq TLS parameters for psycopg migrations, adapt for asyncpg."""
    url = make_url(database_url)
    ssl_mode = url.query.get("sslmode")
    if ssl_mode is not None and ssl_mode not in {
        "disable",
        "allow",
        "prefer",
        "require",
        "verify-ca",
        "verify-full",
    }:
        raise ValueError("Unsupported PostgreSQL sslmode")

    if environment in {"production", "staging"}:
        if ssl_mode in {"disable", "allow", "prefer"}:
            raise ValueError("Cloud PostgreSQL requires sslmode=require or stronger")
        ssl_mode = ssl_mode or "require"

    connect_args: dict[str, object] = {}
    if ssl_mode is not None:
        connect_args["ssl"] = ssl_mode if ssl_mode != "disable" else False

    # Neon libpq connection-string keys aren't asyncpg keyword arguments.
    url = url.difference_update_query(["sslmode", "channel_binding"])
    return url, connect_args


async_url, async_connect_args = asyncpg_tls_configuration(
    settings.database_url, settings.env
)
if async_connect_args:
    engine_kwargs["connect_args"] = async_connect_args

engine = create_async_engine(async_url, **engine_kwargs)
async_session_factory = async_sessionmaker(engine, expire_on_commit=False)


async def get_db_session() -> AsyncIterator[AsyncSession]:
    async with async_session_factory() as session:
        yield session


async def database_is_ready() -> bool:
    try:
        async with engine.connect() as connection:
            await connection.execute(text("SELECT 1"))
        return True
    except Exception:
        return False
