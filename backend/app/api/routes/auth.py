from typing import Annotated

import logging

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.core.security import create_access_token, hash_password, verify_password
from app.db.session import get_db
from app.repositories.user_repository import UserRepository
from app.schemas.user import AuthResponse, LoginRequest, UserCreate
from app.services.sns_service import SNSService

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/auth", tags=["auth"])

# Initialize SNSService once
sns_service = SNSService()


@router.post("/register", response_model=AuthResponse, status_code=status.HTTP_201_CREATED)
def register(payload: UserCreate, db: Annotated[Session, Depends(get_db)]) -> AuthResponse:
    repository = UserRepository(db)
    if repository.get_by_email(payload.email):
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Email is already registered")

    user = repository.create(payload.name, payload.email, hash_password(payload.password))
    
    # Attempt to publish welcome email via SNS
    try:
        sns_service.publish_welcome_email(user.email, user.name)
    except Exception as e:
        # Failsafe fallback: log the error and let registration succeed
        logger.error(f"Failed to publish SNS welcome email for {user.email}: {e}")

    token = create_access_token(user.id, {"email": user.email})
    return AuthResponse(access_token=token, user=user)


@router.post("/login", response_model=AuthResponse)
def login(payload: LoginRequest, db: Annotated[Session, Depends(get_db)]) -> AuthResponse:
    repository = UserRepository(db)
    user = repository.get_by_email(payload.email)
    if user is None or not verify_password(payload.password, user.password_hash):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid email or password")

    token = create_access_token(user.id, {"email": user.email})
    return AuthResponse(access_token=token, user=user)
