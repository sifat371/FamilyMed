from datetime import date, datetime, time
from decimal import Decimal
from uuid import UUID, uuid4

from sqlalchemy import (
    CheckConstraint,
    DateTime,
    ForeignKey,
    Numeric,
    String,
    Time,
    UniqueConstraint,
    Uuid,
    func,
)
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column

from app.db import Base, TimestampMixin


class ScheduledDose(TimestampMixin, Base):
    __tablename__ = "scheduled_doses"
    __table_args__ = (
        CheckConstraint(
            "status IN ('upcoming','pending','taken','skipped','missed')",
            name="ck_scheduled_dose_status",
        ),
        CheckConstraint("quantity > 0", name="ck_scheduled_dose_quantity"),
        CheckConstraint(
            "length(trim(unit)) > 0",
            name="ck_scheduled_dose_unit",
        ),
        UniqueConstraint(
            "schedule_id",
            "scheduled_local_date",
            "scheduled_local_time",
            name="uq_scheduled_dose_occurrence",
        ),
    )

    id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
    schedule_id: Mapped[UUID] = mapped_column(
        Uuid,
        ForeignKey("medication_schedules.id"),
        nullable=False,
    )
    schedule_time_id: Mapped[UUID | None] = mapped_column(
        Uuid,
        ForeignKey("schedule_times.id", ondelete="SET NULL"),
        nullable=True,
    )
    family_member_id: Mapped[UUID] = mapped_column(
        Uuid,
        ForeignKey("family_members.id"),
        nullable=False,
    )
    member_medication_id: Mapped[UUID] = mapped_column(
        Uuid,
        ForeignKey("member_medications.id"),
        nullable=False,
    )
    scheduled_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False
    )
    scheduled_local_date: Mapped[date] = mapped_column(nullable=False)
    scheduled_local_time: Mapped[time] = mapped_column(Time, nullable=False)
    timezone: Mapped[str] = mapped_column(String(64), nullable=False)
    quantity: Mapped[Decimal] = mapped_column(Numeric(10, 3), nullable=False)
    unit: Mapped[str] = mapped_column(String(40), nullable=False)
    meal_relation: Mapped[str | None] = mapped_column(String(32), nullable=True)
    status: Mapped[str] = mapped_column(
        String(20), nullable=False, default="upcoming"
    )
    snoozed_until: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    taken_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    skipped_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    missed_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )


class DoseLog(Base):
    __tablename__ = "dose_logs"
    __table_args__ = (
        CheckConstraint(
            "action IN ('became_pending','snoozed','marked_taken','skipped','missed','corrected')",
            name="ck_dose_log_action",
        ),
    )

    id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
    scheduled_dose_id: Mapped[UUID] = mapped_column(
        Uuid,
        ForeignKey("scheduled_doses.id"),
        nullable=False,
    )
    action: Mapped[str] = mapped_column(String(32), nullable=False)
    performed_by_user_id: Mapped[UUID | None] = mapped_column(
        Uuid,
        ForeignKey("users.id"),
        nullable=True,
    )
    client_action_id: Mapped[UUID | None] = mapped_column(
        Uuid,
        nullable=True,
        unique=True,
    )
    occurred_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False
    )
    recorded_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
    )
    event_metadata: Mapped[dict[str, object]] = mapped_column(
        "metadata",
        JSONB,
        nullable=False,
        default=dict,
    )
