from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from slowapi import Limiter
from slowapi.errors import RateLimitExceeded
from slowapi.middleware import SlowAPIMiddleware
from slowapi.util import get_remote_address
from sqlalchemy.exc import SQLAlchemyError

from app.api.routes import ai, auth, expenses, trips, users, utility
from app.core.config import settings

limiter = Limiter(key_func=get_remote_address, default_limits=[settings.rate_limit])

app = FastAPI(title="AI Travel Planner Backend", version="2.0.0")
app.state.limiter = limiter
app.add_middleware(SlowAPIMiddleware)
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origin_list,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.exception_handler(RateLimitExceeded)
def rate_limit_handler(request: Request, exc: RateLimitExceeded):
    return JSONResponse(status_code=429, content={"detail": "Rate limit exceeded"})


@app.exception_handler(SQLAlchemyError)
def database_error_handler(request: Request, exc: SQLAlchemyError):
    return JSONResponse(status_code=500, content={"detail": "Database operation failed"})


@app.get("/health", tags=["health"])
def health_check() -> dict[str, str]:
    return {"status": "healthy", "service": settings.service_name, "architecture": "monolith-3-tier"}


app.include_router(auth.router, prefix="/api")
app.include_router(users.router, prefix="/api")
app.include_router(trips.router, prefix="/api")
app.include_router(expenses.router, prefix="/api")
app.include_router(ai.router, prefix="/api")
app.include_router(utility.router, prefix="/api")
