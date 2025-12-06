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
    @{Name = "auth-api"; BuildPath = "./auth-api" },
    @{Name = "tasks-api"; BuildPath = "./tasks-api" },
    @{Name = "frontend"; BuildPath = "./frontend" }
)

# Step 1: Check prerequisites
Write-Host "[1/5] Checking prerequisites..." -ForegroundColor Yellow

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
Write-Host ""

# Ensure cache directory exists (still used for temp manifests)
New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null

# Step 2: Create/Start Minikube cluster
if ($SkipCluster) {
    Write-Host "[2/5] Checking if cluster exists..." -ForegroundColor Yellow
    
    $status = minikube status -p $clusterName --format "{{.Host}}" 2>$null
    if (-not $status) {
        Write-Host "  WARNING: Cluster '$clusterName' not found! Ignoring -SkipCluster and creating it." -ForegroundColor Yellow
        $SkipCluster = $false
    }
    elseif ($status -ne "Running") {
        Write-Host "  Starting existing cluster..." -ForegroundColor Gray
        minikube start -p $clusterName
        Write-Host "  Using cluster '$clusterName'" -ForegroundColor Green
        Write-Host ""
    }
    else {
        Write-Host "  Using running cluster '$clusterName'" -ForegroundColor Green
        Write-Host ""
    }
}

$clusterCreated = $false
if (-not $SkipCluster) {
    Write-Host "[2/5] Creating Minikube cluster..." -ForegroundColor Yellow
    
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
    
    $clusterCreated = $true
    Write-Host "  Cluster created" -ForegroundColor Green
    Write-Host ""
}

# Step 3: Build images (In-Cluster)
if ($SkipBuild -and -not $clusterCreated) {
    Write-Host "[3/5] Skipping image build (-SkipBuild specified)..." -ForegroundColor Yellow
    
    # Verify existence of in-cluster images
    Write-Host "  Verifying cached images..." -ForegroundColor Gray
    $existingImages = minikube -p $clusterName image ls 2>$null
    $imagesMissing = $false
    
    foreach ($img in $appImages) {
        # Check matching tag (simple string match usually sufficient for latest)
        if ($existingImages -notmatch "$($img.Name):latest") {
            Write-Host "  WARNING: Image '$($img.Name)' not found in cluster!" -ForegroundColor Yellow
            $imagesMissing = $true
        }
    }
    
    if ($imagesMissing) {
        Write-Host "  Forcing build to fix missing images..." -ForegroundColor Yellow
        $SkipBuild = $false
    }
    else {
        Write-Host "  All images found." -ForegroundColor Green
    }
}
elseif ($SkipBuild -and $clusterCreated) {
    Write-Host "[3/5] Force enabling build (New cluster created, images are missing)..." -ForegroundColor Yellow
    $SkipBuild = $false
}

if (-not $SkipBuild) {
    Write-Host "[3/5] Building images (In-Cluster)..." -ForegroundColor Yellow
    Write-Host "  This uses the Minikube docker daemon directly. No local save/load needed." -ForegroundColor Gray
    Write-Host ""

    foreach ($img in $appImages) {
        Write-Host "  Building $($img.Name)..." -ForegroundColor Gray
        
        # Use minikube image build
        # Note: -f is relative to context root. Since context is $img.BuildPath and Dockerfile is at root of it, 
        # we can omit -f (defaults to Dockerfile) or use -f Dockerfile.
        minikube -p $clusterName image build -t "$($img.Name):latest" $img.BuildPath
        
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  ERROR: Failed to build $($img.Name)" -ForegroundColor Red
            exit 1
        }
    }
    Write-Host "  All images built in-cluster" -ForegroundColor Green
    Write-Host ""
}

# Step 4: Enable ingress addon
Write-Host "[4/5] Enabling ingress addon..." -ForegroundColor Yellow

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

# Step 5: Deploy application
Write-Host "[5/5] Deploying application..." -ForegroundColor Yellow
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
    # Replace default GCR images with simple tag names (minikube uses local registry by default for these)
    # Important: Set PullPolicy to Never to force using the built image
    $content = $content -replace 'us-central1-docker.pkg.dev/PROJECT_ID/task-app-repo/auth-api:latest', 'auth-api:latest'
    $content = $content -replace 'us-central1-docker.pkg.dev/PROJECT_ID/task-app-repo/tasks-api:latest', 'tasks-api:latest'
    $content = $content -replace 'us-central1-docker.pkg.dev/PROJECT_ID/task-app-repo/frontend:latest', 'frontend:latest'
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
