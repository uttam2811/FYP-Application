# FYP MATLAB Simulation Monitor

Real-time web dashboard that monitors and displays output from MATLAB simulations.

## Features

- **Real-time updates** — MATLAB output instantly appears on the dashboard via WebSockets
- **Dual input methods** — HTTP API + file watcher (JSON/CSV/TXT)
- **User management** — 4 pre-registered admin users, add/delete viewer users
- **Role-based access** — Admins have full control; viewers can only view data
- **Live feed** — Scrolling feed of incoming simulation data
- **Simulation history** — Browse, filter, and view all past simulation records
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

## Sending Data from MATLAB

### Option 1: HTTP API (recommended)

```matlab
% Add the matlab/ folder to your MATLAB path, then:
send_to_monitor('my_simulation', struct('x', 1:10, 'y', rand(1,10)));
```

Or POST directly:
```matlab
url = 'http://localhost:3000/api/matlab/push';
data = struct('simulation_name', 'test', 'data', struct('value', 42));
webwrite(url, jsonencode(data), weboptions('MediaType','application/json'));
```

### Option 2: File Drop

Save `.json`, `.csv`, or `.txt` files into `server/matlab-output/`:
```matlab
data = struct('x', 1:100, 'y', sin(1:100));
fid = fopen('server/matlab-output/my_sim.json', 'w');
fprintf(fid, '%s', jsonencode(data));
fclose(fid);
```

## API Endpoints

| Method | Endpoint                     | Auth     | Description                    |
|--------|------------------------------|----------|--------------------------------|
| POST   | /api/auth/login              | No       | Login                          |
| POST   | /api/auth/logout             | No       | Logout                         |
| GET    | /api/auth/me                 | Yes      | Current session info           |
| POST   | /api/matlab/push             | No*      | Push simulation data           |
| GET    | /api/matlab/simulations      | Yes      | List simulation records        |
| GET    | /api/matlab/latest           | Yes      | Latest data per simulation     |
| GET    | /api/matlab/names            | Yes      | List simulation names          |
| GET    | /api/users                   | Admin    | List all users                 |
| POST   | /api/users                   | Admin    | Add new user (viewer role)     |
| DELETE | /api/users/:id               | Admin    | Delete user (non-admin only)   |
| PATCH  | /api/users/:id/toggle        | Admin    | Activate/deactivate user       |
| GET    | /api/admin/stats             | Admin    | Dashboard stats                |
| GET    | /api/admin/activity          | Admin    | Activity log                   |
| DELETE | /api/admin/simulations/clear | Admin    | Clear all simulation data      |

*The push endpoint is unauthenticated so MATLAB can post without a token.

## Tech Stack

- **Backend**: Node.js, Express, Socket.IO, better-sqlite3
- **Frontend**: Vanilla HTML/CSS/JavaScript
- **Real-time**: Socket.IO WebSockets
- **File watching**: Chokidar
- **Auth**: JWT + bcrypt
