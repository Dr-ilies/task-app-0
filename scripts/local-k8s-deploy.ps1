#!/usr/bin/env pwsh
# Local Kubernetes Deployment with Podman
# This script deploys the application using k8s-manifests with local modifications
# It handles service name resolution by injecting pod IPs

param(
    [switch]$SkipBuild  # Skip building images if they already exist
)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Local K8s Deployment with Podman" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Step 1: Build local images (unless -SkipBuild is specified)
if ($SkipBuild) {
    Write-Host "[1/6] Skipping image build (-SkipBuild specified)..." -ForegroundColor Yellow
    Write-Host "  Using existing images: auth-api:latest, tasks-api:latest, frontend:latest" -ForegroundColor Gray
    Write-Host ""
}
else {
    Write-Host "[1/6] Building local images..." -ForegroundColor Yellow
    Write-Host ""

    $images = @(
        @{Name = "auth-api"; Path = "./auth-api" },
        @{Name = "tasks-api"; Path = "./tasks-api" },
        @{Name = "frontend"; Path = "./frontend" }
    )

    foreach ($img in $images) {
        Write-Host "  Building $($img.Name)..." -ForegroundColor Gray
        podman build -t "$($img.Name):latest" -f "$($img.Path)/Dockerfile" $img.Path
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  ERROR: Failed to build $($img.Name)" -ForegroundColor Red
            exit 1
        }
    }

    Write-Host "  All images built successfully" -ForegroundColor Green
    Write-Host ""
}

# Step 2: Process and deploy manifests
Write-Host "[2/6] Processing k8s manifests for local deployment..." -ForegroundColor Yellow
Write-Host ""

$manifestsDir = "k8s-manifests"
$tempDir = "scripts/.tmp-manifests"

# Create temp directory
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

# Files to skip (not supported by Podman)
$skipFiles = @("namespace.yml", "ingress.yml")

# Helper function to get pod IP
function Get-PodIP {
    param([string]$PodName)
    $infraId = podman pod inspect $PodName --format "{{.InfraContainerID}}" 2>$null
    if ($infraId) {
        # Podman kube network uses a different network name
        $ip = podman inspect $infraId --format "{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}" 2>$null
        return $ip.Trim()
    }
    return $null
}

# Helper function to wait for pod to be ready
function Wait-ForPod {
    param([string]$PodName, [int]$TimeoutSeconds = 60)
    $elapsed = 0
    while ($elapsed -lt $TimeoutSeconds) {
        $status = podman pod ps --filter "name=$PodName" --format "{{.Status}}" 2>$null
        if ($status -match "Running") {
            return $true
        }
        Start-Sleep -Seconds 2
        $elapsed += 2
    }
    return $false
}

# Step 3: Deploy database first to get its IP
Write-Host "[3/6] Deploying database..." -ForegroundColor Yellow
Write-Host ""

$dbSourcePath = Join-Path $manifestsDir "database.yml"
$dbTempPath = Join-Path $tempDir "database.yml"

# Process database manifest
$dbContent = Get-Content $dbSourcePath -Raw
$dbContent = $dbContent -replace '(?m)^  namespace: task-app\r?\n', ''
$dbContent | Set-Content $dbTempPath -NoNewline

Write-Host "  Deploying database.yml..." -ForegroundColor Gray
podman kube play $dbTempPath
if ($LASTEXITCODE -ne 0) {
    Write-Host "  ERROR: Failed to deploy database" -ForegroundColor Red
    Remove-Item -Recurse -Force $tempDir -ErrorAction SilentlyContinue
    exit 1
}

# Wait for database pod to be ready
Write-Host "  Waiting for database pod..." -ForegroundColor Gray
if (-not (Wait-ForPod -PodName "db-pod" -TimeoutSeconds 60)) {
    Write-Host "  ERROR: Database pod did not start in time" -ForegroundColor Red
    exit 1
}

# Get database pod IP
$dbIP = Get-PodIP -PodName "db-pod"
if (-not $dbIP) {
    Write-Host "  ERROR: Could not get database pod IP" -ForegroundColor Red
    exit 1
}
Write-Host "  Database pod IP: $dbIP" -ForegroundColor Green
Write-Host ""

# Step 4: Deploy auth-api and tasks-api with correct DB_HOST
Write-Host "[4/6] Deploying API services..." -ForegroundColor Yellow
Write-Host ""

$apiFiles = @("auth-api.yml", "tasks-api.yml")
foreach ($file in $apiFiles) {
    $sourcePath = Join-Path $manifestsDir $file
    $tempPath = Join-Path $tempDir $file

    Write-Host "  Processing $file..." -ForegroundColor Gray

    $content = Get-Content $sourcePath -Raw

    # Replace GCR image paths with local tags
    $content = $content -replace 'us-central1-docker.pkg.dev/PROJECT_ID/task-app-repo/auth-api:latest', 'localhost/auth-api:latest'
    $content = $content -replace 'us-central1-docker.pkg.dev/PROJECT_ID/task-app-repo/tasks-api:latest', 'localhost/tasks-api:latest'

    # Change imagePullPolicy to Never
    $content = $content -replace 'imagePullPolicy: Always', 'imagePullPolicy: Never'

    # Replace DB_HOST: db with actual IP
    $content = $content -replace 'DB_HOST: db', "DB_HOST: $dbIP"

    # Remove namespace references
    $content = $content -replace '(?m)^  namespace: task-app\r?\n', ''

    $content | Set-Content $tempPath -NoNewline

    Write-Host "  Deploying $file..." -ForegroundColor Gray
    podman kube play $tempPath
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  ERROR: Failed to deploy $file" -ForegroundColor Red
        Remove-Item -Recurse -Force $tempDir -ErrorAction SilentlyContinue
        exit 1
    }
}

# Wait for API pods to be ready
Write-Host "  Waiting for API pods..." -ForegroundColor Gray
Wait-ForPod -PodName "auth-api-pod" -TimeoutSeconds 60 | Out-Null
Wait-ForPod -PodName "tasks-api-pod" -TimeoutSeconds 60 | Out-Null

# Get API pod IPs
$authApiIP = Get-PodIP -PodName "auth-api-pod"
$tasksApiIP = Get-PodIP -PodName "tasks-api-pod"

if (-not $authApiIP -or -not $tasksApiIP) {
    Write-Host "  ERROR: Could not get API pod IPs" -ForegroundColor Red
    exit 1
}

Write-Host "  Auth API pod IP: $authApiIP" -ForegroundColor Green
Write-Host "  Tasks API pod IP: $tasksApiIP" -ForegroundColor Green
Write-Host ""

# Step 5: Deploy frontend with correct API URLs
Write-Host "[5/6] Deploying frontend..." -ForegroundColor Yellow
Write-Host ""

$frontendSourcePath = Join-Path $manifestsDir "frontend.yml"
$frontendTempPath = Join-Path $tempDir "frontend.yml"

$frontendContent = Get-Content $frontendSourcePath -Raw

# Replace GCR image path with local tag
$frontendContent = $frontendContent -replace 'us-central1-docker.pkg.dev/PROJECT_ID/task-app-repo/frontend:latest', 'localhost/frontend:latest'

# Change imagePullPolicy to Never
$frontendContent = $frontendContent -replace 'imagePullPolicy: Always', 'imagePullPolicy: Never'

# Replace service URLs with pod IPs
$frontendContent = $frontendContent -replace 'http://auth-api:8000/', "http://${authApiIP}:8000/"
$frontendContent = $frontendContent -replace 'http://tasks-api:8000/', "http://${tasksApiIP}:8000/"

# Change Service type to LoadBalancer
$frontendContent = $frontendContent -replace 'type: ClusterIP', 'type: LoadBalancer'

# Remove namespace references
$frontendContent = $frontendContent -replace '(?m)^  namespace: task-app\r?\n', ''

$frontendContent | Set-Content $frontendTempPath -NoNewline

Write-Host "  Deploying frontend.yml..." -ForegroundColor Gray
podman kube play --publish 8080:80 $frontendTempPath
if ($LASTEXITCODE -ne 0) {
    Write-Host "  ERROR: Failed to deploy frontend" -ForegroundColor Red
    Remove-Item -Recurse -Force $tempDir -ErrorAction SilentlyContinue
    exit 1
}

Write-Host "  Frontend deployed" -ForegroundColor Green
Write-Host ""

# Step 6: Cleanup and display status
Write-Host "[6/6] Cleaning up temporary files..." -ForegroundColor Yellow
Remove-Item -Recurse -Force $tempDir -ErrorAction SilentlyContinue
Write-Host "  Cleanup complete" -ForegroundColor Green
Write-Host ""

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Deployment Complete!" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Pod IPs:" -ForegroundColor Gray
Write-Host "  Database:   $dbIP" -ForegroundColor White
Write-Host "  Auth API:   $authApiIP" -ForegroundColor White
Write-Host "  Tasks API:  $tasksApiIP" -ForegroundColor White
Write-Host ""
Write-Host "Frontend URL: " -NoNewline
Write-Host "http://localhost:8080" -ForegroundColor Green
Write-Host ""
Write-Host "To view running pods:" -ForegroundColor Gray
Write-Host "  podman pod ps" -ForegroundColor White
Write-Host ""
Write-Host "To view logs:" -ForegroundColor Gray
Write-Host "  podman logs -f <container-name>" -ForegroundColor White
Write-Host ""
Write-Host "To tear down deployment:" -ForegroundColor Gray
Write-Host "  .\scripts\local-k8s-down.ps1" -ForegroundColor White
Write-Host ""
