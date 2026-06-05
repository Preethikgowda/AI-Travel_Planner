# AI Travel Planner API

All application traffic enters through the monolith backend at `http://localhost:8080/api`.

## Authentication

Protected endpoints require:

```http
Authorization: Bearer <jwt>
```

### POST `/api/auth/register`

Request:

```json
{
  "name": "Asha Rao",
  "email": "asha@example.com",
  "password": "replace-with-user-password"
}
```

Response:

```json
{
  "access_token": "jwt-token",
  "token_type": "bearer",
  "user": {
    "id": "uuid",
    "name": "Asha Rao",
    "email": "asha@example.com",
    "created_at": "2026-05-31T12:00:00Z"
  }
}
```

### POST `/api/auth/login`

Request:

```json
{
  "email": "asha@example.com",
  "password": "replace-with-user-password"
}
```

Response shape matches register.

## Users

### GET `/api/users/profile`

Returns the authenticated user's profile.

### PUT `/api/users/profile`

Request:

```json
{
  "name": "Asha Rao",
  "email": "asha.rao@example.com"
}
```

### GET `/api/users/preferences`

Returns the authenticated user's travel preferences.

### PUT `/api/users/preferences`

Request:

```json
{
  "travel_style": "balanced",
  "preferred_budget": 2500,
  "interests": ["food", "history", "nature"]
}
```

## Trips and Expenses

### POST `/api/trips`

Request:

```json
{
  "destination": "Kyoto",
  "budget": 2200,
  "days": 5,
  "interests": ["temples", "food", "gardens"],
  "status": "planned"
}
```

### GET `/api/trips`

Returns all trips for the authenticated user.

### GET `/api/trips/{id}`

Returns one trip owned by the authenticated user.

### PUT `/api/trips/{id}`

Request accepts any editable trip fields:

```json
{
  "destination": "Osaka",
  "budget": 2400,
  "days": 6,
  "interests": ["food", "nightlife"],
  "status": "active"
}
```

### DELETE `/api/trips/{id}`

Deletes a trip and its expenses.

### POST `/api/expenses`

Request:

```json
{
  "trip_id": "uuid",
  "category": "hotel",
  "amount": 320,
  "description": "Two nights near station"
}
```

### GET `/api/expenses/{trip_id}`

Returns expenses for a trip owned by the authenticated user.

### GET `/api/trip-history`

Returns trips sorted by most recent first.

## Documents

Documents are uploaded directly from the browser to S3 with backend-generated presigned URLs. The backend stores only metadata and verifies the S3 object before marking it available.

### POST `/api/trips/{trip_id}/documents/presign-upload`

Request:

```json
{
  "file_name": "flight-ticket.pdf",
  "content_type": "application/pdf",
  "size_bytes": 245760,
  "document_type": "flight_ticket"
}
```

Response:

```json
{
  "document": {
    "id": "uuid",
    "user_id": "uuid",
    "trip_id": "uuid",
    "document_scope": "trip",
    "document_type": "flight_ticket",
    "file_name": "flight-ticket.pdf",
    "content_type": "application/pdf",
    "size_bytes": 245760,
    "checksum_sha256": null,
    "s3_bucket": "ai-travel-planner-prod-documents",
    "s3_key": "users/user-id/trips/trip-id/documents/document-id/flight-ticket.pdf",
    "kms_key_id": "arn:aws:kms:us-east-1:123456789012:key/key-id",
    "status": "pending",
    "created_at": "2026-06-06T00:00:00Z",
    "uploaded_at": null,
    "deleted_at": null
  },
  "upload_url": "https://s3-presigned-put-url",
  "method": "PUT",
  "headers": {
    "Content-Type": "application/pdf",
    "x-amz-server-side-encryption": "aws:kms",
    "x-amz-server-side-encryption-aws-kms-key-id": "arn:aws:kms:us-east-1:123456789012:key/key-id"
  },
  "expires_at": "2026-06-06T00:15:00Z",
  "max_size_bytes": 10485760
}
```

The frontend must upload the file to `upload_url` with the returned headers.

### POST `/api/trips/{trip_id}/documents/{document_id}/complete`

Marks a document available after the backend verifies the S3 object exists, has the expected size, and uses SSE-KMS.

Request:

```json
{}
```

### GET `/api/trips/{trip_id}/documents`

Returns available documents for a trip owned by the authenticated user.

### GET `/api/trips/{trip_id}/documents/{document_id}/download-url`

Returns a short-lived private S3 download URL.

### DELETE `/api/trips/{trip_id}/documents/{document_id}`

Soft-deletes the document metadata and deletes the S3 object.

### POST `/api/documents/chat/presign-upload`

Same request shape as trip upload, but creates a standalone chat attachment with `document_scope` set to `chat`.

### POST `/api/documents/chat/{document_id}/complete`

Completes a chat attachment upload.

### GET `/api/documents/chat`

Returns available chat attachments for the authenticated user.

### DELETE `/api/documents/chat/{document_id}`

Deletes a chat attachment.

## AI

### POST `/api/ai/itinerary`

Request:

```json
{
  "destination": "Kyoto",
  "budget": 2200,
  "days": 5,
  "interests": ["temples", "food"]
}
```

Response:

```json
{
  "trip_summary": "string",
  "day_wise_plan": [
    {
      "day": 1,
      "title": "Arrival and orientation",
      "morning": "string",
      "afternoon": "string",
      "evening": "string"
    }
  ],
  "estimated_budget_breakdown": {
    "lodging": "string",
    "food": "string",
    "activities": "string",
    "transport": "string"
  },
  "travel_tips": ["string"]
}
```

### POST `/api/ai/chat`

Request:

```json
{
  "question": "What should I do in Kyoto when it rains?",
  "document_ids": ["uploaded-chat-document-uuid"]
}
```

### POST `/api/ai/budget-optimizer`

Request:

```json
{
  "destination": "Kyoto",
  "budget": 2200,
  "days": 5
}
```

### POST `/api/ai/compare`

Request:

```json
{
  "destination_a": "Kyoto",
  "destination_b": "Seoul"
}
```

### POST `/api/ai/packing-list`

Request:

```json
{
  "destination": "Kyoto",
  "travel_month": "April"
}
```

## Utility

### GET `/api/weather/{city}`

Returns weather from OpenWeatherMap when configured; otherwise returns a local deterministic forecast for development.

### GET `/api/hotels/{city}`

Returns hotel recommendations from Geoapify when configured. If Geoapify is not configured, Google Places is used when configured; otherwise local recommendations are returned.

### GET `/api/places/{city}`

Returns attraction recommendations from Geoapify when configured. If Geoapify is not configured, Google Places is used when configured; otherwise local recommendations are returned.
