"""schedules doses today

Revision ID: 0003
Revises: 0002
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "0003"
down_revision: str | None = "0002"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def _timestamps() -> list[sa.Column]:
    return [
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
    ]


def upgrade() -> None:
    op.create_table(
        "medication_schedules",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("member_medication_id", sa.Uuid(), nullable=False),
        sa.Column("raw_instruction", sa.Text(), nullable=True),
        sa.Column("meal_relation", sa.String(length=32), nullable=True),
        sa.Column("timezone", sa.String(length=64), nullable=False),
        sa.Column("start_date", sa.Date(), nullable=False),
        sa.Column("end_date", sa.Date(), nullable=True),
        sa.Column("generation_not_before_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("status", sa.String(length=20), nullable=False),
        sa.Column("created_by_user_id", sa.Uuid(), nullable=False),
        *_timestamps(),
        sa.CheckConstraint(
            "status IN ('active','paused','ended')",
            name="ck_medication_schedule_status",
        ),
        sa.CheckConstraint(
            "end_date IS NULL OR end_date >= start_date",
            name="ck_medication_schedule_dates",
        ),
        sa.ForeignKeyConstraint(["created_by_user_id"], ["users.id"]),
        sa.ForeignKeyConstraint(
            ["member_medication_id"],
            ["member_medications.id"],
        ),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "uq_current_schedule_per_medication",
        "medication_schedules",
        ["member_medication_id"],
        unique=True,
        postgresql_where=sa.text("status IN ('active', 'paused')"),
    )

    op.create_table(
        "schedule_times",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("schedule_id", sa.Uuid(), nullable=False),
        sa.Column("period", sa.String(length=20), nullable=False),
        sa.Column("local_time", sa.Time(), nullable=False),
        sa.Column("quantity", sa.Numeric(precision=10, scale=3), nullable=False),
        sa.Column("unit", sa.String(length=40), nullable=False),
        sa.Column("sort_order", sa.Integer(), nullable=False),
        *_timestamps(),
        sa.CheckConstraint(
            "period IN ('morning','afternoon','evening','night','custom')",
            name="ck_schedule_time_period",
        ),
        sa.CheckConstraint("quantity > 0", name="ck_schedule_time_quantity"),
        sa.CheckConstraint(
            "length(trim(unit)) > 0",
            name="ck_schedule_time_unit",
        ),
        sa.ForeignKeyConstraint(
            ["schedule_id"],
            ["medication_schedules.id"],
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "schedule_id",
            "local_time",
            name="uq_schedule_time_clock",
        ),
    )

    op.create_table(
        "scheduled_doses",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("schedule_id", sa.Uuid(), nullable=False),
        sa.Column("schedule_time_id", sa.Uuid(), nullable=True),
        sa.Column("family_member_id", sa.Uuid(), nullable=False),
        sa.Column("member_medication_id", sa.Uuid(), nullable=False),
        sa.Column("scheduled_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("scheduled_local_date", sa.Date(), nullable=False),
        sa.Column("scheduled_local_time", sa.Time(), nullable=False),
        sa.Column("timezone", sa.String(length=64), nullable=False),
        sa.Column("quantity", sa.Numeric(precision=10, scale=3), nullable=False),
        sa.Column("unit", sa.String(length=40), nullable=False),
        sa.Column("meal_relation", sa.String(length=32), nullable=True),
        sa.Column("status", sa.String(length=20), nullable=False),
        sa.Column("snoozed_until", sa.DateTime(timezone=True), nullable=True),
        sa.Column("taken_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("skipped_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("missed_at", sa.DateTime(timezone=True), nullable=True),
        *_timestamps(),
        sa.CheckConstraint(
            "status IN ('upcoming','pending','taken','skipped','missed')",
            name="ck_scheduled_dose_status",
        ),
        sa.CheckConstraint("quantity > 0", name="ck_scheduled_dose_quantity"),
        sa.CheckConstraint(
            "length(trim(unit)) > 0",
            name="ck_scheduled_dose_unit",
        ),
        sa.ForeignKeyConstraint(["family_member_id"], ["family_members.id"]),
        sa.ForeignKeyConstraint(
            ["member_medication_id"],
            ["member_medications.id"],
        ),
        sa.ForeignKeyConstraint(["schedule_id"], ["medication_schedules.id"]),
        sa.ForeignKeyConstraint(
            ["schedule_time_id"],
            ["schedule_times.id"],
            ondelete="SET NULL",
        ),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "schedule_id",
            "scheduled_local_date",
            "scheduled_local_time",
            name="uq_scheduled_dose_occurrence",
        ),
    )

    op.create_table(
        "dose_logs",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("scheduled_dose_id", sa.Uuid(), nullable=False),
        sa.Column("action", sa.String(length=32), nullable=False),
        sa.Column("performed_by_user_id", sa.Uuid(), nullable=True),
        sa.Column("client_action_id", sa.Uuid(), nullable=True),
        sa.Column("occurred_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column(
            "recorded_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.Column("metadata", postgresql.JSONB(astext_type=sa.Text()), nullable=False),
        sa.CheckConstraint(
            "action IN ('became_pending','snoozed','marked_taken','skipped','missed','corrected')",
            name="ck_dose_log_action",
        ),
        sa.ForeignKeyConstraint(
            ["performed_by_user_id"],
            ["users.id"],
        ),
        sa.ForeignKeyConstraint(
            ["scheduled_dose_id"],
            ["scheduled_doses.id"],
        ),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("client_action_id"),
    )

    op.create_table(
        "notification_preferences",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("family_member_id", sa.Uuid(), nullable=False),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column(
            "enabled",
            sa.Boolean(),
            nullable=False,
            server_default=sa.text("false"),
        ),
        sa.Column(
            "default_snooze_minutes",
            sa.Integer(),
            nullable=False,
            server_default=sa.text("15"),
        ),
        sa.Column(
            "caregiver_escalation_enabled",
            sa.Boolean(),
            nullable=False,
            server_default=sa.text("false"),
        ),
        *_timestamps(),
        sa.CheckConstraint(
            "default_snooze_minutes > 0",
            name="ck_notification_preference_snooze_positive",
        ),
        sa.ForeignKeyConstraint(["family_member_id"], ["family_members.id"]),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"]),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "user_id",
            "family_member_id",
            name="uq_notification_preference_user_member",
        ),
    )


def downgrade() -> None:
    op.drop_table("notification_preferences")
    op.drop_table("dose_logs")
    op.drop_table("scheduled_doses")
    op.drop_table("schedule_times")
    op.drop_index(
        "uq_current_schedule_per_medication",
        table_name="medication_schedules",
    )
    op.drop_table("medication_schedules")
