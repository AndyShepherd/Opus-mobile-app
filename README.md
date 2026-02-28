# Opus Mobile

Native iOS companion app for the [Opus Accountancy Practice Manager](https://github.com/AndyShepherd/Opus-PM).

## Features

- **Client Management** — Browse, search, and view client details
- **Client Detail** — View company info, assigned services, and contact details
- **Secure Authentication** — JWT-based login with Keychain token storage

## Requirements

- Xcode 16+
- iOS 17+
- The [Opus PM backend](https://github.com/AndyShepherd/Opus-PM) running locally or remotely

## Getting Started

### 1. Start the backend

```bash
cd ../Opus-PM
docker compose -f docker-compose.yml -f docker-compose.dev.yml up --build
```

This starts the Go API at `http://localhost:8080` and MongoDB at `localhost:27017`.

Default login: `admin` / `changeme`

### 2. Run the app

Open `OpusMobile.xcodeproj` in Xcode, select an iOS simulator, and run.

The app connects to `http://localhost:8080` in debug builds.

## Project Structure

```
OpusMobile/
├── OpusMobileApp.swift        # App entry point
├── Config.swift               # API base URL configuration
├── Models/
│   ├── Customer.swift         # Client data model
│   └── User.swift             # User/auth data model
├── Services/
│   ├── APIClient.swift        # HTTP client for the backend API
│   ├── AuthService.swift      # Authentication state management
│   └── KeychainHelper.swift   # Secure token storage
├── Views/
│   ├── LoginView.swift        # Login screen
│   ├── ClientListView.swift   # Client list with search
│   └── ClientDetailView.swift # Client detail screen
└── Assets.xcassets/           # App icons, colours, and images
```

## Related

- [Opus PM](https://github.com/AndyShepherd/Opus-PM) — Full web application and backend
