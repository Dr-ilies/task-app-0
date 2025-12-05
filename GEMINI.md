# Project Overview

This is a multi-service task management application. It consists of a frontend, an authentication API, and a tasks API. The application is designed to be run locally (Docker/Podman) or deployed to the cloud (Google Cloud Run, GKE).

## Architecture

The application is composed of four main services:

*   **Frontend:** A static web application built with HTML, CSS, and vanilla JavaScript.
    *   **Server:** Nginx (acts as web server and reverse proxy).
    *   **Port:** 8080 (Mapped to container port 80).
    *   **Configuration:** Runtime environment variables (`AUTH_API_URL`, `TASKS_API_URL`) are injected via `envsubst` in Nginx.
    *   **Proxy Rules (Local):**
        *   `/auth/` -> `auth-api:8000`
        *   `/api/` -> `tasks-api:8000`
*   **Authentication API:** A FastAPI application that handles user registration and login.
    *   **Port:** 8001 (Mapped to container port 8000).
    *   **Database:** PostgreSQL (Shared `tasksdb`).
    *   **Auth:** JWT (HS256).
*   **Tasks API:** A FastAPI application that provides CRUD functionality for tasks.
    *   **Port:** 8002 (Mapped to container port 8000).
    *   **Database:** PostgreSQL (`tasksdb`).
    *   **Auth:** JWT validation (Shared Secret).
*   **Database:** A PostgreSQL database used by both the Auth API and Tasks API.
    *   **Port:** 5432.

## Local Development

You can run the application locally using either Docker Compose or Podman.

### Docker Compose

```bash
docker-compose up --build
```

The application will be available at `http://localhost:8080`.

### Podman (Kube Play)

For a Kubernetes-like local experience, we use `podman kube play` with a single-pod architecture defined in `podman-deployment.yml`.

1. **Build Images:**
   ```bash
   podman build -t auth-api:latest -f auth-api/Dockerfile ./auth-api
   podman build -t tasks-api:latest -f tasks-api/Dockerfile ./tasks-api
   podman build -t frontend:latest -f frontend/Dockerfile ./frontend
   ```

2. **Run Pod:**
   ```bash
   podman kube play podman-deployment.yml
   ```

   > [!NOTE]
   > On Windows (WSL), `localhost` might not work directly. Use your WSL IP:
   > `wsl ip addr show eth0 | findstr "inet "`

3. **Stop Pod:**
   ```bash
   podman kube down podman-deployment.yml
   ```

## Production Deployment

The project supports deployment to Google Cloud Platform via GitHub Actions.

### Google Cloud Run
Serverless deployment for individual containers. See [GCP_SETUP.md](GCP_SETUP.md) for detailed setup instructions.
- **Workflow:** `.github/workflows/deploy-gcr.yml`
- **Features:** Auto-scaling, Cloud SQL connection.

### Google Kubernetes Engine (GKE)
Orchestrated deployment on a Kubernetes cluster. See [k8s-manifests/README.md](k8s-manifests/README.md) for manifest details and manual deployment steps.
- **Workflow:** `.github/workflows/deploy-gke.yml`
- **Features:** Persistent Volume Claims, Internal Networking, Ingress.

## Development Conventions

*   **Backend:** Python 3.x using **FastAPI**.
    *   **Auth API:** Uses `sqlalchemy` with PostgreSQL.
    *   **Tasks API:** Uses `sqlalchemy` and `psycopg2-binary` for PostgreSQL.
*   **Frontend:** Vanilla HTML, CSS, JavaScript served by Nginx.
*   **Authentication:** JWT (HS256) with shared secret (`JWT_SECRET_KEY`).
*   **CI/CD:** GitHub Actions for automated testing and deployment.
