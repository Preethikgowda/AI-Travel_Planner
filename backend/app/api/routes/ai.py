from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.api.dependencies import get_current_user
from app.core.security import CurrentUser
from app.db.session import get_db
from app.repositories.travel_repository import TravelRepository
from app.schemas.ai import (
    BudgetOptimizerRequest,
    BudgetOptimizerResponse,
    ChatRequest,
    ChatResponse,
    DestinationCompareRequest,
    DestinationCompareResponse,
    ItineraryRequest,
    ItineraryResponse,
    PackingListRequest,
    PackingListResponse,
)
from app.services.ai_service import TravelAIService

router = APIRouter(prefix="/ai", tags=["ai"])
ai_service = TravelAIService()


@router.post("/itinerary", response_model=ItineraryResponse)
async def itinerary(
    payload: ItineraryRequest,
    current_user: Annotated[CurrentUser, Depends(get_current_user)],
):
    return await ai_service.generate_itinerary(payload)


@router.post("/chat", response_model=ChatResponse)
async def chat(
    payload: ChatRequest,
    current_user: Annotated[CurrentUser, Depends(get_current_user)],
    db: Annotated[Session, Depends(get_db)],
):
    attachments = TravelRepository(db).list_documents_by_ids(current_user.id, payload.document_ids, "chat")
    if len(attachments) != len(set(payload.document_ids)):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="One or more chat attachments were not found")
    return await ai_service.chat(payload, attachments)


@router.post("/budget-optimizer", response_model=BudgetOptimizerResponse)
async def budget_optimizer(
    payload: BudgetOptimizerRequest,
    current_user: Annotated[CurrentUser, Depends(get_current_user)],
):
    return await ai_service.optimize_budget(payload)


@router.post("/compare", response_model=DestinationCompareResponse)
async def compare(
    payload: DestinationCompareRequest,
    current_user: Annotated[CurrentUser, Depends(get_current_user)],
):
    return await ai_service.compare_destinations(payload)


@router.post("/packing-list", response_model=PackingListResponse)
async def packing_list(
    payload: PackingListRequest,
    current_user: Annotated[CurrentUser, Depends(get_current_user)],
):
    return await ai_service.packing_list(payload)
