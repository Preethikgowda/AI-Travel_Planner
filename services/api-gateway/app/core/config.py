from functools import lru_cache

from pydantic import model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


PRODUCTION_ENVIRONMENTS = {"production", "prod"}
LOCAL_ONLY_VALUES = ("localhost", "127.0.0.1", "host.docker.internal")


class Settings(BaseSettings):
    environment: str = "local"
    service_name: str = "api-gateway"
    user_service_url: str = "http://localhost:8001"
    travel_service_url: str = "http://localhost:8002"
    ai_service_url: str = "http://localhost:8003"
    utility_service_url: str = "http://localhost:8004"
    cors_origins: str = "http://localhost:5173,http://localhost:8080"
    rate_limit: str = "240/minute"
    upstream_timeout_seconds: float = 45.0

    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8")

    @property
    def cors_origin_list(self) -> list[str]:
        return [origin.strip() for origin in self.cors_origins.split(",") if origin.strip()]

    @property
    def upstream_urls(self) -> list[str]:
        return [
            self.user_service_url,
            self.travel_service_url,
            self.ai_service_url,
            self.utility_service_url,
        ]

    @property
    def is_production(self) -> bool:
        return self.environment.lower() in PRODUCTION_ENVIRONMENTS

    @model_validator(mode="after")
    def validate_production_settings(self):
        if not self.is_production:
            return self

        if any(value in origin for origin in self.cors_origin_list for value in LOCAL_ONLY_VALUES):
            raise ValueError("CORS_ORIGINS must contain only production origins when ENVIRONMENT=production")

        if any(value in url for url in self.upstream_urls for value in LOCAL_ONLY_VALUES):
            raise ValueError("Upstream service URLs must use production service discovery when ENVIRONMENT=production")

        return self


@lru_cache
def get_settings() -> Settings:
    return Settings()


settings = get_settings()
