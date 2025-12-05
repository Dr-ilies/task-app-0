# GKE Kubernetes Manifests

This directory contains Kubernetes manifests for deploying the task management application to Google Kubernetes Engine (GKE).

## Architecture

The application is deployed across multiple services:
- **PostgreSQL Database**: Containerized PostgreSQL with persistent storage.
- **Auth API**: Authentication service (2 replicas, HPA-ready).
- **Tasks API**: Task management service (2 replicas, HPA-ready).
- **Frontend**: Nginx-based frontend (2 replicas).
- **Ingress**: Path-based routing to services via Google Cloud Load Balancer.

## Prerequisites

1. **GKE Cluster**:
   ```bash
   gcloud container clusters create task-app-cluster \
     --zone us-central1-c \
     --num-nodes 3 \
     --machine-type e2-medium
   ```

2. **kubectl context**:
   ```bash
   gcloud container clusters get-credentials task-app-cluster --zone us-central1-c
   ```

3. **Built Images**: Images must be present in Artifact Registry (handled by CI pipeline).
   - `.../task-app-repo/auth-api:latest`
   - `.../task-app-repo/tasks-api:latest`
   - `.../task-app-repo/frontend:latest`

## Deployment Methods

### A. Automatic Deployment (Recommended)
Use the **GitHub Actions workflow** (`Deploy to GKE`). This will:
1. Update image tags to the deployed version.
2. Apply all secrets and manifests.
3. Wait for rollout completion.

### B. Manual Deployment

If you need to deploy manually:

#### 1. Namespace
```bash
kubectl apply -f namespace.yml
```

#### 2. Secrets
Create the required secrets. Replace placeholders with actual values:

```bash
# Database Secrets
kubectl create secret generic db-credentials \
  --from-literal=POSTGRES_USER=postgres \
  --from-literal=POSTGRES_PASSWORD='YOUR_DB_PASSWORD' \
  --from-literal=POSTGRES_DB=tasksdb \
  --namespace=task-app

# Service Secrets (Auth & Tasks API)
kubectl create secret generic auth-api-secrets \
  --from-literal=JWT_SECRET_KEY='YOUR_JWT_SECRET' \
  --from-literal=DB_USER=postgres \
  --from-literal=DB_PASSWORD='YOUR_DB_PASSWORD' \
  --from-literal=DB_HOST=db \
  --from-literal=DB_NAME=tasksdb \
  --namespace=task-app

kubectl create secret generic tasks-api-secrets \
  --from-literal=JWT_SECRET_KEY='YOUR_JWT_SECRET' \
  --from-literal=DB_USER=postgres \
  --from-literal=DB_PASSWORD='YOUR_DB_PASSWORD' \
  --from-literal=DB_HOST=db \
  --from-literal=DB_NAME=tasksdb \
  --namespace=task-app
```

#### 3. Update Image References
Edit `auth-api.yml`, `tasks-api.yml`, and `frontend.yml`.
Replace `PROJECT_ID` in the image path with your actual GCP Project ID.

#### 4. Apply Manifests
```bash
kubectl apply -f database.yml
kubectl apply -f auth-api.yml
kubectl apply -f tasks-api.yml
kubectl apply -f frontend.yml
kubectl apply -f ingress.yml
```

## Monitoring

Check the status of your rollout:

```bash
kubectl get pods -n task-app
kubectl get ingress -n task-app
```

Access the application via the EXTERNAL-IP provided by the Ingress (this may take a few minutes to provision).
