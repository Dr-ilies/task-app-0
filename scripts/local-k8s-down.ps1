#!/usr/bin/env pwsh
# Tear down Local Kubernetes Deployment
# This script removes all pods and resources created by local-k8s-deploy.ps1

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Tearing Down Local K8s Deployment" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$manifestsDir = "k8s-manifests"
$tempDir = "scripts/.tmp-manifests"

# Create temp directory
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

# Files to process (reverse order for teardown)
$deployOrder = @("frontend.yml", "tasks-api.yml", "auth-api.yml", "database.yml")
$skipFiles = @("namespace.yml", "ingress.yml")

Write-Host "Processing manifests for teardown..." -ForegroundColor Yellow
Write-Host ""

foreach ($file in $deployOrder) {
    if ($skipFiles -contains $file) {
        continue
    }

    $sourcePath = Join-Path $manifestsDir $file
    $tempPath = Join-Path $tempDir $file

    Write-Host "  Stopping $file..." -ForegroundColor Gray

    # Read and modify manifest (same as deploy script)
    $content = Get-Content $sourcePath -Raw

    # Replace GCR image paths with local tags
    $content = $content -replace 'us-central1-docker.pkg.dev/PROJECT_ID/task-app-repo/auth-api:latest', 'localhost/auth-api:latest'
    $content = $content -replace 'us-central1-docker.pkg.dev/PROJECT_ID/task-app-repo/tasks-api:latest', 'localhost/tasks-api:latest'
    $content = $content -replace 'us-central1-docker.pkg.dev/PROJECT_ID/task-app-repo/frontend:latest', 'localhost/frontend:latest'

    # Change imagePullPolicy to Never
    $content = $content -replace 'imagePullPolicy: Always', 'imagePullPolicy: Never'

    # For frontend, change Service type to LoadBalancer
    if ($file -eq "frontend.yml") {
        $content = $content -replace 'type: ClusterIP', 'type: LoadBalancer'
    }

    # Remove namespace references
    $content = $content -replace '(?m)^  namespace: task-app\r?\n', ''

    # Save modified manifest
    $content | Set-Content $tempPath -NoNewline

    # Tear down
    podman kube down $tempPath 2>$null

    Start-Sleep -Seconds 1
}

Write-Host ""
Write-Host "Cleaning up volumes..." -ForegroundColor Yellow

# List and remove volumes created by the deployment
$volumes = podman volume ls --filter "name=postgres" --format "{{.Name}}"
if ($volumes) {
    foreach ($vol in $volumes) {
        Write-Host "  Removing volume: $vol" -ForegroundColor Gray
        podman volume rm $vol -f 2>$null
    }
}

Write-Host ""
Write-Host "Cleaning up temporary files..." -ForegroundColor Yellow
Remove-Item -Recurse -Force $tempDir -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Teardown Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "To verify cleanup:" -ForegroundColor Gray
Write-Host "  podman pod ps" -ForegroundColor White
Write-Host "  podman volume ls" -ForegroundColor White
Write-Host ""
