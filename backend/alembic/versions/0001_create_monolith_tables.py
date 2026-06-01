"""create monolith tables

Revision ID: 0001_create_monolith_tables
Revises:
Create Date: 2026-06-01 00:00:00.000000
"""

from alembic import op
import sqlalchemy as sa

revision = "0001_create_monolith_tables"
down_revision = None
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "users",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("name", sa.String(length=120), nullable=False),
        sa.Column("email", sa.String(length=255), nullable=False),
        sa.Column("password_hash", sa.String(length=255), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("CURRENT_TIMESTAMP"), nullable=False),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_users_email", "users", ["email"], unique=True)

    op.create_table(
        "preferences",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("user_id", sa.String(length=36), nullable=False),
        sa.Column("travel_style", sa.String(length=80), nullable=False),
        sa.Column("preferred_budget", sa.Numeric(precision=12, scale=2), nullable=False),
        sa.Column("interests", sa.JSON(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("CURRENT_TIMESTAMP"), nullable=False),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_preferences_user_id", "preferences", ["user_id"], unique=True)

    op.create_table(
        "trips",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("user_id", sa.String(length=36), nullable=False),
        sa.Column("destination", sa.String(length=160), nullable=False),
        sa.Column("budget", sa.Numeric(precision=12, scale=2), nullable=False),
        sa.Column("days", sa.Integer(), nullable=False),
        sa.Column("interests", sa.JSON(), nullable=False),
        sa.Column("status", sa.String(length=40), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("CURRENT_TIMESTAMP"), nullable=False),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_trips_user_id", "trips", ["user_id"], unique=False)
    op.create_index("ix_trips_created_at", "trips", ["created_at"], unique=False)

    op.create_table(
        "expenses",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("trip_id", sa.String(length=36), nullable=False),
        sa.Column("category", sa.String(length=80), nullable=False),
        sa.Column("amount", sa.Numeric(precision=12, scale=2), nullable=False),
        sa.Column("description", sa.String(length=500), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("CURRENT_TIMESTAMP"), nullable=False),
        sa.ForeignKeyConstraint(["trip_id"], ["trips.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_expenses_trip_id", "expenses", ["trip_id"], unique=False)


def downgrade() -> None:
    op.drop_index("ix_expenses_trip_id", table_name="expenses")
    op.drop_table("expenses")
    op.drop_index("ix_trips_created_at", table_name="trips")
    op.drop_index("ix_trips_user_id", table_name="trips")
    op.drop_table("trips")
    op.drop_index("ix_preferences_user_id", table_name="preferences")
    op.drop_table("preferences")
    op.drop_index("ix_users_email", table_name="users")
    op.drop_table("users")
