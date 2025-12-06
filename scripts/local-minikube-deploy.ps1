#!/usr/bin/env pwsh
# Local Kubernetes Deployment with Minikube
# This script creates a Minikube cluster and deploys the application
# using the k8s-manifests with full Kubernetes DNS support

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
    @{Name = "auth-api"; PodmanTag = "localhost/auth-api:latest"; TarName = "auth-api.tar" },
    @{Name = "tasks-api"; PodmanTag = "localhost/tasks-api:latest"; TarName = "tasks-api.tar" },
    @{Name = "frontend"; PodmanTag = "localhost/frontend:latest"; TarName = "frontend.tar" }
)

# Step 1: Check prerequisites
Write-Host "[1/6] Checking prerequisites..." -ForegroundColor Yellow

if (-not (Get-Command minikube -ErrorAction SilentlyContinue)) {
    Write-Host "  ERROR: 'minikube' is not installed. Install from: https://minikube.sigs.k8s.io/" -ForegroundColor Red
    exit 1
}
Write-Host "  minikube: OK" -ForegroundColor Green

if (-not (Get-Command kubectl -ErrorAction SilentlyContinue)) {
    Write-Host "  ERROR: 'kubectl' is not installed." -ForegroundColor Red
    exit 1
}
Write-Host "  kubectl: OK" -ForegroundColor Green

if (-not (Get-Command podman -ErrorAction SilentlyContinue)) {
    Write-Host "  ERROR: 'podman' is not installed." -ForegroundColor Red
    exit 1
}
Write-Host "  podman: OK" -ForegroundColor Green
Write-Host ""

# Ensure cache directory exists
New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null

# Step 2: Build and cache images
if ($SkipBuild) {
    Write-Host "[2/6] Skipping image build (-SkipBuild specified)..." -ForegroundColor Yellow
    
    # Verify cached images exist
    $missingCache = @()
    foreach ($img in $appImages) {
        $tarPath = Join-Path $cacheDir $img.TarName
        if (-not (Test-Path $tarPath)) {
            $missingCache += $img.Name
        }
    }
    
    if ($missingCache.Count -gt 0) {
        Write-Host "  ERROR: Missing cached images: $($missingCache -join ', ')" -ForegroundColor Red
        Write-Host "  Run without -SkipBuild to build and cache images." -ForegroundColor Yellow
        exit 1
    }
    Write-Host "  All app images cached" -ForegroundColor Green
    Write-Host ""
}
else {
    Write-Host "[2/6] Building and caching container images..." -ForegroundColor Yellow
    Write-Host ""

    $buildPaths = @{
        "auth-api"  = "./auth-api"
        "tasks-api" = "./tasks-api"
        "frontend"  = "./frontend"
    }

    foreach ($img in $appImages) {
        $tarPath = Join-Path $cacheDir $img.TarName
        
        Write-Host "  Building $($img.Name)..." -ForegroundColor Gray
        podman build -t "$($img.Name):latest" -f "$($buildPaths[$img.Name])/Dockerfile" $buildPaths[$img.Name]
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  ERROR: Failed to build $($img.Name)" -ForegroundColor Red
            exit 1
        }
        
        Write-Host "  Caching $($img.Name)..." -ForegroundColor Gray
        podman save $img.PodmanTag -o $tarPath 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  ERROR: Failed to cache $($img.Name)" -ForegroundColor Red
            exit 1
        }
    }
    Write-Host "  All images built and cached" -ForegroundColor Green
    Write-Host ""
}

# Step 3: Create/Start Minikube cluster
if ($SkipCluster) {
    Write-Host "[3/6] Skipping cluster creation (-SkipCluster specified)..." -ForegroundColor Yellow
    
    $status = minikube status -p $clusterName --format "{{.Host}}" 2>$null
    if ($status -ne "Running") {
        Write-Host "  Starting existing cluster..." -ForegroundColor Gray
        minikube start -p $clusterName
    }
    Write-Host "  Using cluster '$clusterName'" -ForegroundColor Green
    Write-Host ""
}
else {
    Write-Host "[3/6] Creating Minikube cluster..." -ForegroundColor Yellow
    
    # Check if cluster exists
    $status = minikube status -p $clusterName --format "{{.Host}}" 2>$null
    if ($status) {
        Write-Host "  Deleting existing cluster..." -ForegroundColor Gray
        minikube delete -p $clusterName
    }
    
    Write-Host "  Creating cluster '$clusterName' with Podman driver..." -ForegroundColor Gray
    # Using 'rootless' extra config to help with some podman networking issues if needed, but standard start usually fine
    minikube start -p $clusterName --driver=podman --container-runtime=containerd --ports=8080:80, 8443:443
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  ERROR: Failed to create Minikube cluster" -ForegroundColor Red
        exit 1
    }
    
    Write-Host "  Cluster created" -ForegroundColor Green
    Write-Host ""
}

# Step 4: Load images into Minikube
Write-Host "[4/6] Loading images into Minikube..." -ForegroundColor Yellow

foreach ($img in $appImages) {
    $tarPath = Join-Path $cacheDir $img.TarName
    Write-Host "  Loading $($img.Name)..." -ForegroundColor Gray
    minikube -p $clusterName image load $tarPath
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  WARNING: Failed to load $($img.Name)" -ForegroundColor Yellow
    }
}

Write-Host "  Images loaded" -ForegroundColor Green
Write-Host ""

# Step 5: Enable ingress addon
Write-Host "[5/6] Enabling ingress addon..." -ForegroundColor Yellow

minikube -p $clusterName addons enable ingress
if ($LASTEXITCODE -ne 0) {
    Write-Host "  WARNING: Failed to enable ingress addon" -ForegroundColor Yellow
}
else {
    Write-Host "  Ingress addon enabled" -ForegroundColor Green
}

# Wait for ingress controller
Write-Host "  Waiting for ingress controller..." -ForegroundColor Gray
kubectl wait --namespace ingress-nginx --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=120s 2>$null

Write-Host ""

# Step 6: Deploy application
Write-Host "[6/6] Deploying application..." -ForegroundColor Yellow
Write-Host ""

$manifestsDir = "k8s-manifests"
$tempDir = Join-Path $cacheDir "manifests"
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

# Deploy namespace
Write-Host "  Deploying namespace..." -ForegroundColor Gray
kubectl apply -f (Join-Path $manifestsDir "namespace.yml")

# Deploy resources
$deployOrder = @("database.yml", "auth-api.yml", "tasks-api.yml", "frontend.yml")

foreach ($file in $deployOrder) {
    $sourcePath = Join-Path $manifestsDir $file
    $tempPath = Join-Path $tempDir $file

    $content = Get-Content $sourcePath -Raw
    $content = $content -replace 'us-central1-docker.pkg.dev/PROJECT_ID/task-app-repo/auth-api:latest', 'localhost/auth-api:latest'
    $content = $content -replace 'us-central1-docker.pkg.dev/PROJECT_ID/task-app-repo/tasks-api:latest', 'localhost/tasks-api:latest'
    $content = $content -replace 'us-central1-docker.pkg.dev/PROJECT_ID/task-app-repo/frontend:latest', 'localhost/frontend:latest'
    $content = $content -replace 'imagePullPolicy: Always', 'imagePullPolicy: Never'
    $content | Set-Content $tempPath -NoNewline

    Write-Host "  Deploying $file..." -ForegroundColor Gray
    kubectl apply -f $tempPath

    if ($file -eq "database.yml") {
        Write-Host "  Waiting for database..." -ForegroundColor Gray
        kubectl wait --namespace task-app --for=condition=ready pod --selector=app=db --timeout=120s 2>$null
    }
}

# Deploy ingress (convert gce to nginx)
Write-Host "  Deploying ingress..." -ForegroundColor Gray
$ingressContent = Get-Content (Join-Path $manifestsDir "ingress.yml") -Raw
$ingressContent = $ingressContent -replace 'kubernetes.io/ingress.class: "gce"', 'kubernetes.io/ingress.class: "nginx"'
$ingressContent = $ingressContent -replace 'ingressClassName: gce', 'ingressClassName: nginx'
$ingressTempPath = Join-Path $tempDir "ingress.yml"
$ingressContent | Set-Content $ingressTempPath -NoNewline

$retries = 0
$ingressDeployed = $false
while ($retries -lt 12 -and -not $ingressDeployed) {
    kubectl apply -f $ingressTempPath 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        
        # Verify ingress was actually created
        Start-Sleep -Seconds 2
        $ingressExists = kubectl get ingress -n task-app task-app-ingress -o name 2>$null
        if ($ingressExists) {
            $ingressDeployed = $true
            Write-Host "  Ingress deployed and verified" -ForegroundColor Green
        }
    }
    if (-not $ingressDeployed) {
        $retries++
        Start-Sleep -Seconds 5
    }
}

# Cleanup
Remove-Item -Recurse -Force $tempDir -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "  Waiting for pods..." -ForegroundColor Gray
kubectl wait --namespace task-app --for=condition=ready pod --all --timeout=180s 2>$null

Write-Host ""
kubectl get pods -n task-app

# Get Minikube IP for access
$minikubeIP = minikube -p $clusterName ip 2>$null

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Deployment Complete!" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Access options:" -ForegroundColor Gray
Write-Host "  1. Tunnel (recommended): minikube -p $clusterName tunnel" -ForegroundColor White
Write-Host "     Then access: http://localhost" -ForegroundColor Green
Write-Host ""
Write-Host "  2. Direct IP: http://${minikubeIP}" -ForegroundColor White
Write-Host ""
Write-Host "Quick redeploy:  .\scripts\local-minikube-deploy.ps1 -SkipBuild -SkipCluster" -ForegroundColor White
Write-Host "Tear down:       .\scripts\local-minikube-down.ps1" -ForegroundColor White
Write-Host ""
