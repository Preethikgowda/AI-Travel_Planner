from functools import lru_cache
import json
import base64
from typing import Any

from pydantic import model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

import boto3
from botocore.exceptions import BotoCoreError, ClientError


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

    # AWS / Bedrock settings
    enable_bedrock: bool = True
    bedrock_model_id: str = "meta.llama3-8b-instruct-v1:0"
    bedrock_region: str = ""

    # Enable reading secrets from AWS Secrets Manager instead of environment variables
    aws_secrets_enabled: bool = False
    api_keys_secret_arn: str = ""
    db_secret_arn: str = ""
    jwt_secret_arn: str = ""
    rds_endpoint: str = ""

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
        # If AWS secrets integration is enabled, attempt to populate sensitive values from Secrets Manager.
        if self.aws_secrets_enabled:
            try:
                client = boto3.client("secretsmanager", region_name=self.aws_region)

                def _load_secret(secret_arn: str) -> dict[str, Any]:
                    if not secret_arn:
                        return {}
                    try:
                        resp = client.get_secret_value(SecretId=secret_arn)
                    except (BotoCoreError, ClientError):
                        return {}
                    secret_string = resp.get("SecretString")
                    if secret_string:
                        try:
                            return json.loads(secret_string)
                        except json.JSONDecodeError:
                            return {"value": secret_string}
                    binary = resp.get("SecretBinary")
                    if binary:
                        try:
                            decoded = base64.b64decode(binary).decode("utf-8")
                            return json.loads(decoded)
                        except Exception:
                            return {"value": decoded}
                    return {}

                api_keys = _load_secret(self.api_keys_secret_arn)
                if api_keys:
                    self.groq_api_key = api_keys.get("groq_api_key", self.groq_api_key)
                    self.openweather_api_key = api_keys.get("openweather_api_key", self.openweather_api_key)
                    self.geoapify_api_key = api_keys.get("geoapify_api_key", self.geoapify_api_key)
                    self.google_maps_api_key = api_keys.get("google_maps_api_key", self.google_maps_api_key)

                jwt_secret = _load_secret(self.jwt_secret_arn)
                if jwt_secret:
                    # secret may be stored as {"jwt_secret": "..."} or as raw string
                    self.jwt_secret_key = jwt_secret.get("jwt_secret") or jwt_secret.get("value") or self.jwt_secret_key

                db_secret = _load_secret(self.db_secret_arn)
                if db_secret:
                    # Expecting keys: username, password, host (or use rds_endpoint), db_name
                    username = db_secret.get("username") or db_secret.get("user") or getattr(self, "rds_username", None)
                    password = db_secret.get("password") or db_secret.get("pwd")
                    host = self.rds_endpoint or db_secret.get("host") or db_secret.get("host_port")
                    dbname = db_secret.get("db_name") or db_secret.get("database") or "ai_travel"
                    if username and password and host:
                        # Ensure we don't append port twice if host already contains it
                        if ":" in host:
                            self.database_url = f"postgresql+psycopg://{username}:{password}@{host}/{dbname}"
                        else:
                            self.database_url = f"postgresql+psycopg://{username}:{password}@{host}:5432/{dbname}"
            except Exception:
                # Avoid failing startup if secrets cannot be fetched; we'll validate later for production.
                pass

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
