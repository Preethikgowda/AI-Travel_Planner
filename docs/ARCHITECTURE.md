# Architecture

## 3-Tier Monolith

The project uses a simple 3-tier architecture:

```text
Presentation tier: React frontend
Application tier: FastAPI backend monolith
Data tier: PostgreSQL
Object storage: Amazon S3 with SSE-KMS for private documents
```

Local Docker Compose services:

```text
frontend -> backend -> db
```

## Directory Structure

```text
backend/
  app/
    api/
      routes/
    core/
    db/
    models/
    repositories/
    schemas/
    services/
  alembic/

frontend/
  src/
    api/
    components/
    context/
    pages/
    types/

docs/
deploy/
```

## Frontend Responsibilities

The frontend is responsible for:

- browser routing
- login/register forms
- protected page routing
- dashboard and workflow pages
- calling the backend API through Axios
- caching server state with TanStack Query
- storing the JWT and user object in localStorage

Key files:

```text
frontend/src/api/client.ts
frontend/src/context/AuthContext.tsx
frontend/src/components/ProtectedRoute.tsx
frontend/src/pages/
```

## Backend Responsibilities

The FastAPI backend owns all application behavior:

- authentication
- user profile and preferences
- trip CRUD
- expenses
- AI travel tools
- utility data for weather, hotels, and places
- validation
- rate limiting
- database migrations

Key files:

```text
backend/app/main.py
backend/app/api/routes/
backend/app/models/
backend/app/repositories/
backend/app/services/
backend/alembic/
```

## Data Model

PostgreSQL tables:

```text
users
preferences
trips
expenses
```

Relationships:

```text
users 1 -> 1 preferences
users 1 -> many trips
trips 1 -> many expenses
trips 1 -> many travel_documents
users 1 -> many travel_documents
```

File objects are not stored in PostgreSQL. PostgreSQL stores document metadata and S3 stores the encrypted object.

## Request Flow

### Login

```text
Login.tsx
  -> AuthContext.login()
  -> Axios POST /api/auth/login
  -> backend auth route
  -> UserRepository.get_by_email()
  -> bcrypt password verification
  -> JWT creation
  -> frontend stores JWT
```

### Authenticated Page Load

```text
Browser loads React app
  -> AuthProvider reads localStorage token
  -> GET /api/users/profile
  -> token valid: continue to protected route
  -> token invalid: clear localStorage and redirect to /login
```

### Create Trip

```text
CreateTrip.tsx
  -> POST /api/trips
  -> token decoded by dependency
  -> TravelRepository.create_trip()
  -> PostgreSQL trips table
  -> response returned to React
```

### AI Itinerary

```text
CreateTrip.tsx
  -> POST /api/ai/itinerary
  -> AI route
  -> TravelAIService
  -> Groq API when GROQ_API_KEY exists
  -> local fallback when key is absent
```

### Weather / Hotels / Places

```text
Dashboard or utility page
  -> GET /api/weather/{city}, /api/hotels/{city}, or /api/places/{city}
  -> UtilityApiService
  -> external API when key exists
  -> local fallback when key is absent
```

### Trip Document Upload

```text
TripDocuments.tsx
  -> POST /api/trips/{trip_id}/documents/presign-upload
  -> backend checks JWT and trip ownership
  -> backend creates pending document metadata
  -> backend returns short-lived S3 PUT URL with SSE-KMS headers
  -> browser uploads directly to S3
  -> POST /api/trips/{trip_id}/documents/{document_id}/complete
  -> backend verifies S3 object size and KMS encryption
  -> document becomes available
```

### Chat Attachment Upload

```text
AITravelAssistant.tsx
  -> POST /api/documents/chat/presign-upload
  -> browser uploads directly to S3
  -> POST /api/documents/chat/{document_id}/complete
  -> POST /api/ai/chat with document_ids
  -> backend verifies owner and passes file metadata to TravelAIService
```

## Deployment Shape

Recommended AWS production shape:

```text
CloudFront + S3 -> React frontend
Application Load Balancer -> ECS Fargate backend
ECS backend -> RDS PostgreSQL
ECS backend -> private S3 document bucket encrypted with KMS
Secrets Manager -> backend secrets
```

See [deploy/aws/README.md](../deploy/aws/README.md).
