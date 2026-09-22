from functools import lru_cache
from typing import Literal

from pydantic import model_validator
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

    @property
    def cors_origin_list(self) -> list[str]:
        return [origin.strip() for origin in self.cors_origins.split(",") if origin.strip()]

    @model_validator(mode="after")
    def reject_development_values_outside_dev(self) -> "Settings":
        if self.env in {"staging", "production"}:
            if self.jwt_secret == DEV_JWT_SECRET:
                raise ValueError("FAMILYMED_JWT_SECRET must be explicitly configured")
            if self.database_url == DEV_DATABASE_URL:
                raise ValueError("FAMILYMED_DATABASE_URL must be explicitly configured")
        return self


@lru_cache
def get_settings() -> Settings:
    return Settings()
