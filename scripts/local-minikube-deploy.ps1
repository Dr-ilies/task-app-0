#!/usr/bin/env pwsh
# =================================================================================================
# SCRIPT: Local Kubernetes using Minikube
# =================================================================================================
# WELCOME STUDENTS!
# "Minikube" is a tool that runs a single-node Kubernetes cluster inside a Virtual Machine (VM)
# or a Docker container.
#
# HOW IS THIS DIFFERENT FROM KIND?
# - Kind = "Kubernetes IN Docker". It's a Docker container acting as a node.
# - Minikube = More mature, supports many drivers (VirtualBox, HyperV, Docker, Podman).
#
# KEY FEATURE: "Minikube Tunnel"
# Minikube has a built-in feature called 'minikube tunnel' that can assign External IPs
# to Services with type=LoadBalancer. This is excellent for testing Ingress.
# =================================================================================================

param(
    [switch]$SkipBuild,      # Skip building container images
    [switch]$SkipCluster     # Skip cluster creation (use existing)
)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Local Minikube Deployment" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$clusterName = "task-app"
$cacheDir = "scripts/.minikube-cache"
$appImages = @(
    @{Name = "auth-api"; BuildPath = "./auth-api" },
    @{Name = "tasks-api"; BuildPath = "./tasks-api" },
    @{Name = "frontend"; BuildPath = "./frontend" }
)

# =================================================================================================
# STEP 1: Prerequisites
# =================================================================================================
Write-Host "[1/5] Checking prerequisites..." -ForegroundColor Yellow

if (-not (Get-Command minikube -ErrorAction SilentlyContinue)) {
    Write-Host "  ERROR: 'minikube' is not installed." -ForegroundColor Red; exit 1
}
if (-not (Get-Command kubectl -ErrorAction SilentlyContinue)) {
    Write-Host "  ERROR: 'kubectl' is not installed." -ForegroundColor Red; exit 1
}
Write-Host "  All tools ready." -ForegroundColor Green
New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null

# =================================================================================================
# STEP 2: Create Cluster
# =================================================================================================
if ($SkipCluster) {
    # Logic to check if cluster exists. If not, force creation.
    Write-Host "[2/5] Checking cluster..." -ForegroundColor Yellow
    $status = minikube status -p $clusterName --format "{{.Host}}" 2>$null
    if (-not $status) { $SkipCluster = $false } # Doesn't exist, create it.
    elseif ($status -ne "Running") { minikube start -p $clusterName } # Stopped, start it.
}

$clusterCreated = $false
if (-not $SkipCluster) {
    Write-Host "[2/5] Creating Minikube cluster..." -ForegroundColor Yellow
    
    # Delete if exists to ensuring fresh start
    $status = minikube status -p $clusterName --format "{{.Host}}" 2>$null
    if ($status) { minikube delete -p $clusterName }

    # START COMMAND:
    # --driver=podman: Use Podman instead of Docker Desktop or VirtualBox.
    # --container-runtime=containerd: Use standard k8s runtime.
    # --ports: Map internal K8s ports to our laptop ports (optional, for direct access).
    minikube start -p $clusterName --driver=podman --container-runtime=containerd --ports=8080:80, 8443:443
    
    if ($LASTEXITCODE -ne 0) { Write-Host "  ERROR: Failed to create cluster" -ForegroundColor Red; exit 1 }
    $clusterCreated = $true
}

# =================================================================================================
# STEP 3: Build Images (In-Cluster)
# =================================================================================================
# Minikube is unique: You can point your shell to Minikube's Docker daemon.
# But since we use Podman driver, we use 'minikube image build'.
# This builds the image DIRECTLY INSIDE the cluster. No need to push/pull!

if (-not $SkipBuild) {
    Write-Host "[3/5] Building images (In-Cluster)..." -ForegroundColor Yellow
    
    foreach ($img in $appImages) {
        Write-Host "  Building $($img.Name)..." -ForegroundColor Gray
        # COMMAND: minikube image build
        # This is strictly for the Minikube environment.
        minikube -p $clusterName image build -t "$($img.Name):latest" $img.BuildPath
    }
}

# =================================================================================================
# STEP 4: Enable Ingress
# =================================================================================================
Write-Host "[4/5] Enabling ingress addon..." -ForegroundColor Yellow

# Minikube has "Addons". These are one-click installs for common features.
# This installs Nginx Ingress Controller automatically.
minikube -p $clusterName addons enable ingress

# Wait for it to be ready
Write-Host "  Waiting for ingress controller..." -ForegroundColor Gray
kubectl wait --namespace ingress-nginx --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=120s 2>$null

# =================================================================================================
# STEP 5: Deploy Application
# =================================================================================================
Write-Host "[5/5] Deploying application..." -ForegroundColor Yellow

$manifestsDir = "k8s-manifests"
$tempDir = Join-Path $cacheDir "manifests"
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

# Namespace
kubectl apply -f (Join-Path $manifestsDir "namespace.yml")

$deployOrder = @("database.yml", "auth-api.yml", "tasks-api.yml", "frontend.yml")
foreach ($file in $deployOrder) {
    $sourcePath = Join-Path $manifestsDir $file
    $tempPath = Join-Path $tempDir $file
    $content = Get-Content $sourcePath -Raw
    
    # MODIFICATION:
    # We use simple tag names: 'auth-api:latest'.
    # Because we built them "In-Cluster", Minikube knows them by this short name.
    $content = $content -replace 'us-central1-docker.pkg.dev/PROJECT_ID/task-app-repo/auth-api:latest', 'auth-api:latest'
    $content = $content -replace 'us-central1-docker.pkg.dev/PROJECT_ID/task-app-repo/tasks-api:latest', 'tasks-api:latest'
    $content = $content -replace 'us-central1-docker.pkg.dev/PROJECT_ID/task-app-repo/frontend:latest', 'frontend:latest'
    
    # CRITICAL: 'imagePullPolicy: Never'
    # "Don't try to pull 'auth-api:latest' from Docker Hub. Use the local one."
    $content = $content -replace 'imagePullPolicy: Always', 'imagePullPolicy: Never'
    
    $content | Set-Content $tempPath -NoNewline
    kubectl apply -f $tempPath
    
    if ($file -eq "database.yml") {
        # Wait for DB
        kubectl wait --namespace task-app --for=condition=ready pod --selector=app=db --timeout=120s 2>$null
    }
}

# Ingress
Write-Host "  Deploying ingress..." -ForegroundColor Gray
$ingressContent = Get-Content (Join-Path $manifestsDir "ingress.yml") -Raw

# Minikube's ingress addon uses 'nginx' class.
$ingressContent = $ingressContent -replace 'kubernetes.io/ingress.class: "gce"', 'kubernetes.io/ingress.class: "nginx"'
$ingressContent = $ingressContent -replace 'ingressClassName: gce', 'ingressClassName: nginx'

$ingressTempPath = Join-Path $tempDir "ingress.yml"
$ingressContent | Set-Content $ingressTempPath -NoNewline

# Retry loop
$retries = 0; $ingressDeployed = $false
while ($retries -lt 12 -and -not $ingressDeployed) {
    kubectl apply -f $ingressTempPath 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) { $ingressDeployed = $true }
    else { Start-Sleep -Seconds 5; $retries++ }
}

# Get Minikube IP
$minikubeIP = minikube -p $clusterName ip 2>$null

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Deployment Complete!" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Access options:" -ForegroundColor Gray
Write-Host "  1. Tunnel (recommended): minikube -p $clusterName tunnel" -ForegroundColor White
Write-Host "     Then access: http://localhost" -ForegroundColor Green
Write-Host ""
Write-Host "  2. Direct IP: http://${minikubeIP}" -ForegroundColor White
