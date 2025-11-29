# Project Overview

This is a multi-service task management application. It consists of a frontend, an authentication API, and a tasks API. The application is designed to be run with Docker or Podman.

## Architecture

The application is composed of four main services:

*   **Frontend:** A static web application built with HTML, CSS, and vanilla JavaScript. It is served by an Nginx web server acting as a reverse proxy.
    *   **Port:** 8080 (Mapped to container port 80)
    *   **Proxy Rules:**
        *   `/auth/` -> `auth-api:8000`
        *   `/api/` -> `tasks-api:8000`
*   **Authentication API:** A FastAPI application that handles user registration and login.
    *   **Port:** 8001 (Mapped to container port 8000)
    *   **Database:** PostgreSQL (Shared `tasksdb`)
    *   **Auth:** JWT (HS256)
*   **Tasks API:** A FastAPI application that provides CRUD functionality for tasks.
    *   **Port:** 8002 (Mapped to container port 8000)
    *   **Database:** PostgreSQL (`tasksdb`)
    *   **Auth:** JWT validation (Shared Secret)
*   **Database:** A PostgreSQL database used by the Tasks API to store task data.
    *   **Port:** 5432

## Building and Running

### Docker

To build and run the application with Docker, use the following command:

```bash
docker-compose up --build
```

The application will be available at `http://localhost:8080`.

### Podman

To build and run the application with Podman, first build the container images:

```bash
podman build -t auth-api:latest -f auth-api/Dockerfile ./auth-api
podman build -t tasks-api:latest -f tasks-api/Dockerfile ./tasks-api
podman build -t frontend:latest -f frontend/Dockerfile ./frontend
```

Then, deploy the application with:

```bash
podman kube play podman-deployment.yml
```

The application will be available at `http://localhost:8080`.

> [!NOTE]
> On Windows (WSL), `localhost` might not work directly for Podman. Use the WSL IP address:
> `wsl ip addr show eth0 | findstr "inet "`

To stop the application:
```bash
podman kube down podman-deployment.yml
```

## Development Conventions

*   **Backend:** Python 3.x using the **FastAPI** framework.
    *   **Auth API:** Uses `sqlalchemy` for SQLite.
    *   **Tasks API:** Uses `sqlalchemy` and `psycopg2-binary` for PostgreSQL.
*   **Frontend:** Vanilla HTML, CSS, and JavaScript.
    *   Uses `fetch` API to communicate with backend services via Nginx proxy.
*   **Authentication:** JSON Web Tokens (JWT) signed with `HS256`.
    *   Shared secret key defined in environment variables (`JWT_SECRET_KEY`).
*   **Containerization:**
    *   `docker-compose.yml` for local development.
    *   `podman-deployment.yml` for Kubernetes-like deployment with Podman.
