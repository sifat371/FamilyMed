from datetime import date, datetime, time
from decimal import Decimal
from uuid import UUID, uuid4

from sqlalchemy import (
    CheckConstraint,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    Numeric,
    String,
    Text,
    Time,
    UniqueConstraint,
    Uuid,
    text,
)
from sqlalchemy.orm import Mapped, mapped_column

from app.db import Base, TimestampMixin


class MedicationSchedule(TimestampMixin, Base):
    __tablename__ = "medication_schedules"
    __table_args__ = (
        CheckConstraint(
            "status IN ('active','paused','ended')",
            name="ck_medication_schedule_status",
        ),
        CheckConstraint(
            "end_date IS NULL OR end_date >= start_date",
            name="ck_medication_schedule_dates",
        ),
        Index(
            "uq_current_schedule_per_medication",
            "member_medication_id",
            unique=True,
            postgresql_where=text("status IN ('active', 'paused')"),
        ),
    )

    id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
    member_medication_id: Mapped[UUID] = mapped_column(
        Uuid,
        ForeignKey("member_medications.id"),
        nullable=False,
    )
    raw_instruction: Mapped[str | None] = mapped_column(Text, nullable=True)
    meal_relation: Mapped[str | None] = mapped_column(String(32), nullable=True)
    timezone: Mapped[str] = mapped_column(String(64), nullable=False)
    start_date: Mapped[date] = mapped_column(nullable=False)
    end_date: Mapped[date | None] = mapped_column(nullable=True)
    generation_not_before_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False
    )
    status: Mapped[str] = mapped_column(String(20), nullable=False)
    created_by_user_id: Mapped[UUID] = mapped_column(
        Uuid,
        ForeignKey("users.id"),
        nullable=False,
    )


class ScheduleTime(TimestampMixin, Base):
    __tablename__ = "schedule_times"
    __table_args__ = (
        CheckConstraint(
            "period IN ('morning','afternoon','evening','night','custom')",
            name="ck_schedule_time_period",
        ),
        CheckConstraint("quantity > 0", name="ck_schedule_time_quantity"),
        CheckConstraint(
            "length(trim(unit)) > 0",
            name="ck_schedule_time_unit",
        ),
        UniqueConstraint(
            "schedule_id",
            "local_time",
            name="uq_schedule_time_clock",
        ),
    )

    id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
    schedule_id: Mapped[UUID] = mapped_column(
        Uuid,
        ForeignKey("medication_schedules.id", ondelete="CASCADE"),
        nullable=False,
    )
    period: Mapped[str] = mapped_column(String(20), nullable=False)
    local_time: Mapped[time] = mapped_column(Time, nullable=False)
    quantity: Mapped[Decimal] = mapped_column(Numeric(10, 3), nullable=False)
    unit: Mapped[str] = mapped_column(String(40), nullable=False)
    sort_order: Mapped[int] = mapped_column(Integer, nullable=False)
