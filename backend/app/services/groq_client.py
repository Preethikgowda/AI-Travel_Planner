# Backward-compatible re-export.
# Any existing code importing from app.services.groq_client will continue to work.
from app.services.ai_service import TravelAIService  # noqa: F401

__all__ = ["TravelAIService"]
