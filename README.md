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

# 2. Seed the database with 4 admin users
npm run seed

# 3. Start the server
npm start

# 4. Open in browser
# http://localhost:3000
```

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
