from datetime import date
from uuid import UUID, uuid4

from sqlalchemy import Boolean, ForeignKey, Index, String, Text, Uuid
from sqlalchemy.orm import Mapped, mapped_column

from app.db import Base, TimestampMixin


class MedicineMaster(TimestampMixin, Base):
    __tablename__ = "medicine_master"

    id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
    brand_name: Mapped[str | None] = mapped_column(String(160), nullable=True)
    generic_name: Mapped[str] = mapped_column(String(160), nullable=False)
    strength: Mapped[str | None] = mapped_column(String(80), nullable=True)
    dosage_form: Mapped[str | None] = mapped_column(String(80), nullable=True)
    manufacturer: Mapped[str | None] = mapped_column(String(160), nullable=True)
    country: Mapped[str] = mapped_column(String(2), nullable=False)
    source: Mapped[str] = mapped_column(String(120), nullable=False)
    source_reference: Mapped[str | None] = mapped_column(Text, nullable=True)
    normalized_search_text: Mapped[str] = mapped_column(Text, nullable=False)
    active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)


class MemberMedication(TimestampMixin, Base):
    __tablename__ = "member_medications"
    __table_args__ = (
        Index("ix_member_medications_member_status", "family_member_id", "status"),
    )

    id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
    family_member_id: Mapped[UUID] = mapped_column(
        Uuid, ForeignKey("family_members.id"), nullable=False
    )
    medicine_master_id: Mapped[UUID | None] = mapped_column(
        Uuid, ForeignKey("medicine_master.id"), nullable=True
    )
    prescription_id: Mapped[UUID | None] = mapped_column(Uuid, nullable=True)
    extraction_id: Mapped[UUID | None] = mapped_column(Uuid, nullable=True)
    display_name: Mapped[str] = mapped_column(String(180), nullable=False)
    strength: Mapped[str | None] = mapped_column(String(80), nullable=True)
    dosage_form: Mapped[str | None] = mapped_column(String(80), nullable=True)
    status: Mapped[str] = mapped_column(String(20), nullable=False, default="draft")
    start_date: Mapped[date] = mapped_column(nullable=False)
    end_date: Mapped[date | None] = mapped_column(nullable=True)
    created_by_user_id: Mapped[UUID] = mapped_column(
        Uuid, ForeignKey("users.id"), nullable=False
    )
