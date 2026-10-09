from collections.abc import AsyncIterator
from datetime import datetime

from sqlalchemy import DateTime, func, text
from sqlalchemy.engine import make_url
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

# Neon connection strings include libpq-specific query keys such as
# sslmode=require and channel_binding=require. asyncpg expects TLS via its
# 'ssl' connect argument instead. Preserve the original URL in Settings for
# psycopg/Alembic migrations, which understand the libpq query parameters.
async_url = make_url(settings.database_url)
ssl_mode = async_url.query.get("sslmode")
if ssl_mode is not None and ssl_mode not in {
    "disable",
    "allow",
    "prefer",
    "require",
    "verify-ca",
    "verify-full",
}:
    raise ValueError("Unsupported PostgreSQL sslmode")
if settings.env in {"production", "staging"}:
    # Never allow an unencrypted connection to cloud PostgreSQL.
    if ssl_mode in {"disable", "allow", "prefer"}:
        raise ValueError("Cloud PostgreSQL requires sslmode=require or stronger")
    ssl_mode = ssl_mode or "require"
if ssl_mode is not None:
    engine_kwargs["connect_args"] = {
        "ssl": ssl_mode if ssl_mode != "disable" else False
    }
async_url = async_url.difference_update_query(["sslmode", "channel_binding"])

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
