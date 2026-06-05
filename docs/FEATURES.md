# Features

## Authentication

Users create their own account with name, email, and password. Passwords are hashed with bcrypt before storage. Login returns a JWT access token used by the frontend for protected requests.

Frontend flow:

```text
Register/Login page -> AuthContext -> Axios -> /api/auth/* -> JWT stored in localStorage
```

Backend flow:

```text
auth route -> UserRepository -> PostgreSQL users table -> JWT response
```

## Session Validation

When the app starts, the frontend validates any stored token by calling `/api/users/profile`. Invalid or expired tokens are cleared and the user is sent to the login page.

## Dashboard

The dashboard summarizes saved trips, budget totals, weather, and hotel recommendations. Data is fetched with TanStack Query and refreshed when trip or expense mutations succeed.

## Trip Planning

Users can create trips with destination, budget, trip length, interests, and status. Trips are persisted in PostgreSQL and linked to the authenticated user.

Main endpoints:

```text
POST /api/trips
GET /api/trips
GET /api/trips/{id}
PUT /api/trips/{id}
DELETE /api/trips/{id}
GET /api/trip-history
```

## AI Itinerary

The itinerary assistant accepts destination, budget, days, and interests. If `GROQ_API_KEY` is configured, the backend calls Groq. If not, it returns a deterministic local fallback so the app still works in development.

Endpoint:

```text
POST /api/ai/itinerary
```

## AI Chat Assistant

Users can ask travel planning questions. The backend uses Groq when configured and fallback responses otherwise.

Endpoint:

```text
POST /api/ai/chat
```

## Budget Optimizer

The backend generates budget-saving suggestions based on destination, total budget, and number of days.

Endpoint:

```text
POST /api/ai/budget-optimizer
```

## Destination Comparison

Users compare two destinations across cost, weather, activities, and recommendation.

Endpoint:

```text
POST /api/ai/compare
```

## Packing Assistant

Users enter a destination and travel month, and the backend returns categorized packing recommendations.

Endpoint:

```text
POST /api/ai/packing-list
```

## Expense Tracking

Expenses are linked to a trip and owner-checked through the trip relationship. Users can add and view expenses for their own trips.

Main endpoints:

```text
POST /api/expenses
GET /api/expenses/{trip_id}
GET /api/trips/budget-summary
```

## Trip Documents

Users can upload private trip documents such as tickets, hotel bookings, visas, insurance, passport copies, receipts, and itineraries. The backend stores metadata in PostgreSQL and uses short-lived S3 presigned URLs for direct browser uploads and downloads.

Production storage controls:

- S3 bucket is private with public access blocked
- objects are encrypted with SSE-KMS
- uploads are limited by allowed content type and file size
- document access is checked against the authenticated user and trip owner
- deletes are soft-deleted in PostgreSQL and issue an S3 delete marker when bucket versioning is enabled

Main endpoints:

```text
POST /api/trips/{trip_id}/documents/presign-upload
POST /api/trips/{trip_id}/documents/{document_id}/complete
GET /api/trips/{trip_id}/documents
GET /api/trips/{trip_id}/documents/{document_id}/download-url
DELETE /api/trips/{trip_id}/documents/{document_id}
```

## Chat Attachments

The AI assistant supports encrypted file attachments. Files are uploaded through the same S3/KMS presigned flow and the chat request sends document IDs. The backend verifies ownership before passing safe file metadata to the AI service. File contents are not sent to the model by default.

Main endpoints:

```text
POST /api/documents/chat/presign-upload
POST /api/documents/chat/{document_id}/complete
GET /api/documents/chat
DELETE /api/documents/chat/{document_id}
POST /api/ai/chat
```

## Weather, Hotels, And Places

The utility routes use external APIs when keys are configured:

- OpenWeatherMap for weather
- Geoapify for hotels and places
- Google Places as an optional fallback for hotels and places

If keys are missing, local fallback data is returned.

Main endpoints:

```text
GET /api/weather/{city}
GET /api/hotels/{city}
GET /api/places/{city}
```
