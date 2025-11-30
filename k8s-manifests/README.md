# GKE Kubernetes Manifests

This directory contains Kubernetes manifests for deploying the task management application to Google Kubernetes Engine (GKE).

## Architecture

The application is deployed across multiple services:
- **PostgreSQL Database**: Containerized PostgreSQL with persistent storage
- **Auth API**: Authentication service (2 replicas)
- **Tasks API**: Task management service (2 replicas)
- **Frontend**: Nginx-based frontend (2 replicas)
- **Ingress**: Path-based routing to services

## Prerequisites

1. **GKE Cluster**: You need a running GKE cluster
   ```bash
   # Create a cluster (example)
   gcloud container clusters create task-app-cluster \
     --zone us-central1-a \
     --num-nodes 3 \
     --machine-type e2-medium
   ```

2. **kubectl**: Configured to connect to your cluster
   ```bash
   gcloud container clusters get-credentials task-app-cluster --zone us-central1-c
   ```

3. **Container Images**: Images must be built and pushed to Artifact Registry
   - This is handled by the `CI.yml` workflow

4. **GitHub Secrets**: The following secrets must be configured:
   - `GCP_SA_KEY`: Service account key JSON
   - `GCP_PROJECT_ID`: Your GCP project ID
   - `DB_PASSWORD`: PostgreSQL password
   - `JWT_SECRET_KEY`: JWT signing secret
   - `GKE_CLUSTER_NAME`: Name of your GKE cluster
   - `GKE_ZONE`: Zone where your cluster is located

## Manual Deployment

If you want to deploy manually instead of using GitHub Actions:

### 1. Update Image References

Edit the deployment files to replace `PROJECT_ID` with your actual GCP project ID:
```bash
# In auth-api.yml, tasks-api.yml, and frontend.yml
# Replace: us-central1-docker.pkg.dev/PROJECT_ID/task-app-repo/...
# With: us-central1-docker.pkg.dev/YOUR_PROJECT_ID/task-app-repo/...
```

### 2. Create Namespace

```bash
kubectl apply -f namespace.yml
```

### 3. Update Secrets

```bash
# Update database credentials
kubectl create secret generic db-credentials \
  --from-literal=POSTGRES_USER=postgres \
  --from-literal=POSTGRES_PASSWORD=your_secure_password \
  --from-literal=POSTGRES_DB=tasksdb \
  --namespace=task-app \
  --dry-run=client -o yaml | kubectl apply -f -

# Update auth-api secrets
kubectl create secret generic auth-api-secrets \
  --from-literal=JWT_SECRET_KEY=your_jwt_secret \
  --from-literal=DB_USER=postgres \
  --from-literal=DB_PASSWORD=your_secure_password \
  --from-literal=DB_HOST=db \
  --from-literal=DB_NAME=tasksdb \
  --namespace=task-app \
  --dry-run=client -o yaml | kubectl apply -f -

# Update tasks-api secrets
kubectl create secret generic tasks-api-secrets \
  --from-literal=DB_USER=postgres \
  --from-literal=DB_PASSWORD=your_secure_password \
  --from-literal=DB_HOST=db \
  --from-literal=DB_NAME=tasksdb \
  --from-literal=JWT_SECRET_KEY=your_jwt_secret \
  --namespace=task-app \
  --dry-run=client -o yaml | kubectl apply -f -
```

### 4. Deploy Services

```bash
# Deploy in order
kubectl apply -f database.yml
kubectl apply -f auth-api.yml
kubectl apply -f tasks-api.yml
kubectl apply -f frontend.yml
kubectl apply -f ingress.yml
```

### 5. Wait for Deployment

```bash
kubectl wait --for=condition=available --timeout=300s \
  deployment/db deployment/auth-api deployment/tasks-api deployment/frontend \
  --namespace=task-app
```

### 6. Get Ingress IP

```bash
kubectl get ingress task-app-ingress --namespace=task-app
```

The application will be accessible at the EXTERNAL-IP address shown (it may take a few minutes for the IP to be assigned).

## GitHub Actions Deployment

The preferred deployment method is using the GitHub Actions workflow:

1. Go to **Actions** tab in your GitHub repository
2. Select **Deploy to GKE** workflow
3. Click **Run workflow**
4. The workflow will:
   - Use pre-built images from Artifact Registry
   - Deploy to your GKE cluster
   - Update all secrets
   - Apply all manifests

## Monitoring

```bash
# Check pod status
kubectl get pods --namespace=task-app

# Check service status
kubectl get services --namespace=task-app

# Check ingress status
kubectl get ingress --namespace=task-app

# View logs
kubectl logs -f deployment/auth-api --namespace=task-app
kubectl logs -f deployment/tasks-api --namespace=task-app
kubectl logs -f deployment/frontend --namespace=task-app
kubectl logs -f deployment/db --namespace=task-app
```

## Scaling

```bash
# Scale a deployment
kubectl scale deployment/auth-api --replicas=3 --namespace=task-app
kubectl scale deployment/tasks-api --replicas=3 --namespace=task-app
```

## Cleanup

```bash
# Delete all resources
kubectl delete namespace task-app
```

## Differences from Local Deployment

| Feature | Local (podman-deployment.yml) | GKE (k8s-manifests/) |
|---------|------------------------------|----------------------|
| Images | Local builds (`imagePullPolicy: Never`) | Artifact Registry (`imagePullPolicy: Always`) |
| Secrets | Hard-coded in YAML | Kubernetes Secrets |
| Storage | Local volumes | GCE Persistent Disks |
| Replicas | 1 per service | 2 per service (scalable) |
| Health Checks | Basic | HTTP/TCP probes |
| Resource Limits | None | CPU/Memory limits set |
| Access | NodePort (30080) | Ingress with Load Balancer |
