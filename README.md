# AI Travel Planner

Production-oriented AI travel planning platform built as independently deployable services with a React dashboard, FastAPI services, PostgreSQL databases, Docker, and Docker Compose.

## Architecture

The project has exactly four domain microservices:

- `user-service`: registration, login, JWT auth, profile, preferences
- `travel-service`: trips, trip history, expenses, budget summary
- `ai-service`: Groq-powered itinerary, chat, budget optimizer, destination comparison, packing list
- `utility-service`: weather, hotel recommendations, place recommendations

Supporting deployable components:

- `api-gateway`: routes `/api/...` traffic to the correct service
- `frontend`: React, TypeScript, Vite, TailwindCSS dashboard
- `user-db`: PostgreSQL database for user data
- `travel-db`: PostgreSQL database for travel data

## Folder Structure

```text
AI-travel-Planner/
  docker-compose.yml
  .env.example
  README.md
  docs/
    API.md
  frontend/
    Dockerfile
    nginx.conf
    package.json
    src/
      api/
      components/
      context/
      pages/
      types/
  services/
    api-gateway/
    ai-service/
    travel-service/
      alembic/
      app/
    user-service/
      alembic/
      app/
    utility-service/
```

## Requirements

- Docker Desktop
- Docker Compose v2
- Node.js 20 for local frontend development
- Python 3.12 for local service development
- Optional API keys:
  - `GROQ_API_KEY`
  - `OPENWEATHER_API_KEY`
  - `GEOAPIFY_API_KEY`
  - `GOOGLE_MAPS_API_KEY`

The app runs without external API keys by returning deterministic local development responses for AI and utility features. Add real keys when you want live Groq, OpenWeatherMap, Geoapify, or Google Places results.

## Environment

Create a local `.env` from the example:

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
USER_DB_PASSWORD=user_password
TRAVEL_DB_PASSWORD=travel_password
JWT_SECRET_KEY=replace-with-a-long-random-secret-before-production
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
- API Gateway: `http://localhost:8080`
- API docs per service:
  - `http://localhost:8011/docs`
  - `http://localhost:8012/docs`
  - `http://localhost:8013/docs`
  - `http://localhost:8014/docs`
  - `http://localhost:8080/docs`

## Ports

| Component | Port |
| --- | ---: |
| Frontend | `5173` |
| API Gateway | `8080` |
| User Service | `8011` |
| Travel Service | `8012` |
| AI Service | `8013` |
| Utility Service | `8014` |
| User PostgreSQL | `5433` |
| Travel PostgreSQL | `5434` |

## Database

`user-service` owns `user_db`:

- `users`
- `preferences`

`travel-service` owns `travel_db`:

- `trips`
- `expenses`

Alembic migrations run automatically when each database-backed service container starts.

Manual migration commands:

```bash
docker compose run --rm user-service alembic upgrade head
docker compose run --rm travel-service alembic upgrade head
```

## API Gateway Contract

All frontend calls use `http://localhost:8080/api`.

Routing:

- `/api/auth/*` -> user service
- `/api/users/*` -> user service
- `/api/trips/*` -> travel service
- `/api/expenses/*` -> travel service
- `/api/trip-history` -> travel service
- `/api/ai/*` -> AI service
- `/api/weather/*` -> utility service
- `/api/hotels/*` -> utility service
- `/api/places/*` -> utility service

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

## Service Development

Each backend service is self-contained and can be run independently.

Example:

```bash
cd services/user-service
python -m venv .venv
. .venv/Scripts/activate
pip install -r requirements.txt
uvicorn app.main:app --reload --port 8001
```

Use the corresponding `.env.example` in each service directory for local service-specific settings.

## Security Features

- JWT authentication
- Password hashing with bcrypt
- Protected backend endpoints
- Role-ready JWT claims
- Input validation with Pydantic
- CORS controls
- API rate limiting
- Service-level health checks
- Per-user trip and expense ownership checks

## Health Checks

```bash
curl http://localhost:8080/health
curl http://localhost:8011/health
curl http://localhost:8012/health
curl http://localhost:8013/health
curl http://localhost:8014/health
```

## Deployment Notes

The containers are structured for later ECS or EKS deployment:

- Each service has its own Dockerfile.
- Services communicate through environment-configured URLs.
- Databases are not shared across service ownership boundaries.
- Health endpoints are available for load balancers and orchestrators.
- Secrets are injected through environment variables.

AWS deployment assets are in [deploy/aws/README.md](deploy/aws/README.md). The production path uses:

- ECS Fargate for backend containers
- RDS PostgreSQL instead of Docker Compose database containers
- S3 + CloudFront for the React frontend
- AWS Secrets Manager for `DATABASE_URL`, `JWT_SECRET_KEY`, and external API keys
- An Application Load Balancer exposing only `api-gateway`

## GitHub Push Checklist

Before pushing this repo:

```bash
python -m compileall services
cd frontend
npm run build
```

Make sure only example env files are committed. Real `.env` files are ignored by `.gitignore`.
