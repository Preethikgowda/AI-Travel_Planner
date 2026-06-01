from functools import lru_cache

from pydantic import model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


PRODUCTION_ENVIRONMENTS = {"production", "prod"}
PLACEHOLDER_JWT_SECRETS = {
    "change-this-local-dev-secret",
    "replace-with-a-long-random-secret-before-production",
}
LOCAL_ONLY_VALUES = ("localhost", "127.0.0.1", "host.docker.internal")


class Settings(BaseSettings):
    environment: str = "local"
    service_name: str = "ai-travel-backend"
    database_url: str = "postgresql+psycopg://ai_travel:ai_travel_password@localhost:5435/ai_travel"
    jwt_secret_key: str = "change-this-local-dev-secret"
    jwt_algorithm: str = "HS256"
    access_token_expire_minutes: int = 1440
    cors_origins: str = "http://localhost:5173,http://localhost:8080"
    rate_limit: str = "240/minute"
    groq_api_key: str = ""
    groq_model: str = "llama-3.3-70b-versatile"
    groq_base_url: str = "https://api.groq.com/openai/v1/chat/completions"
    groq_timeout_seconds: float = 30.0
    openweather_api_key: str = ""
    geoapify_api_key: str = ""
    google_maps_api_key: str = ""
    request_timeout_seconds: float = 20.0

    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8")

    @property
    def cors_origin_list(self) -> list[str]:
        return [origin.strip() for origin in self.cors_origins.split(",") if origin.strip()]

    @property
    def is_production(self) -> bool:
        return self.environment.lower() in PRODUCTION_ENVIRONMENTS

    @model_validator(mode="after")
    def validate_production_settings(self):
        if not self.is_production:
            return self

        if self.jwt_secret_key in PLACEHOLDER_JWT_SECRETS or len(self.jwt_secret_key) < 32:
            raise ValueError("JWT_SECRET_KEY must be replaced with a strong production secret")

        if any(value in self.database_url for value in LOCAL_ONLY_VALUES):
            raise ValueError("DATABASE_URL must point to the production database when ENVIRONMENT=production")

        if any(value in origin for origin in self.cors_origin_list for value in LOCAL_ONLY_VALUES):
            raise ValueError("CORS_ORIGINS must contain only production origins when ENVIRONMENT=production")

        return self


@lru_cache
def get_settings() -> Settings:
    return Settings()


settings = get_settings()
