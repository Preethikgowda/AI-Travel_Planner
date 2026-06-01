# AI Travel Planner

AI Travel Planner is a 3-tier travel planning application:

- **Presentation tier**: React, TypeScript, Vite, TailwindCSS
- **Application tier**: one FastAPI monolith backend
- **Data tier**: one PostgreSQL database

The backend owns authentication, user preferences, trips, expenses, AI travel assistance, weather, hotels, and places APIs.

## Architecture

```text
AI-travel-Planner/
  backend/
    Dockerfile
    alembic/
    app/
      api/
      core/
      db/
      models/
      repositories/
      schemas/
      services/
  frontend/
    Dockerfile
    nginx.conf
    src/
  deploy/
    aws/
  docs/
    API.md
  docker-compose.yml
```

Runtime services:

- `frontend`: browser UI served by Nginx
- `backend`: FastAPI monolith serving `/api/*`
- `db`: PostgreSQL database

## Requirements

- Docker Desktop
- Docker Compose v2
- Node.js 20 for local frontend-only development
- Python 3.12 for local backend-only development

Optional API keys:

- `GROQ_API_KEY`
- `OPENWEATHER_API_KEY`
- `GEOAPIFY_API_KEY`
- `GOOGLE_MAPS_API_KEY`

The app runs without external API keys by returning deterministic local development responses.

## Features

- User registration and login with JWT authentication
- Protected dashboard and navigation
- User profile and travel preference management
- Trip creation, listing, editing, deletion, and history
- Expense tracking per trip
- Budget summary across saved trips
- AI itinerary generation
- AI travel chat assistant
- Destination comparison
- Packing list assistant
- Weather lookup
- Hotel recommendations
- Place and attraction recommendations

More feature details are in [docs/FEATURES.md](docs/FEATURES.md).

## Tech Stack

| Layer | Technology | Usage |
| --- | --- | --- |
| Frontend | React 18 | Browser UI and page composition |
| Frontend | TypeScript | Type-safe UI code |
| Frontend | Vite | Frontend build and dev server |
| Frontend | TailwindCSS | Utility-first styling |
| Frontend | TanStack Query | Server-state fetching and cache invalidation |
| Frontend | Axios | HTTP client for backend API calls |
| Frontend | React Router | Client-side routing and protected pages |
| Backend | FastAPI | REST API and OpenAPI docs |
| Backend | SQLAlchemy | ORM models and database access |
| Backend | Alembic | Database schema migrations |
| Backend | Pydantic | Request/response validation and settings |
| Backend | python-jose | JWT creation and validation |
| Backend | Passlib/bcrypt | Password hashing |
| Backend | SlowAPI | API rate limiting |
| Backend | HTTPX | External API calls to AI/weather/place providers |
| Database | PostgreSQL | Persistent application data |
| Runtime | Docker Compose | Local 3-tier orchestration |

## Request Flow

```text
Browser
  -> React frontend served on localhost:5173
  -> Axios API client using VITE_API_BASE_URL
  -> FastAPI backend on localhost:8080/api
  -> route handler
  -> service/repository layer
  -> PostgreSQL database or external provider
  -> JSON response back to React
```

Examples:

- Login: `Login.tsx -> POST /api/auth/login -> auth route -> UserRepository -> PostgreSQL -> JWT response`
- Create trip: `CreateTrip.tsx -> POST /api/trips -> trips route -> TravelRepository -> PostgreSQL`
- Generate itinerary: `CreateTrip.tsx -> POST /api/ai/itinerary -> AI route -> TravelAIService -> Groq API or local fallback`
- Weather: `Dashboard.tsx -> GET /api/weather/{city} -> utility route -> OpenWeatherMap or local fallback`

More architecture details are in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Environment

Create a local `.env`:

```bash
cp .env.example .env
```

On Windows PowerShell:

```powershell
Copy-Item .env.example .env
```

Set production-grade secrets before deploying:

```env
ENVIRONMENT=local
DB_PASSWORD=ai_travel_password
JWT_SECRET_KEY=replace-with-a-long-random-secret-before-production
JWT_ALGORITHM=HS256
ACCESS_TOKEN_EXPIRE_MINUTES=1440
CORS_ORIGINS=http://localhost:5173,http://localhost:8080
VITE_API_BASE_URL=http://localhost:8080/api
GROQ_API_KEY=
OPENWEATHER_API_KEY=
GEOAPIFY_API_KEY=
GOOGLE_MAPS_API_KEY=
```

## Run Everything

```bash
docker compose up --build
```

Open:

- Frontend: `http://localhost:5173`
- Backend: `http://localhost:8080`
- Backend docs: `http://localhost:8080/docs`

If you previously ran the old microservice stack, clean old containers first:

```bash
docker compose down --remove-orphans
docker compose up --build
```

## Ports

| Component | Port |
| --- | ---: |
| Frontend | `5173` |
| Backend | `8080` |
| PostgreSQL | `5435` |

## Database

The monolith uses one PostgreSQL database:

```text
ai_travel
```

Tables:

- `users`
- `preferences`
- `trips`
- `expenses`

Alembic migrations run automatically when the backend container starts.

Manual migration command:

```bash
docker compose run --rm backend alembic upgrade head
```

## API Contract

All frontend calls use:

```text
http://localhost:8080/api
```

Main route groups:

- `/api/auth/*`
- `/api/users/*`
- `/api/trips/*`
- `/api/expenses/*`
- `/api/trip-history`
- `/api/ai/*`
- `/api/weather/*`
- `/api/hotels/*`
- `/api/places/*`

Detailed endpoint contracts are in [docs/API.md](docs/API.md).

## Local Frontend Development

```bash
cd frontend
npm install
npm run dev
```

The dev server uses:

```env
VITE_API_BASE_URL=http://localhost:8080/api
```

## Local Backend Development

```bash
cd backend
python -m venv .venv
. .venv/Scripts/activate
pip install -r requirements.txt
uvicorn app.main:app --reload --port 8080
```

Run PostgreSQL through Compose or point `DATABASE_URL` to your own database.

## Health Check

```bash
curl http://localhost:8080/health
```

## Deployment Notes

AWS deployment assets are in [deploy/aws/README.md](deploy/aws/README.md). The production path uses:

- ECS Fargate for the backend container
- RDS PostgreSQL for the database
- S3 + CloudFront for the React frontend
- AWS Secrets Manager for `DATABASE_URL`, `JWT_SECRET_KEY`, and external API keys
- An Application Load Balancer exposing the backend

## GitHub Push Checklist

Before pushing this repo:

```bash
python -m compileall backend
cd frontend
npm run build
```

Make sure only example env files are committed. Real `.env` files are ignored by `.gitignore`.
