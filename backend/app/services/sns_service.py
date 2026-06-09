import logging
from typing import Optional

import boto3
from botocore.exceptions import BotoCoreError, ClientError

from app.core.config import settings

logger = logging.getLogger(__name__)


class SNSService:
    def __init__(self) -> None:
        self.topic_arn = settings.sns_topic_arn
        if not self.topic_arn:
            logger.warning("SNS_TOPIC_ARN is not configured. SNS notifications will be disabled.")
            self._client = None
            return

        # Extract region from the SNS Topic ARN if available (format: arn:aws:sns:region:account:name)
        # Fallback to default aws_region setting.
        region_name = settings.aws_region
        if self.topic_arn:
            arn_parts = self.topic_arn.split(":")
            if len(arn_parts) >= 4 and arn_parts[3]:
                region_name = arn_parts[3]

        # Initialize boto3 client with provided credentials if they exist,
        # otherwise boto3 will automatically use IAM roles or local AWS config.
        client_kwargs = {"region_name": region_name}
        if settings.aws_access_key_id and settings.aws_secret_access_key:
            client_kwargs["aws_access_key_id"] = settings.aws_access_key_id
            client_kwargs["aws_secret_access_key"] = settings.aws_secret_access_key

        try:
            self._client = boto3.client("sns", **client_kwargs)
        except Exception as e:
            logger.error(f"Failed to initialize SNS client: {e}")
            self._client = None

    @property
    def client(self):
        return self._client

    def publish_welcome_email(self, email: str, name: str) -> None:
        """
        Publishes a welcome message to the configured SNS topic.
        Fails silently (with logging) to ensure caller workflows are not disrupted.
        """
        if not self.client or not self.topic_arn:
            return

        subject = "Welcome to AI Travel Planner!"
        message = (
            f"Hello {name},\n\n"
            f"Welcome to AI Travel Planner! We are thrilled to have you on board.\n"
            f"Get ready to explore the world with personalized, AI-driven itineraries.\n\n"
            f"Best regards,\nThe AI Travel Planner Team"
        )

        try:
            # We can optionally pass the email as a message attribute if the SNS topic 
            # uses subscription filter policies to route specific messages.
            # However, standard SNS just broadcasts the message to all subscribed endpoints.
            # To send to a specific email, you generally use Amazon SES, but since the 
            # requirement specifies SNS, we will publish to the SNS Topic.
            self.client.publish(
                TopicArn=self.topic_arn,
                Subject=subject,
                Message=message,
                MessageAttributes={
                    "email": {
                        "DataType": "String",
                        "StringValue": email
                    }
                }
            )
            logger.info(f"Successfully published welcome message to SNS for user: {email}")
        except (BotoCoreError, ClientError) as e:
            logger.error(f"Failed to publish welcome message to SNS for user {email}: {e}")
        except Exception as e:
            logger.error(f"Unexpected error publishing welcome message to SNS for user {email}: {e}")
