# Retail POS backend

One Django project for the retail POS (`lib/`) and the vitrine (`storefront/`).
The Flutter apps are not wired to it yet.

## Run locally

```bash
cd backend
python -m venv .venv && . .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env          # DJANGO_DEBUG=1 for local work
python manage.py migrate
python manage.py runserver
python manage.py test tests
```

Production needs `DJANGO_SECRET_KEY`, `PIN_PEPPER`, `DATABASE_URL` (Postgres) and
`REDIS_URL`; see `.env.example`. Schedule `python manage.py release_reservations`
every few minutes so lapsed vitrine reservations return their stock.

## Authentication

| Header | Who |
| --- | --- |
| `Bearer <Firebase ID token>` | Owner sign-in (Firebase, off until configured; `dev:<uid>` in DEBUG) |
| `Device <token>` | A paired register, before a PIN is entered |
| `Staff <token>` | A staff session from `POST /api/v1/auth/pin` or owner sign-in |
| `X-Shop-Key` | Legacy vitrine publishing / inbox |

Errors are always `{"error": "<message en français>"}`.

## Layout

- `/api/v1/` — accounts, catalog, customers, cash, sales (orders, checks, quotes),
  payments (paylinks, card intents, MonCash), storefront staff settings,
  notifications, timeclock, reports, catalog imports, sync (`push` / `pull`).
- `/storefront/` — public vitrine API and the legacy keyed endpoints, same paths
  and payloads as the old Node server.
- `/health`, `/config`, `/payments/...`, `/paid`, `/cancel`, `/catalog/imports` —
  legacy `payments_server` routes kept for the current apps.

Writes from the POS are idempotent: send the client-generated UUID as `id` (or an
`Idempotency-Key` header) and retries after a dropped connection are no-ops.
