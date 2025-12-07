#!/usr/bin/env pwsh
# =================================================================================================
# SCRIPT: Local Kubernetes Deployment (Podman)
# =================================================================================================
# WELCOME STUDENTS!
# This PowerShell script allows you to run your Kubernetes application LOCALLY on your laptop.
# It simulates a Kubernetes environment using 'Podman', which is an alternative to Docker.
#
# CHALLENGE:
# In a real cluster (GKE), we have DNS (e.g., http://auth-api resolves automatically).
# In Podman's basic "kube play" mode, we don't have a full DNS server.
#
# SOLUTION:
# This script does some "Magic" to fix this:
# 1. It deploys the Database first and finds its IP address.
# 2. It injects that IP address into the configurations of the other services.
# 3. It edits the Manifests on-the-fly to remove cloud-specific settings (like GCP Identity).
#
# USAGE:
#   .\scripts\local-k8s-deploy.ps1             # Build images and deploy
#   .\scripts\local-k8s-deploy.ps1 -SkipBuild  # Deploy existing images (faster)
# =================================================================================================

# 'param' defines the command-line arguments this script accepts.
param(
    # [switch] means it's a boolean flag. PASS: -SkipBuild. DEFAULT: False.
    [switch]$SkipBuild
)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Local K8s Deployment with Podman" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# =================================================================================================
# STEP 1: Build Container Images
# =================================================================================================
# Before we can run containers, we must build them from our source code.
# This loop goes through each folder (auth-api, tasks-api, frontend) and runs 'podman build'.
if ($SkipBuild) {
    Write-Host "[1/6] Skipping image build (-SkipBuild specified)..." -ForegroundColor Yellow
}
else {
    Write-Host "[1/6] Building local images..." -ForegroundColor Yellow
    
    # Array of HashTables defining our services
    $images = @(
        @{Name = "auth-api"; Path = "./auth-api" },
        @{Name = "tasks-api"; Path = "./tasks-api" },
        @{Name = "frontend"; Path = "./frontend" }
    )

    foreach ($img in $images) {
        Write-Host "  Building $($img.Name)..." -ForegroundColor Gray
        
        # podman build -t Name:Tag -f Dockerfile Path
        podman build -t "$($img.Name):latest" -f "$($img.Path)/Dockerfile" $img.Path
        
        # Check for errors ($LASTEXITCODE is 0 if success, non-zero if error)
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  ERROR: Failed to build $($img.Name)" -ForegroundColor Red
            exit 1 # Stop the script immediately
        }
    }
}

# =================================================================================================
# STEP 2: Setup Workspace
# =================================================================================================
Write-Host "[2/6] Processing k8s manifests for local deployment..." -ForegroundColor Yellow

$manifestsDir = "k8s-manifests"
# We create a temporary hidden folder to store our modified YAML files.
# We don't want to modify the REAL files in 'k8s-manifests/' because those are for Production!
$tempDir = "scripts/.tmp-manifests"

New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

# HELPER FUNCTION: Get-PodIP
# Gets the internal IP address of a running Podman container.
# We need this because we don't have a DNS server.
function Get-PodIP {
    param([string]$PodName)
    # 1. Get the ID of the "Infra Container" (the network holder for the pod)
    $infraId = podman pod inspect $PodName --format "{{.InfraContainerID}}" 2>$null
    if ($infraId) {
        # 2. Inspect that container to find its IP address
        $ip = podman inspect $infraId --format "{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}" 2>$null
        return $ip.Trim()
    }
    return $null
}

# HELPER FUNCTION: Wait-ForPod
# Loops until a pod status becomes "Running".
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

# =================================================================================================
# STEP 3: Deploy Database
# =================================================================================================
# We deploy the DB first because the APIs need its IP address to connect.
Write-Host "[3/6] Deploying database..." -ForegroundColor Yellow

$dbSourcePath = Join-Path $manifestsDir "database.yml"
$dbTempPath = Join-Path $tempDir "database.yml"

# Read the Manifest
$dbContent = Get-Content $dbSourcePath -Raw

# MODIFICATION: Remove 'namespace: task-app'
# Podman 'kube play' doesn't support Namespaces well in local mode.
# regex: (?m) enables multiline mode. ^ start of line. \r? windows comaptibility.
$dbContent = $dbContent -replace '(?m)^  namespace: task-app\r?\n', ''

# Save modified file
$dbContent | Set-Content $dbTempPath -NoNewline

# Deploy!
Write-Host "  Deploying database.yml..." -ForegroundColor Gray
podman kube play $dbTempPath

# Wait for it to be ready
Write-Host "  Waiting for database pod..." -ForegroundColor Gray
if (-not (Wait-ForPod -PodName "db-pod" -TimeoutSeconds 60)) {
    Write-Host "  ERROR: Database pod did not start in time" -ForegroundColor Red
    exit 1
}

# Find its IP
$dbIP = Get-PodIP -PodName "db-pod"
Write-Host "  Database pod IP: $dbIP" -ForegroundColor Green

# =================================================================================================
# STEP 4: Deploy APIs (Auth & Tasks)
# =================================================================================================
Write-Host "[4/6] Deploying API services..." -ForegroundColor Yellow

$apiFiles = @("auth-api.yml", "tasks-api.yml")
foreach ($file in $apiFiles) {
    $sourcePath = Join-Path $manifestsDir $file
    $tempPath = Join-Path $tempDir $file
    
    $content = Get-Content $sourcePath -Raw

    # MODIFICATION 1: Change Image Path
    # Cloud: us-central1-docker.pkg.dev/...
    # Local: localhost/auth-api:latest
    $content = $content -replace 'us-central1-docker.pkg.dev/PROJECT_ID/task-app-repo/auth-api:latest', 'localhost/auth-api:latest'
    $content = $content -replace 'us-central1-docker.pkg.dev/PROJECT_ID/task-app-repo/tasks-api:latest', 'localhost/tasks-api:latest'

    # MODIFICATION 2: Image Pull Policy
    # Cloud: Always (Check for updates)
    # Local: Never (Use the image I just built on my machine)
    $content = $content -replace 'imagePullPolicy: Always', 'imagePullPolicy: Never'

    # MODIFICATION 3: Inject DB IP
    # The manifests say "DB_HOST: db". We verify that doesn't work locally.
    # We replace it with the actual IP: "DB_HOST: 10.88.0.2"
    $content = $content -replace 'DB_HOST: db', "DB_HOST: $dbIP"

    # Remove namespace
    $content = $content -replace '(?m)^  namespace: task-app\r?\n', ''

    $content | Set-Content $tempPath -NoNewline
    podman kube play $tempPath
}

# Wait for APIs
Wait-ForPod -PodName "auth-api-pod" | Out-Null
Wait-ForPod -PodName "tasks-api-pod" | Out-Null

$authApiIP = Get-PodIP -PodName "auth-api-pod"
$tasksApiIP = Get-PodIP -PodName "tasks-api-pod"

Write-Host "  Auth API pod IP: $authApiIP" -ForegroundColor Green
Write-Host "  Tasks API pod IP: $tasksApiIP" -ForegroundColor Green

# =================================================================================================
# STEP 5: Deploy Frontend
# =================================================================================================
Write-Host "[5/6] Deploying frontend..." -ForegroundColor Yellow

$frontendSourcePath = Join-Path $manifestsDir "frontend.yml"
$frontendTempPath = Join-Path $tempDir "frontend.yml"
$frontendContent = Get-Content $frontendSourcePath -Raw

# Standard modifications (Image path, Pull Policy, Namespace)
$frontendContent = $frontendContent -replace 'us-central1-docker.pkg.dev/PROJECT_ID/task-app-repo/frontend:latest', 'localhost/frontend:latest'
$frontendContent = $frontendContent -replace 'imagePullPolicy: Always', 'imagePullPolicy: Never'
$frontendContent = $frontendContent -replace '(?m)^  namespace: task-app\r?\n', ''

# SPECIAL MODIFICATION: Service Discovery
# The frontend (Nginx) needs to proxy requests to the APIs.
# We inject the IP addresses we found earlier.
$frontendContent = $frontendContent -replace 'http://auth-api:8000/', "http://${authApiIP}:8000/"
$frontendContent = $frontendContent -replace 'http://tasks-api:8000/', "http://${tasksApiIP}:8000/"

# SPECIAL MODIFICATION: Expose Port
# In Cloud, 'ClusterIP' is fine because Ingress handles external traffic.
# Locally, we change it to 'LoadBalancer' or just rely on 'podman kube play --publish'.
# Here we change the type just in case.
$frontendContent = $frontendContent -replace 'type: ClusterIP', 'type: LoadBalancer'

$frontendContent | Set-Content $frontendTempPath -NoNewline

# --publish 8080:80 maps localhost:8080 -> Container Port 80
podman kube play --publish 8080:80 $frontendTempPath

Write-Host "  Frontend deployed" -ForegroundColor Green

# =================================================================================================
# STEP 6: Cleanup
# =================================================================================================
# We delete the temporary modified files so we don't clutter the disk.
Write-Host "[6/6] Cleaning up temporary files..." -ForegroundColor Yellow
Remove-Item -Recurse -Force $tempDir -ErrorAction SilentlyContinue

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Deployment Complete!" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Frontend URL: " -NoNewline
Write-Host "http://localhost:8080" -ForegroundColor Green
Write-Host ""
Write-Host "To tear down deployment:" -ForegroundColor Gray
Write-Host "  .\scripts\local-k8s-down.ps1" -ForegroundColor White
