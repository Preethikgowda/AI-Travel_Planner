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
  "question": "What should I do in Kyoto when it rains?"
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
