# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Mobile companion app for the **Opus Accountancy Practice Manager**. The existing web application lives in the sibling `../Opus-PM/` directory.

- **App name**: Opus Accountancy Practice Manager (Mobile)
- **Branding**: Navy `#0f2744`, gold `#c9a84c`
- **Terminology**: Always "Client" in the UI (never "Customer")

## Backend API

This app connects to the existing Go/MongoDB backend from `../Opus-PM/backend/`. The API runs at `http://localhost:8080` in development.

### Authentication

- JWT (HS256), 7-day expiry
- Accepts `Authorization: Bearer <token>` header (the backend already supports this for mobile clients)
- Login: `POST /api/auth/login` with `{ username, password }` — returns JWT in response body and as HTTP-only cookie
- Refresh: `POST /api/auth/refresh`
- Current user: `GET /api/auth/me`
- Roles: `admin` and `user`

### Key API Endpoints

| Method | Path | Purpose |
|---|---|---|
| GET/POST | `/api/customers` | List/create clients |
| GET/PUT/DELETE | `/api/customers/{id}` | Client CRUD |
| GET | `/api/companies-house/{number}` | Companies House lookup |
| GET/POST | `/api/notes/{customerId}` | Client notes |
| GET/PUT | `/api/aml/records/{customerId}` | AML risk profiles |
| GET/POST | `/api/aml/assessments/{customerId}` | AML assessments |
| GET/POST | `/api/aml/documents/{customerId}` | AML documents (multipart upload) |
| GET/POST | `/api/time/entries` | Time tracking entries |
| GET | `/api/time/activities` | Non-client activities |
| GET | `/api/time/reports/clients` | Time reports by client |
| GET | `/api/services` | Service catalogue |

### Running the Backend Locally

```bash
cd ../Opus-PM
docker compose -f docker-compose.yml -f docker-compose.dev.yml up --build
```

Backend at http://localhost:8080, MongoDB at localhost:27017. Default login: `admin` / `changeme`.

## Data Model Reference

Key types (see `../Opus-PM/frontend/src/app/models/` for full TypeScript definitions):

- **Customer**: `clientKind: 'person' | 'company'`, `type: 'Limited Company' | 'Sole Trader' | 'Partnership' | 'LLP' | ...`
- Only `'Limited Company'` and `'LLP'` have Companies House integration
- Services are assigned per-client from a fixed catalogue (accounts_production, tax_returns, vat_service, etc.)
- Time entries use configurable "units" (default 15 minutes), stored as integer count
