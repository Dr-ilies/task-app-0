#!/usr/bin/env pwsh
# Local Kubernetes Deployment with Kind (Kubernetes IN Docker)
# This script creates a Kind cluster with Podman and deploys the application
# using the k8s-manifests with full Kubernetes DNS support

param(
    [switch]$SkipBuild,      # Skip building container images
    [switch]$SkipCluster     # Skip cluster creation (use existing)
)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Local Kind Deployment with Podman" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$clusterName = "task-app"
$env:KIND_EXPERIMENTAL_PROVIDER = "podman"

# Cache directory for all images
$cacheDir = "scripts/.kind-cache"

# Ingress controller image (update version as needed)
$ingressImage = "registry.k8s.io/ingress-nginx/controller:v1.12.2"
$ingressTarPath = Join-Path $cacheDir "ingress-controller.tar"

# App images
$appImages = @(
    @{Name = "auth-api"; PodmanTag = "localhost/auth-api:latest"; TarName = "auth-api.tar" },
    @{Name = "tasks-api"; PodmanTag = "localhost/tasks-api:latest"; TarName = "tasks-api.tar" },
    @{Name = "frontend"; PodmanTag = "localhost/frontend:latest"; TarName = "frontend.tar" }
)

# Step 1: Check prerequisites
Write-Host "[1/7] Checking prerequisites..." -ForegroundColor Yellow

if (-not (Get-Command kind -ErrorAction SilentlyContinue)) {
    Write-Host "  ERROR: 'kind' is not installed. Install it from: https://kind.sigs.k8s.io/" -ForegroundColor Red
    exit 1
}
Write-Host "  kind: OK" -ForegroundColor Green

if (-not (Get-Command kubectl -ErrorAction SilentlyContinue)) {
    Write-Host "  ERROR: 'kubectl' is not installed. Install it from: https://kubernetes.io/docs/tasks/tools/" -ForegroundColor Red
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

# Step 2: Build and cache app images
if ($SkipBuild) {
    Write-Host "[2/7] Skipping image build (-SkipBuild specified)..." -ForegroundColor Yellow
    
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
    Write-Host "[2/7] Building and caching container images..." -ForegroundColor Yellow
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

# Step 3: Ensure ingress controller image is cached
Write-Host "[3/7] Checking ingress controller cache..." -ForegroundColor Yellow

if (Test-Path $ingressTarPath) {
    Write-Host "  Using cached ingress controller" -ForegroundColor Green
}
else {
    Write-Host "  Pulling ingress controller (one-time download)..." -ForegroundColor Gray
    Write-Host "  Image: $ingressImage" -ForegroundColor Gray
    
    podman pull $ingressImage
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  ERROR: Failed to pull ingress controller" -ForegroundColor Red
        exit 1
    }
    
    Write-Host "  Caching ingress controller..." -ForegroundColor Gray
    podman save $ingressImage -o $ingressTarPath
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  ERROR: Failed to cache ingress controller" -ForegroundColor Red
        exit 1
    }
    
    Write-Host "  Ingress controller cached" -ForegroundColor Green
}
Write-Host ""

# Step 4: Create Kind cluster
if ($SkipCluster) {
    Write-Host "[4/7] Skipping cluster creation (-SkipCluster specified)..." -ForegroundColor Yellow
    
    $existingCluster = kind get clusters 2>$null | Where-Object { $_ -eq $clusterName }
    if (-not $existingCluster) {
        Write-Host "  ERROR: Cluster '$clusterName' does not exist. Run without -SkipCluster." -ForegroundColor Red
        exit 1
    }
    Write-Host "  Using existing cluster '$clusterName'" -ForegroundColor Green
    Write-Host ""
}
else {
    Write-Host "[4/7] Creating Kind cluster..." -ForegroundColor Yellow
    
    $existingCluster = kind get clusters 2>$null | Where-Object { $_ -eq $clusterName }
    if ($existingCluster) {
        Write-Host "  Cluster exists. Deleting..." -ForegroundColor Gray
        kind delete cluster --name $clusterName
    }

    $kindConfig = @"
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  kubeadmConfigPatches:
  - |
    kind: InitConfiguration
    nodeRegistration:
      kubeletExtraArgs:
        node-labels: "ingress-ready=true"
  extraPortMappings:
  - containerPort: 80
    hostPort: 8080
    protocol: TCP
  - containerPort: 443
    hostPort: 8443
    protocol: TCP
"@
    
    $kindConfigPath = Join-Path $cacheDir "kind-config.yml"
    $kindConfig | Set-Content $kindConfigPath

    Write-Host "  Creating cluster..." -ForegroundColor Gray
    kind create cluster --name $clusterName --config $kindConfigPath
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  ERROR: Failed to create cluster" -ForegroundColor Red
        exit 1
    }
    
    Write-Host "  Cluster created" -ForegroundColor Green
    Write-Host ""
}

# Step 5: Load ALL cached images into Kind
Write-Host "[5/7] Loading cached images into Kind..." -ForegroundColor Yellow

# Load app images from cache
foreach ($img in $appImages) {
    $tarPath = Join-Path $cacheDir $img.TarName
    Write-Host "  Loading $($img.Name)..." -ForegroundColor Gray
    
    podman cp $tarPath "${clusterName}-control-plane:/tmp/$($img.TarName)" 2>&1 | Out-Null
    podman exec "${clusterName}-control-plane" ctr --namespace k8s.io images import "/tmp/$($img.TarName)" 2>&1 | Out-Null
    podman exec "${clusterName}-control-plane" rm "/tmp/$($img.TarName)" 2>&1 | Out-Null
}

# Load ingress controller from cache
Write-Host "  Loading ingress-controller..." -ForegroundColor Gray
podman cp $ingressTarPath "${clusterName}-control-plane:/tmp/ingress-controller.tar" 2>&1 | Out-Null
podman exec "${clusterName}-control-plane" ctr --namespace k8s.io images import "/tmp/ingress-controller.tar" 2>&1 | Out-Null
podman exec "${clusterName}-control-plane" rm "/tmp/ingress-controller.tar" 2>&1 | Out-Null

Write-Host "  All images loaded" -ForegroundColor Green
Write-Host ""

# Step 6: Install NGINX Ingress Controller
Write-Host "[6/7] Installing NGINX Ingress Controller..." -ForegroundColor Yellow

kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.12.2/deploy/static/provider/kind/deploy.yaml 2>&1 | Out-Null

Write-Host "  Waiting for ingress controller..." -ForegroundColor Gray
$retries = 0
$maxRetries = 12
$ingressReady = $false

while ($retries -lt $maxRetries -and -not $ingressReady) {
    Start-Sleep -Seconds 5
    $status = kubectl get pods -n ingress-nginx -l app.kubernetes.io/component=controller -o jsonpath='{.items[0].status.phase}' 2>$null
    if ($status -eq "Running") {
        $ready = kubectl get pods -n ingress-nginx -l app.kubernetes.io/component=controller -o jsonpath='{.items[0].status.containerStatuses[0].ready}' 2>$null
        if ($ready -eq "true") {
            $ingressReady = $true
        }
    }
    $retries++
}

if ($ingressReady) {
    Write-Host "  Ingress controller ready" -ForegroundColor Green
}
else {
    Write-Host "  WARNING: Ingress controller may not be ready" -ForegroundColor Yellow
}
Write-Host ""

# Step 7: Deploy application
Write-Host "[7/7] Deploying application..." -ForegroundColor Yellow
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

# Deploy ingress (with robust retry and verification)
Write-Host "  Deploying ingress..." -ForegroundColor Gray
$ingressContent = Get-Content (Join-Path $manifestsDir "ingress.yml") -Raw
$ingressContent = $ingressContent -replace 'kubernetes.io/ingress.class: "gce"', 'kubernetes.io/ingress.class: "nginx"'
$ingressContent = $ingressContent -replace 'ingressClassName: gce', 'ingressClassName: nginx'
$ingressTempPath = Join-Path $tempDir "ingress.yml"
$ingressContent | Set-Content $ingressTempPath -NoNewline

$ingressDeployed = $false
$retries = 0
$maxRetries = 12  # 12 * 5s = 60s max wait

while ($retries -lt $maxRetries -and -not $ingressDeployed) {
    $result = kubectl apply -f $ingressTempPath 2>&1
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
        if ($retries -lt $maxRetries) {
            Write-Host "    Waiting for webhook... ($retries/$maxRetries)" -ForegroundColor Gray
            Start-Sleep -Seconds 5
        }
    }
}

if (-not $ingressDeployed) {
    Write-Host "  ERROR: Failed to deploy ingress after $maxRetries attempts" -ForegroundColor Red
    Write-Host "  Run manually: kubectl apply -f $ingressTempPath" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "  Waiting for pods..." -ForegroundColor Gray
kubectl wait --namespace task-app --for=condition=ready pod --all --timeout=180s 2>$null

Write-Host ""
kubectl get pods -n task-app

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Deployment Complete!" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "URL: " -NoNewline
Write-Host "http://localhost:8080" -ForegroundColor Green
Write-Host ""
Write-Host "Cache location: $cacheDir" -ForegroundColor Gray
Write-Host ""
Write-Host "Quick redeploy:  .\scripts\local-kind-deploy.ps1 -SkipBuild -SkipCluster" -ForegroundColor White
Write-Host "Tear down:       .\scripts\local-kind-down.ps1" -ForegroundColor White
Write-Host ""
