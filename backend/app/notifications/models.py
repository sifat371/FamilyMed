from uuid import UUID, uuid4

from sqlalchemy import Boolean, CheckConstraint, ForeignKey, Integer, UniqueConstraint, Uuid
from sqlalchemy.orm import Mapped, mapped_column

from app.db import Base, TimestampMixin


class NotificationPreference(TimestampMixin, Base):
    __tablename__ = "notification_preferences"
    __table_args__ = (
        CheckConstraint(
            "default_snooze_minutes > 0",
            name="ck_notification_preference_snooze_positive",
        ),
        UniqueConstraint(
            "user_id",
            "family_member_id",
            name="uq_notification_preference_user_member",
        ),
    )

    id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
    family_member_id: Mapped[UUID] = mapped_column(
        Uuid,
        ForeignKey("family_members.id"),
        nullable=False,
    )
    user_id: Mapped[UUID] = mapped_column(
        Uuid,
        ForeignKey("users.id"),
        nullable=False,
    )
    enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    default_snooze_minutes: Mapped[int] = mapped_column(
        Integer,
        nullable=False,
        default=15,
    )
    caregiver_escalation_enabled: Mapped[bool] = mapped_column(
        Boolean,
        nullable=False,
        default=False,
    )
