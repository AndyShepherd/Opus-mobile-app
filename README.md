# Opus Mobile

Native iOS companion app for the [Opus Accountancy Practice Manager](https://github.com/AndyShepherd/Opus-PM).

## Features

- **Client Management** — Browse, search, and filter clients
- **Client Detail** — Company info, contacts, and quick actions (call, email, message)
- **Secure Authentication** — JWT login with iOS Keychain storage

## Getting Started

**Requirements:** Xcode 16+, iOS 17+, and the [Opus PM backend](https://github.com/AndyShepherd/Opus-PM) running.

```bash
# 1. Start the backend
cd ../Opus-PM
docker compose -f docker-compose.yml -f docker-compose.dev.yml up --build

# 2. Open and run in Xcode
open OpusMobile.xcodeproj
```

Default login: `admin` / `changeme`

## Documentation

See the **[Wiki](https://github.com/AndyShepherd/Opus-mobile-app/wiki)** for detailed documentation:

- [Architecture](https://github.com/AndyShepherd/Opus-mobile-app/wiki/Architecture) — Project structure, layers, and data flow
- [Views](https://github.com/AndyShepherd/Opus-mobile-app/wiki/Views) — Login, Client List, Client Detail
- [Services](https://github.com/AndyShepherd/Opus-mobile-app/wiki/Services) — API client, auth, Keychain
- [Models](https://github.com/AndyShepherd/Opus-mobile-app/wiki/Models) — Customer, Contact, User
- [Configuration](https://github.com/AndyShepherd/Opus-mobile-app/wiki/Configuration) — Build config and branding
- [Backend API](https://github.com/AndyShepherd/Opus-mobile-app/wiki/Backend-API) — Endpoints and local setup

## Related

- [Opus PM](https://github.com/AndyShepherd/Opus-PM) — Full web application and backend
