# Dromo — Global Track Table API (Phase 1)

Facts-only, crowd-built per-recording metadata. Keyed by **ISRC** (primary) or
**acoustic fingerprint** (fallback). The first device to encounter a recording
analyzes it once and populates the table; every device after gets a free lookup.

> **Legal boundary (ARCHITECTURE §4):** only numbers and fingerprints are accepted.
> The request models use `extra="forbid"`, so any attempt to send audio/sample data
> is rejected with `422`. No audio, no titles/artists — identity + facts only.

## Endpoints (`/v1`)
| Method | Path | Purpose |
|--------|------|---------|
| `GET`  | `/healthz` | liveness |
| `GET`  | `/v1/track?isrc=…` or `?fingerprint=…` | lookup → facts or `404` |
| `POST` | `/v1/track` | populate on miss → `201 created` / `200 existing` (first-write-wins) |
| `POST` | `/v1/track/batch` | bulk lookup for library import (hits + misses) |

Interactive docs at `/docs` when running.

## Run locally (zero infra — SQLite)
```bash
cd server
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements-dev.txt
uvicorn app.main:app --reload          # uses ./dromo_tracktable.db
```

## Run with Postgres (Docker)
```bash
cd server
docker compose up --build               # api on :8000, postgres on :5432
```

## Test
```bash
cd server
pip install -r requirements-dev.txt
pytest                                   # in-memory SQLite, no Postgres needed
```

## Scope & boundaries (Phase 1)
- **In:** lookup, populate, batch lookup, identity (ISRC/fingerprint), the §7 schema, idempotent first-write-wins.
- **Out (later phases):** objective confirm/correction with anti-poisoning (Phase 6,
  `confirmation_count` column is already present); per-user taste layer (separate store, never here);
  Alembic migrations (v1 uses `create_all`); auth/rate-limiting.
