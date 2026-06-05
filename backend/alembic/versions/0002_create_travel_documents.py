"""create travel documents

Revision ID: 0002_create_travel_documents
Revises: 0001_create_monolith_tables
Create Date: 2026-06-06 00:00:00.000000
"""

from alembic import op
import sqlalchemy as sa

revision = "0002_create_travel_documents"
down_revision = "0001_create_monolith_tables"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "travel_documents",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("user_id", sa.String(length=36), nullable=False),
        sa.Column("trip_id", sa.String(length=36), nullable=True),
        sa.Column("document_scope", sa.String(length=40), nullable=False),
        sa.Column("document_type", sa.String(length=80), nullable=False),
        sa.Column("file_name", sa.String(length=255), nullable=False),
        sa.Column("content_type", sa.String(length=120), nullable=False),
        sa.Column("size_bytes", sa.Integer(), nullable=False),
        sa.Column("checksum_sha256", sa.String(length=64), nullable=True),
        sa.Column("s3_bucket", sa.String(length=255), nullable=False),
        sa.Column("s3_key", sa.Text(), nullable=False),
        sa.Column("kms_key_id", sa.String(length=255), nullable=False),
        sa.Column("status", sa.String(length=40), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("CURRENT_TIMESTAMP"), nullable=False),
        sa.Column("uploaded_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
        sa.ForeignKeyConstraint(["trip_id"], ["trips.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("s3_key"),
    )
    op.create_index("ix_travel_documents_created_at", "travel_documents", ["created_at"], unique=False)
    op.create_index("ix_travel_documents_document_scope", "travel_documents", ["document_scope"], unique=False)
    op.create_index("ix_travel_documents_status", "travel_documents", ["status"], unique=False)
    op.create_index("ix_travel_documents_trip_id", "travel_documents", ["trip_id"], unique=False)
    op.create_index("ix_travel_documents_user_id", "travel_documents", ["user_id"], unique=False)


def downgrade() -> None:
    op.drop_index("ix_travel_documents_user_id", table_name="travel_documents")
    op.drop_index("ix_travel_documents_trip_id", table_name="travel_documents")
    op.drop_index("ix_travel_documents_status", table_name="travel_documents")
    op.drop_index("ix_travel_documents_document_scope", table_name="travel_documents")
    op.drop_index("ix_travel_documents_created_at", table_name="travel_documents")
    op.drop_table("travel_documents")
