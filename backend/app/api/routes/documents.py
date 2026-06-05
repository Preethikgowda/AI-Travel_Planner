from typing import Annotated
from uuid import uuid4

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.api.dependencies import get_current_user
from app.core.security import CurrentUser
from app.db.session import get_db
from app.repositories.travel_repository import TravelRepository
from app.schemas.travel import (
    DocumentDownloadUrlResponse,
    DocumentPresignUploadRequest,
    DocumentPresignUploadResponse,
    DocumentUploadCompleteRequest,
    TravelDocumentRead,
)
from app.services.s3_documents import (
    S3DocumentStorage,
    StorageConfigurationError,
    StorageObjectMissingError,
    StorageValidationError,
)

router = APIRouter(tags=["documents"])
storage = S3DocumentStorage()


@router.post(
    "/trips/{trip_id}/documents/presign-upload",
    response_model=DocumentPresignUploadResponse,
    status_code=status.HTTP_201_CREATED,
)
def presign_trip_document_upload(
    trip_id: str,
    payload: DocumentPresignUploadRequest,
    current_user: Annotated[CurrentUser, Depends(get_current_user)],
    db: Annotated[Session, Depends(get_db)],
):
    repository = TravelRepository(db)
    trip = repository.get_trip(trip_id, current_user.id)
    if trip is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Trip not found")
    return _create_presigned_upload(repository, payload, current_user.id, "trip", trip_id)


@router.post("/trips/{trip_id}/documents/{document_id}/complete", response_model=TravelDocumentRead)
def complete_trip_document_upload(
    trip_id: str,
    document_id: str,
    payload: DocumentUploadCompleteRequest,
    current_user: Annotated[CurrentUser, Depends(get_current_user)],
    db: Annotated[Session, Depends(get_db)],
):
    repository = TravelRepository(db)
    trip = repository.get_trip(trip_id, current_user.id)
    if trip is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Trip not found")
    document = repository.get_document(document_id, current_user.id, document_scope="trip", trip_id=trip_id)
    if document is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Document not found")
    return _complete_upload(repository, document, payload)


@router.get("/trips/{trip_id}/documents", response_model=list[TravelDocumentRead])
def list_trip_documents(
    trip_id: str,
    current_user: Annotated[CurrentUser, Depends(get_current_user)],
    db: Annotated[Session, Depends(get_db)],
):
    repository = TravelRepository(db)
    trip = repository.get_trip(trip_id, current_user.id)
    if trip is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Trip not found")
    return repository.list_documents(current_user.id, "trip", trip_id=trip_id)


@router.get("/trips/{trip_id}/documents/{document_id}/download-url", response_model=DocumentDownloadUrlResponse)
def trip_document_download_url(
    trip_id: str,
    document_id: str,
    current_user: Annotated[CurrentUser, Depends(get_current_user)],
    db: Annotated[Session, Depends(get_db)],
):
    repository = TravelRepository(db)
    trip = repository.get_trip(trip_id, current_user.id)
    if trip is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Trip not found")
    document = repository.get_document(document_id, current_user.id, document_scope="trip", trip_id=trip_id)
    if document is None or document.status != "available":
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Document not found")
    return _download_url(document)


@router.delete("/trips/{trip_id}/documents/{document_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_trip_document(
    trip_id: str,
    document_id: str,
    current_user: Annotated[CurrentUser, Depends(get_current_user)],
    db: Annotated[Session, Depends(get_db)],
):
    repository = TravelRepository(db)
    trip = repository.get_trip(trip_id, current_user.id)
    if trip is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Trip not found")
    document = repository.get_document(document_id, current_user.id, document_scope="trip", trip_id=trip_id)
    if document is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Document not found")
    _delete_document(repository, document)
    return None


@router.post(
    "/documents/chat/presign-upload",
    response_model=DocumentPresignUploadResponse,
    status_code=status.HTTP_201_CREATED,
)
def presign_chat_attachment_upload(
    payload: DocumentPresignUploadRequest,
    current_user: Annotated[CurrentUser, Depends(get_current_user)],
    db: Annotated[Session, Depends(get_db)],
):
    repository = TravelRepository(db)
    return _create_presigned_upload(repository, payload, current_user.id, "chat", None)


@router.post("/documents/chat/{document_id}/complete", response_model=TravelDocumentRead)
def complete_chat_attachment_upload(
    document_id: str,
    payload: DocumentUploadCompleteRequest,
    current_user: Annotated[CurrentUser, Depends(get_current_user)],
    db: Annotated[Session, Depends(get_db)],
):
    repository = TravelRepository(db)
    document = repository.get_document(document_id, current_user.id, document_scope="chat")
    if document is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Document not found")
    return _complete_upload(repository, document, payload)


@router.get("/documents/chat", response_model=list[TravelDocumentRead])
def list_chat_attachments(
    current_user: Annotated[CurrentUser, Depends(get_current_user)],
    db: Annotated[Session, Depends(get_db)],
):
    return TravelRepository(db).list_documents(current_user.id, "chat")


@router.delete("/documents/chat/{document_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_chat_attachment(
    document_id: str,
    current_user: Annotated[CurrentUser, Depends(get_current_user)],
    db: Annotated[Session, Depends(get_db)],
):
    repository = TravelRepository(db)
    document = repository.get_document(document_id, current_user.id, document_scope="chat")
    if document is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Document not found")
    _delete_document(repository, document)
    return None


def _create_presigned_upload(
    repository: TravelRepository,
    payload: DocumentPresignUploadRequest,
    user_id: str,
    document_scope: str,
    trip_id: str | None,
) -> DocumentPresignUploadResponse:
    try:
        safe_file_name = storage.validate_upload(
            file_name=payload.file_name,
            content_type=payload.content_type,
            size_bytes=payload.size_bytes,
        )
    except StorageConfigurationError as exc:
        raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail=str(exc)) from exc
    except StorageValidationError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc

    document_id = str(uuid4())
    s3_key = storage.build_object_key(
        user_id=user_id,
        document_id=document_id,
        document_scope=document_scope,
        file_name=safe_file_name,
        trip_id=trip_id,
    )

    document = repository.create_document(
        document_id=document_id,
        user_id=user_id,
        trip_id=trip_id,
        document_scope=document_scope,
        document_type=payload.document_type,
        file_name=safe_file_name,
        content_type=payload.content_type.lower().strip(),
        size_bytes=payload.size_bytes,
        checksum_sha256=payload.checksum_sha256,
        s3_bucket=storage.bucket_name,
        s3_key=s3_key,
        kms_key_id=storage.kms_key_id,
    )

    try:
        upload_url, headers, expires_at = storage.presign_upload(document)
    except StorageConfigurationError as exc:
        repository.hard_delete_document(document)
        raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail=str(exc)) from exc

    return DocumentPresignUploadResponse(
        document=document,
        upload_url=upload_url,
        method="PUT",
        headers=headers,
        expires_at=expires_at,
        max_size_bytes=storage.max_upload_bytes,
    )


def _complete_upload(
    repository: TravelRepository,
    document,
    payload: DocumentUploadCompleteRequest,
) -> TravelDocumentRead:
    if document.status == "available":
        return document
    try:
        storage.verify_uploaded_object(document)
    except StorageConfigurationError as exc:
        raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail=str(exc)) from exc
    except StorageObjectMissingError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc
    except StorageValidationError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc
    return repository.mark_document_available(document, payload.checksum_sha256)


def _download_url(document) -> DocumentDownloadUrlResponse:
    try:
        download_url, expires_at = storage.presign_download(document)
    except StorageConfigurationError as exc:
        raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail=str(exc)) from exc
    return DocumentDownloadUrlResponse(download_url=download_url, expires_at=expires_at)


def _delete_document(repository: TravelRepository, document) -> None:
    try:
        storage.delete_object(document)
    except StorageConfigurationError as exc:
        raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail=str(exc)) from exc
    repository.soft_delete_document(document)
