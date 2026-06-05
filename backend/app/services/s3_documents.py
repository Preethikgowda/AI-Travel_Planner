from datetime import datetime, timedelta, timezone
from pathlib import PurePath
import re
from typing import Any

from app.core.config import settings
from app.models.travel import TravelDocument


class StorageConfigurationError(RuntimeError):
    pass


class StorageValidationError(ValueError):
    pass


class StorageObjectMissingError(RuntimeError):
    pass


class S3DocumentStorage:
    def __init__(self) -> None:
        self._client = None

    @property
    def bucket_name(self) -> str:
        return settings.s3_document_bucket

    @property
    def kms_key_id(self) -> str:
        return settings.s3_document_kms_key_id

    @property
    def max_upload_bytes(self) -> int:
        return settings.s3_max_upload_bytes

    def require_configured(self) -> None:
        if not self.bucket_name or not self.kms_key_id:
            raise StorageConfigurationError("S3 document storage is not configured")

    def validate_upload(self, *, file_name: str, content_type: str, size_bytes: int) -> str:
        self.require_configured()
        if size_bytes > self.max_upload_bytes:
            raise StorageValidationError(f"File exceeds the {self.max_upload_bytes} byte upload limit")

        normalized_content_type = content_type.lower().strip()
        if normalized_content_type not in settings.s3_allowed_content_type_list:
            raise StorageValidationError("File type is not allowed")

        safe_name = self.safe_file_name(file_name)
        if not safe_name:
            raise StorageValidationError("File name is invalid")
        return safe_name

    def build_object_key(self, *, user_id: str, document_id: str, document_scope: str, file_name: str, trip_id: str | None = None) -> str:
        safe_name = self.safe_file_name(file_name)
        if document_scope == "trip" and trip_id:
            return f"users/{user_id}/trips/{trip_id}/documents/{document_id}/{safe_name}"
        return f"users/{user_id}/chat-attachments/{document_id}/{safe_name}"

    def presign_upload(self, document: TravelDocument) -> tuple[str, dict[str, str], datetime]:
        self.require_configured()
        expires_at = self._expires_at()
        headers = self._upload_headers(document)
        params: dict[str, Any] = {
            "Bucket": document.s3_bucket,
            "Key": document.s3_key,
            "ContentType": document.content_type,
            "ServerSideEncryption": "aws:kms",
            "SSEKMSKeyId": document.kms_key_id,
            "Metadata": self._metadata(document),
        }
        url = self.client.generate_presigned_url(
            "put_object",
            Params=params,
            ExpiresIn=settings.s3_presigned_url_expires_seconds,
            HttpMethod="PUT",
        )
        return url, headers, expires_at

    def presign_download(self, document: TravelDocument) -> tuple[str, datetime]:
        self.require_configured()
        expires_at = self._expires_at()
        url = self.client.generate_presigned_url(
            "get_object",
            Params={
                "Bucket": document.s3_bucket,
                "Key": document.s3_key,
                "ResponseContentDisposition": f'attachment; filename="{document.file_name}"',
            },
            ExpiresIn=settings.s3_presigned_url_expires_seconds,
            HttpMethod="GET",
        )
        return url, expires_at

    def verify_uploaded_object(self, document: TravelDocument) -> None:
        self.require_configured()
        try:
            response = self.client.head_object(Bucket=document.s3_bucket, Key=document.s3_key)
        except Exception as exc:
            error_code = getattr(exc, "response", {}).get("Error", {}).get("Code")
            if error_code in {"404", "NoSuchKey", "NotFound"}:
                raise StorageObjectMissingError("Uploaded file was not found in S3") from exc
            raise StorageConfigurationError("Unable to verify uploaded file in S3") from exc

        actual_size = int(response.get("ContentLength") or 0)
        if actual_size != document.size_bytes:
            raise StorageValidationError("Uploaded file size does not match the requested upload")

        actual_encryption = response.get("ServerSideEncryption")
        actual_kms_key = response.get("SSEKMSKeyId")
        if actual_encryption != "aws:kms" or not actual_kms_key:
            raise StorageValidationError("Uploaded file is not encrypted with SSE-KMS")

    def delete_object(self, document: TravelDocument) -> None:
        self.require_configured()
        self.client.delete_object(Bucket=document.s3_bucket, Key=document.s3_key)

    @property
    def client(self):
        if self._client is None:
            try:
                import boto3
            except ImportError as exc:
                raise StorageConfigurationError("boto3 is required for S3 document storage") from exc
            self._client = boto3.client("s3", region_name=settings.aws_region)
        return self._client

    @staticmethod
    def safe_file_name(file_name: str) -> str:
        base_name = PurePath(file_name).name.strip()
        return re.sub(r"[^A-Za-z0-9._-]+", "_", base_name)[:160]

    def _expires_at(self) -> datetime:
        return datetime.now(timezone.utc) + timedelta(seconds=settings.s3_presigned_url_expires_seconds)

    def _upload_headers(self, document: TravelDocument) -> dict[str, str]:
        headers = {
            "Content-Type": document.content_type,
            "x-amz-server-side-encryption": "aws:kms",
            "x-amz-server-side-encryption-aws-kms-key-id": document.kms_key_id,
            "x-amz-meta-user-id": document.user_id,
            "x-amz-meta-document-id": document.id,
            "x-amz-meta-document-scope": document.document_scope,
        }
        if document.trip_id:
            headers["x-amz-meta-trip-id"] = document.trip_id
        return headers

    @staticmethod
    def _metadata(document: TravelDocument) -> dict[str, str]:
        metadata = {
            "user-id": document.user_id,
            "document-id": document.id,
            "document-scope": document.document_scope,
        }
        if document.trip_id:
            metadata["trip-id"] = document.trip_id
        return metadata
