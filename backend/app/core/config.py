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
    aws_region: str = "us-east-1"
    s3_document_bucket: str = ""
    s3_document_kms_key_id: str = ""
    s3_presigned_url_expires_seconds: int = 900
    s3_max_upload_bytes: int = 10 * 1024 * 1024
    s3_allowed_content_types: str = (
        "application/pdf,image/jpeg,image/png,image/webp,text/plain,text/markdown,"
        "application/json,text/csv"
    )

    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8")

    @property
    def cors_origin_list(self) -> list[str]:
        return [origin.strip() for origin in self.cors_origins.split(",") if origin.strip()]

    @property
    def is_production(self) -> bool:
        return self.environment.lower() in PRODUCTION_ENVIRONMENTS

    @property
    def s3_allowed_content_type_list(self) -> set[str]:
        return {content_type.strip().lower() for content_type in self.s3_allowed_content_types.split(",") if content_type.strip()}

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

        if not self.s3_document_bucket:
            raise ValueError("S3_DOCUMENT_BUCKET is required when ENVIRONMENT=production")

        if not self.s3_document_kms_key_id:
            raise ValueError("S3_DOCUMENT_KMS_KEY_ID is required when ENVIRONMENT=production")

        return self


@lru_cache
def get_settings() -> Settings:
    return Settings()


settings = get_settings()
