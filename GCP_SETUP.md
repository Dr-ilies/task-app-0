# Google Cloud Platform Setup for CI/CD

This guide walks you through configuring Google Cloud Platform (GCP) for automated deployment via GitHub Actions.

## Prerequisites

- A GCP project
- `gcloud` CLI installed and authenticated
- Owner or Editor role on the GCP project

## 1. Enable Required APIs

First, enable the necessary Google Cloud APIs:

```bash
gcloud services enable run.googleapis.com
gcloud services enable artifactregistry.googleapis.com
gcloud services enable sqladmin.googleapis.com
gcloud services enable cloudresourcemanager.googleapis.com
```

> [!NOTE]
> These commands require you to have sufficient permissions on your GCP project. If you encounter permission errors, ensure you have Owner or Editor role.

## 2. Create Service Account for GitHub Actions

Create a dedicated service account for GitHub Actions deployments:

```bash
# Replace PROJECT_ID with your actual GCP project ID
export PROJECT_ID="your-project-id"

# Create the service account
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

### Alternative: Using Google Cloud Console

If you prefer using the web interface:

1. Go to [IAM & Admin → IAM](https://console.cloud.google.com/iam-admin/iam)
2. Find the service account: `github-actions-deployer@[PROJECT_ID].iam.gserviceaccount.com`
3. Click the **Edit** pencil icon
4. Click **ADD ANOTHER ROLE** and add each of these roles:
   - `Cloud Run Admin`
   - `Service Account User`
   - `Artifact Registry Writer`
   - `Cloud SQL Client`
5. Click **Save**

## 4. Create Service Account Key

Generate a JSON key file for authentication:

```bash
gcloud iam service-accounts keys create gcp-key.json \
    --iam-account=github-actions-deployer@${PROJECT_ID}.iam.gserviceaccount.com
```

> [!CAUTION]
> **Keep this key secure!** It provides access to your GCP resources. Never commit it to version control.

## 5. Add GitHub Secrets

Add the following secrets to your GitHub repository:

1. Go to your GitHub repository
2. Navigate to **Settings** → **Secrets and variables** → **Actions**
3. Click **New repository secret** and add:

| Secret Name | Value | Description |
|------------|-------|-------------|
| `GCP_PROJECT_ID` | Your GCP project ID | Project identifier |
| `GCP_SA_KEY` | Contents of `gcp-key.json` | Service account credentials |
| `DB_PASSWORD` | Your database password | PostgreSQL password |
| `JWT_SECRET_KEY` | Your JWT secret | Authentication secret key |
| `INSTANCE_CONNECTION_NAME` | `PROJECT:REGION:INSTANCE` | Cloud SQL connection string |

> [!TIP]
> For `INSTANCE_CONNECTION_NAME`, use format: `your-project:us-central1:your-db-instance`

## 6. Create Artifact Registry Repository

Create a Docker repository in Artifact Registry:

```bash
gcloud artifacts repositories create task-app-repo \
    --repository-format=docker \
    --location=us-central1 \
    --description="Docker images for task app" \
    --project=$PROJECT_ID
```

## 7. Set Up Cloud SQL (If Not Already Done)

If you haven't created a Cloud SQL instance:

```bash
# Create Cloud SQL instance
gcloud sql instances create tasksdb-instance \
    --database-version=POSTGRES_15 \
    --tier=db-f1-micro \
    --region=us-central1 \
    --project=$PROJECT_ID

# Create database
gcloud sql databases create tasksdb \
    --instance=tasksdb-instance \
    --project=$PROJECT_ID

# Set root password
gcloud sql users set-password postgres \
    --instance=tasksdb-instance \
    --password=YOUR_SECURE_PASSWORD \
    --project=$PROJECT_ID
```

## Verification

To verify your setup:

1. **Check IAM roles**:
   ```bash
   gcloud projects get-iam-policy $PROJECT_ID \
       --flatten="bindings[].members" \
       --filter="bindings.members:serviceAccount:github-actions-deployer@${PROJECT_ID}.iam.gserviceaccount.com"
   ```

2. **Check enabled APIs**:
   ```bash
   gcloud services list --enabled --project=$PROJECT_ID | grep -E 'run|artifact|sql'
   ```

3. **Test deployment**: Push a commit to your `main` branch and monitor the GitHub Actions workflow.

## Troubleshooting

### Permission Denied Errors

If you see "Permission denied to enable service" errors:
- Ensure all APIs are enabled (Step 1)
- Verify service account has all required roles (Step 3)
- Check that GitHub secrets are correctly configured (Step 5)

### Authentication Failures

If authentication fails:
- Verify `GCP_SA_KEY` secret contains the complete JSON key
- Ensure the service account key is valid and not expired
- Check that the project ID in secrets matches your actual project

### Database Connection Issues

If Cloud Run services can't connect to the database:
- Verify `INSTANCE_CONNECTION_NAME` is correct
- Ensure Cloud SQL Admin API is enabled
- Check that the service account has `Cloud SQL Client` role

## Security Best Practices

> [!WARNING]
> **Production Recommendations**:
> - Rotate service account keys regularly
> - Use least-privilege IAM roles
> - Enable VPC Service Controls for additional security
> - Use Secret Manager instead of environment variables for sensitive data
> - Implement Cloud Armor for DDoS protection

## Clean Up

To delete the service account key after rotating:

```bash
# List keys
gcloud iam service-accounts keys list \
    --iam-account=github-actions-deployer@${PROJECT_ID}.iam.gserviceaccount.com

# Delete a specific key
gcloud iam service-accounts keys delete KEY_ID \
    --iam-account=github-actions-deployer@${PROJECT_ID}.iam.gserviceaccount.com
```

## Additional Resources

- [Cloud Run Documentation](https://cloud.google.com/run/docs)
- [IAM Roles Reference](https://cloud.google.com/iam/docs/understanding-roles)
- [Artifact Registry Documentation](https://cloud.google.com/artifact-registry/docs)
- [Cloud SQL Documentation](https://cloud.google.com/sql/docs)
