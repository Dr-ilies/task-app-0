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

### Docker Compose / podman

```bash
docker-compose up --build
podman compose up --build
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

### Podman (K8s Manifests)

For testing production-like Kubernetes deployment locally, use the helper scripts that deploy `k8s-manifests/` directly with Podman. This method uses the same manifests as GKE deployment, ensuring parity between local and production environments.

1. **Deploy:**
   ```powershell
   .\scripts\local-k8s-deploy.ps1 -SkipBuild
   ```

   The script will:
   - Build all images locally
   - Process k8s-manifests for local compatibility
   - Deploy in correct order (database → auth-api → tasks-api → frontend)
   - Display access information

2. **Tear Down:**
   ```powershell
   .\scripts\local-k8s-down.ps1
   ```

   > [!NOTE]
   > Any changes to `k8s-manifests/` will automatically be reflected when you redeploy using this method.

### Kind (Kubernetes IN Docker)

For a **full Kubernetes cluster** with real DNS resolution, use Kind with Podman. This gives you the closest experience to GKE, including namespace support, services, and ingress.

**Prerequisites:** Install [Kind](https://kind.sigs.k8s.io/) and [kubectl](https://kubernetes.io/docs/tasks/tools/).

1. **Deploy:**
   ```powershell
   .\scripts\local-kind-deploy.ps1 # full deploy (builds and caches everything)
   .\scripts\local-kind-deploy.ps1 -SkipBuild # redeploy
   .\scripts\local-kind-deploy.ps1 -SkipBuild -SkipCluster # Quick redeploy (uses all caches)
   ```

   The script will:
   - Create a Kind cluster using Podman
   - Load container images into the cluster
   - Install NGINX Ingress Controller
   - Deploy all k8s-manifests with full Kubernetes DNS

2. **Tear Down:**
   ```powershell
   .\scripts\local-kind-down.ps1           # Delete entire cluster
   .\scripts\local-kind-down.ps1 -KeepCluster  # Keep cluster, delete namespace only
   ```

   > [!TIP]
   > Use `-KeepCluster` for faster redeployment. Then redeploy with `.\scripts\local-kind-deploy.ps1 -SkipCluster`.

### Minikube

Alternative to Kind with built-in addons. Uses Podman as the driver.

**Prerequisites:** Install [Minikube](https://minikube.sigs.k8s.io/) and [kubectl](https://kubernetes.io/docs/tasks/tools/).

1. **Deploy:**
   ```powershell
   .\scripts\local-minikube-deploy.ps1
   .\scripts\local-minikube-deploy.ps1 -SkipBuild -SkipCluster  # Quick redeploy
   ```

2. **Access:** Run `minikube -p task-app tunnel` then visit http://localhost

3. **Tear Down:**
   ```powershell
   .\scripts\local-minikube-down.ps1
   ```

### Deployment Method Comparison

| Method | Use Case | Kubernetes DNS | Ingress | Complexity |
|--------|----------|----------------|---------|------------|
| **Docker Compose** | Quick development | ❌ | ❌ | Low |
| **Podman Single Pod** | Simple K8s-like dev | ❌ (same pod) | ❌ | Low |
| **Podman K8s** | Pre-deployment testing | ❌ (IP injection) | ❌ | Medium |
| **Kind** | Full GKE parity | ✅ | ✅ | Medium |
| **Minikube** | Full GKE parity | ✅ | ✅ | Medium |

**Recommendation:** Use Docker Compose for daily development. Use Kind or Minikube for testing k8s-manifests with full Kubernetes features before deploying to GKE.



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
