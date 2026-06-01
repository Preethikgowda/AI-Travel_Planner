# Contributing

## Local Setup

Run the full stack:

```bash
docker compose up --build
```

Run the frontend separately:

```bash
cd frontend
npm install
npm run dev
```

## Verification Before a PR

Run:

```bash
cd frontend
npm run build
```

Then from the repo root:

```bash
python -m compileall backend
docker compose config --quiet
```

## Environment Files

Copy `.env.example` to `.env` for local development. Do not commit `.env` or real credentials.
