from collections.abc import Mapping

import httpx
from fastapi import FastAPI, HTTPException, Request, Response, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from slowapi import Limiter
from slowapi.errors import RateLimitExceeded
from slowapi.middleware import SlowAPIMiddleware
from slowapi.util import get_remote_address

from app.core.config import settings

limiter = Limiter(key_func=get_remote_address, default_limits=[settings.rate_limit])

app = FastAPI(title="AI Travel Planner API Gateway", version="1.0.0")
app.state.limiter = limiter
app.add_middleware(SlowAPIMiddleware)
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origin_list,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

ROUTE_TARGETS: Mapping[str, str] = {
    "auth": settings.user_service_url,
    "users": settings.user_service_url,
    "trips": settings.travel_service_url,
    "expenses": settings.travel_service_url,
    "trip-history": settings.travel_service_url,
    "ai": settings.ai_service_url,
    "weather": settings.utility_service_url,
    "hotels": settings.utility_service_url,
    "places": settings.utility_service_url,
}

EXCLUDED_RESPONSE_HEADERS = {
    "connection",
    "content-encoding",
    "content-length",
    "keep-alive",
    "proxy-authenticate",
    "proxy-authorization",
    "te",
    "trailers",
    "transfer-encoding",
    "upgrade",
}


@app.exception_handler(RateLimitExceeded)
def rate_limit_handler(request: Request, exc: RateLimitExceeded):
    return JSONResponse(status_code=429, content={"detail": "Rate limit exceeded"})


@app.get("/health", tags=["health"])
def health_check() -> dict[str, str]:
    return {"status": "healthy", "service": settings.service_name}


@app.api_route(
    "/api/{full_path:path}",
    methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
)
async def proxy(full_path: str, request: Request) -> Response:
    if not full_path:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Route not found")

    prefix = full_path.split("/", 1)[0]
    target_base = ROUTE_TARGETS.get(prefix)
    if target_base is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=f"No upstream route for /api/{prefix}")

    upstream_url = f"{target_base.rstrip('/')}/{full_path}"
    body = await request.body()
    headers = {
        key: value
        for key, value in request.headers.items()
        if key.lower() not in {"host", "content-length"}
    }

    try:
        async with httpx.AsyncClient(timeout=settings.upstream_timeout_seconds) as client:
            upstream_response = await client.request(
                request.method,
                upstream_url,
                params=request.query_params,
                content=body,
                headers=headers,
            )
    except httpx.HTTPError as exc:
        raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY, detail="Upstream service unavailable") from exc

    response_headers = {
        key: value
        for key, value in upstream_response.headers.items()
        if key.lower() not in EXCLUDED_RESPONSE_HEADERS
    }
    return Response(
        content=upstream_response.content,
        status_code=upstream_response.status_code,
        headers=response_headers,
        media_type=upstream_response.headers.get("content-type"),
    )
