# Google Cloud Platform Setup for CI/CD

This guide walks you through configuring Google Cloud Platform (GCP) for automated deployment via GitHub Actions. It supports both **Cloud Run** and **Google Kubernetes Engine (GKE)**.

## Prerequisites

- A GCP project
- `gcloud` CLI installed and authenticated
- Owner or Editor role on the GCP project

## 1. Enable Required APIs

Enable the necessary Google Cloud APIs for both Cloud Run and GKE:

```bash
gcloud services enable run.googleapis.com \
    artifactregistry.googleapis.com \
    sqladmin.googleapis.com \
    cloudresourcemanager.googleapis.com \
    container.googleapis.com
```

## 2. Create Service Account for GitHub Actions

Create a dedicated service account for deployments:

```bash
export PROJECT_ID="your-project-id"

gcloud iam service-accounts create github-actions-deployer \
    --display-name="GitHub Actions Deploy" \
    --description="Service account for deploying from GitHub Actions" \
    --project=$PROJECT_ID
```

## 3. Grant Required IAM Roles

Grant the necessary roles to the service account:

```bash
# Cloud Run Admin - Deploy and manage Cloud Run services
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:github-actions-deployer@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role="roles/run.admin"

# Kubernetes Engine Developer - Deploy to GKE
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:github-actions-deployer@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role="roles/container.developer"

# Service Account User - Act as service accounts
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:github-actions-deployer@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role="roles/iam.serviceAccountUser"

# Artifact Registry Writer - Push Docker images
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:github-actions-deployer@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role="roles/artifactregistry.writer"

# Cloud SQL Client - Connect to Cloud SQL databases
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:github-actions-deployer@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role="roles/cloudsql.client"
```

## 4. Create Service Account Key

Generate a JSON key file for authentication:

```bash
gcloud iam service-accounts keys create gcp-key.json \
    --iam-account=github-actions-deployer@${PROJECT_ID}.iam.gserviceaccount.com
```

> [!CAUTION]
> **Keep this key secure!** It provides access to your GCP resources. Never commit it to version control.

## 5. Resources Setup

### 5.1 Artifact Registry
Create a Docker repository:
```bash
gcloud artifacts repositories create task-app-repo \
    --repository-format=docker \
    --location=us-central1 \
    --description="Docker images for task app" \
    --project=$PROJECT_ID
```

### 5.2 Cloud SQL
Create a PostgreSQL instance:
```bash
gcloud sql instances create tasksdb-instance \
    --database-version=POSTGRES_15 \
    --tier=db-f1-micro \
    --region=us-central1 \
    --project=$PROJECT_ID

gcloud sql databases create tasksdb --instance=tasksdb-instance --project=$PROJECT_ID
gcloud sql users set-password postgres --instance=tasksdb-instance --password=YOUR_SECURE_PASSWORD --project=$PROJECT_ID
```

### 5.3 GKE Cluster (For GKE Deployment)
Create a cluster if deploying to Kubernetes:
```bash
gcloud container clusters create task-app-cluster \
    --zone us-central1-c \
    --num-nodes 3 \
    --machine-type e2-medium \
    --project=$PROJECT_ID
```

## 6. GitHub Secrets

Add the following secrets to your GitHub repository (**Settings** → **Secrets and variables** → **Actions**):

### Common Secrets
| Secret Name | Description | Example Value |
|------------|-------------|---------------|
| `GCP_PROJECT_ID` | Your GCP Project ID | `my-gcp-project` |
| `GCP_SA_KEY` | Content of `gcp-key.json` | `{ "type": "service_account"... }` |
| `DB_PASSWORD` | Cloud SQL/Postgres Password | `superSecurePwd123!` |
| `JWT_SECRET_KEY` | Secret for JWT signing | `randomLongString` |

### Cloud Run Specific
| Secret Name | Description | Example Value |
|------------|-------------|---------------|
| `INSTANCE_CONNECTION_NAME` | Cloud SQL connection name | `project:region:instance` |

### GKE Specific
| Secret Name | Description | Example Value |
|------------|-------------|---------------|
| `GKE_CLUSTER_NAME` | Name of your GKE cluster | `task-app-cluster` |
| `GKE_ZONE` | Zone of your GKE cluster | `us-central1-c` |

## Verification

To verify your setup:

1. **Check IAM roles**:
   ```bash
   gcloud projects get-iam-policy $PROJECT_ID \
       --flatten="bindings[].members" \
       --filter="bindings.members:serviceAccount:github-actions-deployer@${PROJECT_ID}.iam.gserviceaccount.com"
   ```

2. **Check GKE Access** (if using GKE):
   ```bash
   gcloud container clusters get-credentials task-app-cluster --zone us-central1-c
   kubectl get nodes
   ```

3. **Test Deployment**: Push to `main` (for GCR) or trigger the "Deploy to GKE" workflow manually.
