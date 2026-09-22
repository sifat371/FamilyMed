"""auth family medications

Revision ID: 0002
Revises: 0001_bootstrap
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0002"
down_revision: str | None = "0001_bootstrap"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "users",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("name", sa.String(length=120), nullable=False),
        sa.Column("email", sa.String(length=255), nullable=False),
        sa.Column("password_hash", sa.Text(), nullable=False),
        sa.Column("preferred_language", sa.String(length=5), nullable=False),
        sa.Column("timezone", sa.String(length=64), nullable=False),
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
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_users_email", "users", ["email"], unique=True)

    op.create_table(
        "families",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("name", sa.String(length=160), nullable=False),
        sa.Column("created_by_user_id", sa.Uuid(), nullable=False),
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
        sa.ForeignKeyConstraint(["created_by_user_id"], ["users.id"]),
        sa.PrimaryKeyConstraint("id"),
    )

    op.create_table(
        "family_memberships",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("family_id", sa.Uuid(), nullable=False),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("role", sa.String(length=20), nullable=False),
        sa.Column("status", sa.String(length=20), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.ForeignKeyConstraint(["family_id"], ["families.id"]),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"]),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("family_id", "user_id", name="uq_family_membership"),
    )
    op.create_index(
        "ix_family_memberships_user_status",
        "family_memberships",
        ["user_id", "status"],
        unique=False,
    )

    op.create_table(
        "family_members",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("family_id", sa.Uuid(), nullable=False),
        sa.Column("name", sa.String(length=120), nullable=False),
        sa.Column("relationship", sa.String(length=40), nullable=False),
        sa.Column("date_of_birth", sa.Date(), nullable=True),
        sa.Column("preferred_language", sa.String(length=5), nullable=False),
        sa.Column("linked_user_id", sa.Uuid(), nullable=True),
        sa.Column("profile_image_key", sa.Text(), nullable=True),
        sa.Column("timezone", sa.String(length=64), nullable=False),
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
        sa.Column("archived_at", sa.DateTime(timezone=True), nullable=True),
        sa.ForeignKeyConstraint(["family_id"], ["families.id"]),
        sa.ForeignKeyConstraint(["linked_user_id"], ["users.id"]),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_family_members_family_id", "family_members", ["family_id"], unique=False
    )

    op.create_table(
        "medicine_master",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("brand_name", sa.String(length=160), nullable=True),
        sa.Column("generic_name", sa.String(length=160), nullable=False),
        sa.Column("strength", sa.String(length=80), nullable=True),
        sa.Column("dosage_form", sa.String(length=80), nullable=True),
        sa.Column("manufacturer", sa.String(length=160), nullable=True),
        sa.Column("country", sa.String(length=2), nullable=False),
        sa.Column("source", sa.String(length=120), nullable=False),
        sa.Column("source_reference", sa.Text(), nullable=True),
        sa.Column("normalized_search_text", sa.Text(), nullable=False),
        sa.Column("active", sa.Boolean(), nullable=False),
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
        sa.PrimaryKeyConstraint("id"),
    )

    op.create_table(
        "member_medications",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("family_member_id", sa.Uuid(), nullable=False),
        sa.Column("medicine_master_id", sa.Uuid(), nullable=True),
        sa.Column("prescription_id", sa.Uuid(), nullable=True),
        sa.Column("extraction_id", sa.Uuid(), nullable=True),
        sa.Column("display_name", sa.String(length=180), nullable=False),
        sa.Column("strength", sa.String(length=80), nullable=True),
        sa.Column("dosage_form", sa.String(length=80), nullable=True),
        sa.Column("status", sa.String(length=20), nullable=False),
        sa.Column("start_date", sa.Date(), nullable=False),
        sa.Column("end_date", sa.Date(), nullable=True),
        sa.Column("created_by_user_id", sa.Uuid(), nullable=False),
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
        sa.ForeignKeyConstraint(["created_by_user_id"], ["users.id"]),
        sa.ForeignKeyConstraint(["family_member_id"], ["family_members.id"]),
        sa.ForeignKeyConstraint(["medicine_master_id"], ["medicine_master.id"]),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_member_medications_member_status",
        "member_medications",
        ["family_member_id", "status"],
        unique=False,
    )


def downgrade() -> None:
    op.drop_index("ix_member_medications_member_status", table_name="member_medications")
    op.drop_table("member_medications")
    op.drop_table("medicine_master")
    op.drop_index("ix_family_members_family_id", table_name="family_members")
    op.drop_table("family_members")
    op.drop_index("ix_family_memberships_user_status", table_name="family_memberships")
    op.drop_table("family_memberships")
    op.drop_table("families")
    op.drop_index("ix_users_email", table_name="users")
    op.drop_table("users")
