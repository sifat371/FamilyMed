from uuid import UUID, uuid4

from sqlalchemy import String, Text, Uuid
from sqlalchemy.orm import Mapped, mapped_column

from app.db import Base, TimestampMixin


class User(TimestampMixin, Base):
    __tablename__ = "users"

    id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
    name: Mapped[str] = mapped_column(String(120), nullable=False)
    email: Mapped[str] = mapped_column(String(255), nullable=False, unique=True, index=True)
    # Social-only accounts do not have a password. Never generate a known fallback.
    password_hash: Mapped[str | None] = mapped_column(Text, nullable=True)
    google_subject: Mapped[str | None] = mapped_column(String(255), unique=True, nullable=True)
    preferred_language: Mapped[str] = mapped_column(String(5), nullable=False, default="en")
    timezone: Mapped[str] = mapped_column(String(64), nullable=False, default="Asia/Dhaka")

    @property
    def has_password(self) -> bool:
        return self.password_hash is not None
