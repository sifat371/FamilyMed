from functools import lru_cache
from typing import Literal

from pydantic import EmailStr, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

DEV_DATABASE_URL = "postgresql+asyncpg://familymed:familymed@localhost:5432/familymed"
DEV_JWT_SECRET = "change-me-in-local-env"


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file="../.env",
        env_prefix="FAMILYMED_",
        extra="ignore",
    )

    env: Literal["development", "test", "staging", "production"] = "development"
    database_url: str = DEV_DATABASE_URL
    jwt_secret: str = DEV_JWT_SECRET
    jwt_algorithm: str = "HS256"
    access_token_minutes: int = 15
    refresh_token_days: int = 30
    cors_origins: str = "http://localhost:3000"
    support_email: EmailStr | None = None

    @property
    def cors_origin_list(self) -> list[str]:
        return [origin.strip() for origin in self.cors_origins.split(",") if origin.strip()]

    @model_validator(mode="after")
    def reject_development_values_outside_dev(self) -> "Settings":
        # Managed Postgres providers (including Render) expose the standard
        # postgresql:// connection string. Runtime SQLAlchemy requires asyncpg.
        if self.database_url.startswith("postgres://"):
            self.database_url = "postgresql+asyncpg://" + self.database_url[len("postgres://") :]
        elif self.database_url.startswith("postgresql://"):
            self.database_url = (
                "postgresql+asyncpg://" + self.database_url[len("postgresql://") :]
            )
        if self.env in {"staging", "production"}:
            if len(self.jwt_secret) < 32 or self.jwt_secret == DEV_JWT_SECRET:
                raise ValueError("FAMILYMED_JWT_SECRET must be a unique 32+ character secret")
            if self.database_url == DEV_DATABASE_URL:
                raise ValueError("FAMILYMED_DATABASE_URL must be explicitly configured")
            if not self.database_url.startswith("postgresql+asyncpg://"):
                raise ValueError("FAMILYMED_DATABASE_URL must be a PostgreSQL URL")
        if self.env == "production" and self.support_email is None:
            raise ValueError("FAMILYMED_SUPPORT_EMAIL is required for public support and deletion")
        return self


@lru_cache
def get_settings() -> Settings:
    return Settings()
