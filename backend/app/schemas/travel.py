from datetime import datetime
from decimal import Decimal
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field


class TripCreate(BaseModel):
    destination: str = Field(min_length=2, max_length=160)
    budget: Decimal = Field(ge=0)
    days: int = Field(ge=1, le=365)
    interests: list[str] = Field(default_factory=list)
    status: str = Field(default="planned", min_length=2, max_length=40)


class TripUpdate(BaseModel):
    destination: str | None = Field(default=None, min_length=2, max_length=160)
    budget: Decimal | None = Field(default=None, ge=0)
    days: int | None = Field(default=None, ge=1, le=365)
    interests: list[str] | None = None
    status: str | None = Field(default=None, min_length=2, max_length=40)


class TripRead(BaseModel):
    id: str
    user_id: str
    destination: str
    budget: Decimal
    days: int
    interests: list[str]
    status: str
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)


class ExpenseCreate(BaseModel):
    trip_id: str
    category: str = Field(min_length=2, max_length=80)
    amount: Decimal = Field(gt=0)
    description: str = Field(default="", max_length=500)


class ExpenseRead(BaseModel):
    id: str
    trip_id: str
    category: str
    amount: Decimal
    description: str
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)


class BudgetSummary(BaseModel):
    total_budget: Decimal
    total_spent: Decimal
    remaining_budget: Decimal


class DocumentPresignUploadRequest(BaseModel):
    file_name: str = Field(min_length=1, max_length=255)
    content_type: str = Field(min_length=3, max_length=120)
    size_bytes: int = Field(gt=0)
    document_type: str = Field(default="general", min_length=2, max_length=80)
    checksum_sha256: str | None = Field(default=None, min_length=64, max_length=64)


class DocumentUploadCompleteRequest(BaseModel):
    checksum_sha256: str | None = Field(default=None, min_length=64, max_length=64)


class TravelDocumentRead(BaseModel):
    id: str
    user_id: str
    trip_id: str | None
    document_scope: Literal["trip", "chat"]
    document_type: str
    file_name: str
    content_type: str
    size_bytes: int
    checksum_sha256: str | None
    s3_bucket: str
    s3_key: str
    kms_key_id: str
    status: str
    created_at: datetime
    uploaded_at: datetime | None
    deleted_at: datetime | None

    model_config = ConfigDict(from_attributes=True)


class DocumentPresignUploadResponse(BaseModel):
    document: TravelDocumentRead
    upload_url: str
    method: Literal["PUT"]
    headers: dict[str, str]
    expires_at: datetime
    max_size_bytes: int


class DocumentDownloadUrlResponse(BaseModel):
    download_url: str
    expires_at: datetime
