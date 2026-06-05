from decimal import Decimal

from datetime import datetime, timezone

from sqlalchemy import desc, func, select
from sqlalchemy.orm import Session

from app.models.travel import Expense, TravelDocument, Trip
from app.schemas.travel import TripCreate, TripUpdate


class TravelRepository:
    def __init__(self, db: Session):
        self.db = db

    def create_trip(self, user_id: str, payload: TripCreate) -> Trip:
        trip = Trip(
            user_id=user_id,
            destination=payload.destination,
            budget=payload.budget,
            days=payload.days,
            interests=self._normalize_interests(payload.interests),
            status=payload.status,
        )
        self.db.add(trip)
        self.db.commit()
        self.db.refresh(trip)
        return trip

    def list_trips(self, user_id: str) -> list[Trip]:
        return list(self.db.scalars(select(Trip).where(Trip.user_id == user_id).order_by(desc(Trip.created_at))))

    def get_trip(self, trip_id: str, user_id: str) -> Trip | None:
        return self.db.scalar(select(Trip).where(Trip.id == trip_id, Trip.user_id == user_id))

    def update_trip(self, trip: Trip, payload: TripUpdate) -> Trip:
        data = payload.model_dump(exclude_unset=True)
        if "interests" in data and data["interests"] is not None:
            data["interests"] = self._normalize_interests(data["interests"])
        for key, value in data.items():
            setattr(trip, key, value)
        self.db.commit()
        self.db.refresh(trip)
        return trip

    def delete_trip(self, trip: Trip) -> None:
        self.db.delete(trip)
        self.db.commit()

    def create_expense(self, trip: Trip, category: str, amount: Decimal, description: str) -> Expense:
        expense = Expense(
            trip_id=trip.id,
            category=category,
            amount=amount,
            description=description,
        )
        self.db.add(expense)
        self.db.commit()
        self.db.refresh(expense)
        return expense

    def list_expenses(self, trip_id: str) -> list[Expense]:
        return list(self.db.scalars(select(Expense).where(Expense.trip_id == trip_id).order_by(desc(Expense.created_at))))

    def total_spent_for_user(self, user_id: str) -> Decimal:
        total = self.db.scalar(
            select(func.coalesce(func.sum(Expense.amount), 0)).join(Trip).where(Trip.user_id == user_id)
        )
        return Decimal(total or 0)

    def create_document(
        self,
        *,
        document_id: str,
        user_id: str,
        trip_id: str | None,
        document_scope: str,
        document_type: str,
        file_name: str,
        content_type: str,
        size_bytes: int,
        checksum_sha256: str | None,
        s3_bucket: str,
        s3_key: str,
        kms_key_id: str,
    ) -> TravelDocument:
        document = TravelDocument(
            id=document_id,
            user_id=user_id,
            trip_id=trip_id,
            document_scope=document_scope,
            document_type=document_type,
            file_name=file_name,
            content_type=content_type,
            size_bytes=size_bytes,
            checksum_sha256=checksum_sha256,
            s3_bucket=s3_bucket,
            s3_key=s3_key,
            kms_key_id=kms_key_id,
            status="pending",
        )
        self.db.add(document)
        self.db.commit()
        self.db.refresh(document)
        return document

    def list_documents(self, user_id: str, document_scope: str, trip_id: str | None = None) -> list[TravelDocument]:
        query = select(TravelDocument).where(
            TravelDocument.user_id == user_id,
            TravelDocument.document_scope == document_scope,
            TravelDocument.status == "available",
        )
        if trip_id is not None:
            query = query.where(TravelDocument.trip_id == trip_id)
        return list(self.db.scalars(query.order_by(desc(TravelDocument.created_at))))

    def get_document(
        self,
        document_id: str,
        user_id: str,
        document_scope: str | None = None,
        trip_id: str | None = None,
        include_deleted: bool = False,
    ) -> TravelDocument | None:
        query = select(TravelDocument).where(TravelDocument.id == document_id, TravelDocument.user_id == user_id)
        if document_scope is not None:
            query = query.where(TravelDocument.document_scope == document_scope)
        if trip_id is not None:
            query = query.where(TravelDocument.trip_id == trip_id)
        if not include_deleted:
            query = query.where(TravelDocument.status != "deleted")
        return self.db.scalar(query)

    def list_documents_by_ids(self, user_id: str, document_ids: list[str], document_scope: str) -> list[TravelDocument]:
        if not document_ids:
            return []
        return list(
            self.db.scalars(
                select(TravelDocument).where(
                    TravelDocument.user_id == user_id,
                    TravelDocument.document_scope == document_scope,
                    TravelDocument.id.in_(document_ids),
                    TravelDocument.status == "available",
                )
            )
        )

    def mark_document_available(self, document: TravelDocument, checksum_sha256: str | None = None) -> TravelDocument:
        document.status = "available"
        document.uploaded_at = datetime.now(timezone.utc)
        if checksum_sha256:
            document.checksum_sha256 = checksum_sha256
        self.db.commit()
        self.db.refresh(document)
        return document

    def soft_delete_document(self, document: TravelDocument) -> TravelDocument:
        document.status = "deleted"
        document.deleted_at = datetime.now(timezone.utc)
        self.db.commit()
        self.db.refresh(document)
        return document

    def hard_delete_document(self, document: TravelDocument) -> None:
        self.db.delete(document)
        self.db.commit()

    @staticmethod
    def _normalize_interests(interests: list[str]) -> list[str]:
        return sorted({interest.strip().lower() for interest in interests if interest.strip()})
