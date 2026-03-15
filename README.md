# FYP Application

Web dashboard with user management and admin panel.

## Features

- **User management** — Pre-registered admin users, add/delete viewer users
- **Role-based access** — Admins have full control; viewers can only view data
- **Activity logging** — Track user actions in the admin panel

## Quick Start

```bash
# 1. Install dependencies
npm install

# 2. Create your environment file
# Windows PowerShell:
Copy-Item .env.example .env

# 3. Seed the database with 4 admin users
npm run seed

# 4. Start the server
npm start

# 5. Open in browser
# http://localhost:3000
```

## Security Configuration

- `CORS_ORIGIN`: Comma-separated list of allowed origins.
- `FORCE_HTTPS=true`: Enable HTTPS redirect in production behind a reverse proxy.
- `JWT_SECRET`: Set a strong random secret for production.

## Integrity Check

Run a full integrity check at any time:

```bash
npm run integrity:check
```

This verifies:
- SHA-256 manifest in `integrity/workspace.sha256`
- Git object integrity (`git fsck --full`)
- Dependency vulnerabilities (`npm audit --omit=dev`)

## Production Preflight

Before deployment, run:

```bash
npm run preflight:prod
```

This enforces:
- `NODE_ENV=production`
- Strong non-placeholder `JWT_SECRET`
- `FORCE_HTTPS=true`
- HTTPS-only `CORS_ORIGIN` entries
- Required SMTP configuration variables
- Valid `PORT` and `OTP_EXPIRY_MINUTES`
- Embedded integrity check execution

## MATLAB Simulation Live Status Integration

The dashboard now reads simulation status from your project files folder (`PROJECT_FILES_PATH`, default: `D:\\FPY Application_Files`).

Create/update these files from MATLAB while simulation runs:

1. `simulation_status.json`
2. `simulation_results.json`

Example `simulation_status.json`:

```json
{
	"connectionStatus": "connected",
	"state": "running",
	"progress": 42.5,
	"elapsedSeconds": 180,
	"etaSeconds": 240,
	"startedAt": "2026-03-15T16:00:00.000Z",
	"updatedAt": "2026-03-15T16:03:00.000Z",
	"message": "Solving power flow"
}
```

Example `simulation_results.json`:

```json
{
	"voltagePU": 0.985,
	"activePowerKW": 152.3,
	"reactivePowerKVAR": 47.1,
	"frequencyHz": 49.98
}
```

The dashboard polls `/api/simulation/status` every 3 seconds and updates:
- Dashboard Live/Offline status
- MATLAB Connected/Disconnected status
- Simulation progress %, elapsed time, ETA
- Live result values

## Default Admin Credentials

| Username | Password   |
|----------|-----------|
| admin1   | Admin@123 |
| admin2   | Admin@456 |
| admin3   | Admin@789 |
| admin4   | Admin@012 |

These 4 users have **admin** role with full privileges.
Any new user created from the admin panel gets **viewer** role.

## API Endpoints

| Method | Endpoint                     | Auth     | Description                    |
|--------|------------------------------|----------|--------------------------------|
| POST   | /api/auth/login              | No       | Login                          |
| POST   | /api/auth/logout             | No       | Logout                         |
| GET    | /api/auth/me                 | Yes      | Current session info           |
| GET    | /api/users                   | Admin    | List all users                 |
| POST   | /api/users                   | Admin    | Add new user (viewer role)     |
| DELETE | /api/users/:id               | Admin    | Delete user (non-admin only)   |
| PATCH  | /api/users/:id/toggle        | Admin    | Activate/deactivate user       |
| GET    | /api/admin/stats             | Admin    | Dashboard stats                |
| GET    | /api/admin/activity          | Admin    | Activity log                   |

## Tech Stack

- **Backend**: Node.js, Express, Socket.IO
- **Frontend**: Vanilla HTML/CSS/JavaScript
- **Auth**: JWT + bcrypt
