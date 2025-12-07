#!/usr/bin/env pwsh
# =================================================================================================
# SCRIPT: Local Kubernetes using Kind (Kubernetes IN Docker)
# =================================================================================================
# WELCOME STUDENTS!
# "Kind" stands for "Kubernetes IN Docker".
# It creates a whole Kubernetes cluster INSIDE a Docker container.
#
# WHY KIND?
# 1. Full Cluster: Unlike 'podman kube play', Kind gives you a Real K8s Cluster.
# 2. Ingress Support: You can install NGINX Ingress Controller.
# 3. DNS: It has a real internal DNS server (CoreDNS).
#
# WORKFLOW:
# 1. Create a Kind Cluster (starts a container acting as a "Node").
# 2. Build your app images.
# 3. "Load" images into the cluster (since the cluster is inside a container, it can't see your laptop's images).
# 4. Install Nginx Ingress.
# 5. Apply your k8s-manifests.
# =================================================================================================

param(
    [switch]$SkipBuild,      # Skip building container images
    [switch]$SkipCluster     # Skip cluster creation (use existing)
)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Local Kind Deployment with Podman" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$clusterName = "task-app"
# We tell Kind to use 'podman' instead of 'docker'.
$env:KIND_EXPERIMENTAL_PROVIDER = "podman"

# CACHING:
# Kind needs to import images (tarballs). This is slow.
# We create a cache folder to store the built images so we don't rebuild/re-import unnecessarily.
$cacheDir = "scripts/.kind-cache"

# INGRESS IMAGE:
# We pin a specific version of NGINX Ingress Controller.
$ingressImage = "registry.k8s.io/ingress-nginx/controller:v1.12.2"
$ingressTarPath = Join-Path $cacheDir "ingress-controller.tar"

# App Images Definition
# 'PodmanTag': The name on your laptop.
# 'TarName': The filename in the cache.
$appImages = @(
    @{Name = "auth-api"; PodmanTag = "localhost/auth-api:latest"; TarName = "auth-api.tar" },
    @{Name = "tasks-api"; PodmanTag = "localhost/tasks-api:latest"; TarName = "tasks-api.tar" },
    @{Name = "frontend"; PodmanTag = "localhost/frontend:latest"; TarName = "frontend.tar" }
)

# =================================================================================================
# STEP 1: Prerequisites
# =================================================================================================
Write-Host "[1/7] Checking prerequisites..." -ForegroundColor Yellow

if (-not (Get-Command kind -ErrorAction SilentlyContinue)) {
    Write-Host "  ERROR: 'kind' is not installed." -ForegroundColor Red
    exit 1
}
# Check for kubectl and podman as well...
if (-not (Get-Command kubectl -ErrorAction SilentlyContinue)) { Write-Host "  ERROR: 'kubectl' missing." -ForegroundColor Red; exit 1 }
if (-not (Get-Command podman -ErrorAction SilentlyContinue)) { Write-Host "  ERROR: 'podman' missing." -ForegroundColor Red; exit 1 }

Write-Host "  All tools ready." -ForegroundColor Green
New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null

# =================================================================================================
# STEP 2: Build and Cache Images
# =================================================================================================
if ($SkipBuild) {
    Write-Host "[2/7] Skipping image build..." -ForegroundColor Yellow
}
else {
    Write-Host "[2/7] Building and caching container images..." -ForegroundColor Yellow
    
    $buildPaths = @{
        "auth-api"  = "./auth-api"
        "tasks-api" = "./tasks-api"
        "frontend"  = "./frontend"
    }

    foreach ($img in $appImages) {
        $tarPath = Join-Path $cacheDir $img.TarName
        
        # 1. BUILD the image
        Write-Host "  Building $($img.Name)..." -ForegroundColor Gray
        podman build -t "$($img.Name):latest" -f "$($buildPaths[$img.Name])/Dockerfile" $buildPaths[$img.Name]
        
        # 2. SAVE the image to a .tar file
        # 'podman save' exports the image to a file. Kind can then 'import' this file.
        Write-Host "  Caching $($img.Name)..." -ForegroundColor Gray
        podman save $img.PodmanTag -o $tarPath 2>&1 | Out-Null
    }
}

# =================================================================================================
# STEP 3: Cache Ingress Controller
# =================================================================================================
# We download the Ingress Controller image once and save it to disk.
# This prevents downloading 300MB every time we restart the cluster.
Write-Host "[3/7] Checking ingress controller cache..." -ForegroundColor Yellow

if (-not (Test-Path $ingressTarPath)) {
    Write-Host "  Pulling ingress controller (one-time download)..." -ForegroundColor Gray
    podman pull $ingressImage
    podman save $ingressImage -o $ingressTarPath
}
Write-Host "  Ingress controller cached." -ForegroundColor Green

# =================================================================================================
# STEP 4: Create Kind Cluster
# =================================================================================================
if ($SkipCluster) {
    Write-Host "[4/7] Skipping cluster creation..." -ForegroundColor Yellow
}
else {
    Write-Host "[4/7] Creating Kind cluster (this takes a minute)..." -ForegroundColor Yellow
    
    # Delete old cluster if exists
    $existingCluster = kind get clusters 2>$null | Where-Object { $_ -eq $clusterName }
    if ($existingCluster) {
        kind delete cluster --name $clusterName
    }

    # CLUSTER CONFIGURATION
    # We need to map port 80 (inside Kind) to 8080 (on Laptop).
    # And port 443 (HTTPS) to 8443.
    # 'extraPortMappings' does this Docker port mapping for us.
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

    kind create cluster --name $clusterName --config $kindConfigPath
}

# =================================================================================================
# STEP 5: Load Images into Cluster
# =================================================================================================
Write-Host "[5/7] Loading cached images into Kind..." -ForegroundColor Yellow

# IMPORTANT CONCEPT:
# Your cluster is a Docker Container.
# It has its OWN internal Docker (containerd) storage.
# We must COPY our .tar files into the cluster node and Import them.

foreach ($img in $appImages) {
    $tarPath = Join-Path $cacheDir $img.TarName
    Write-Host "  Loading $($img.Name)..." -ForegroundColor Gray
    
    # 'podman cp': Copy file from Laptop -> Kind Container
    podman cp $tarPath "${clusterName}-control-plane:/tmp/$($img.TarName)" 2>&1 | Out-Null
    
    # 'podman exec': Run command INSIDE Kind Container
    # 'ctr images import': Import the tarball into containerd
    podman exec "${clusterName}-control-plane" ctr --namespace k8s.io images import "/tmp/$($img.TarName)" 2>&1 | Out-Null
    
    # Cleanup inside container
    podman exec "${clusterName}-control-plane" rm "/tmp/$($img.TarName)" 2>&1 | Out-Null
}

# Also load Ingress Controller
Write-Host "  Loading ingress-controller..." -ForegroundColor Gray
podman cp $ingressTarPath "${clusterName}-control-plane:/tmp/ingress-controller.tar" 2>&1 | Out-Null
podman exec "${clusterName}-control-plane" ctr --namespace k8s.io images import "/tmp/ingress-controller.tar" 2>&1 | Out-Null
podman exec "${clusterName}-control-plane" rm "/tmp/ingress-controller.tar" 2>&1 | Out-Null

# =================================================================================================
# STEP 6: Install Ingress Controller
# =================================================================================================
Write-Host "[6/7] Installing NGINX Ingress Controller..." -ForegroundColor Yellow

# We apply the specific manifest for Kind from the official repo
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.12.2/deploy/static/provider/kind/deploy.yaml 2>&1 | Out-Null

Write-Host "  Waiting for ingress controller to be ready..." -ForegroundColor Gray
# Loop until the Ingress Controller pod is officially "Ready"
$retries = 0; $maxRetries = 12; $ingressReady = $false
while ($retries -lt $maxRetries -and -not $ingressReady) {
    Start-Sleep -Seconds 5
    $status = kubectl get pods -n ingress-nginx -l app.kubernetes.io/component=controller -o jsonpath='{.items[0].status.phase}' 2>$null
    if ($status -eq "Running") {
        $ready = kubectl get pods -n ingress-nginx -l app.kubernetes.io/component=controller -o jsonpath='{.items[0].status.containerStatuses[0].ready}' 2>$null
        if ($ready -eq "true") { $ingressReady = $true }
    }
    $retries++
}

# =================================================================================================
# STEP 7: Deploy Application
# =================================================================================================
Write-Host "[7/7] Deploying application..." -ForegroundColor Yellow

$manifestsDir = "k8s-manifests"
$tempDir = Join-Path $cacheDir "manifests"
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

# 1. Namespace
kubectl apply -f (Join-Path $manifestsDir "namespace.yml")

# 2. App Components
$deployOrder = @("database.yml", "auth-api.yml", "tasks-api.yml", "frontend.yml")

foreach ($file in $deployOrder) {
    $sourcePath = Join-Path $manifestsDir $file
    $tempPath = Join-Path $tempDir $file

    $content = Get-Content $sourcePath -Raw
    
    # MODIFY MANIFEST:
    # Point to the images we just loaded (localhost/...)
    $content = $content -replace 'us-central1-docker.pkg.dev/PROJECT_ID/task-app-repo/auth-api:latest', 'localhost/auth-api:latest'
    $content = $content -replace 'us-central1-docker.pkg.dev/PROJECT_ID/task-app-repo/tasks-api:latest', 'localhost/tasks-api:latest'
    $content = $content -replace 'us-central1-docker.pkg.dev/PROJECT_ID/task-app-repo/frontend:latest', 'localhost/frontend:latest'
    
    # CRITICAL: 'imagePullPolicy: Never'
    # Tells Kubernetes: "Do NOT go to the internet. The image is already on the node."
    # We loaded it manually in Step 5.
    $content = $content -replace 'imagePullPolicy: Always', 'imagePullPolicy: Never'
    
    $content | Set-Content $tempPath -NoNewline
    Write-Host "  Deploying $file..." -ForegroundColor Gray
    kubectl apply -f $tempPath
    
    # Wait for DB before deploying APIs (Best Practice)
    if ($file -eq "database.yml") {
        Write-Host "  Waiting for database..." -ForegroundColor Gray
        kubectl wait --namespace task-app --for=condition=ready pod --selector=app=db --timeout=120s 2>$null
    }
}

# 3. Ingress
Write-Host "  Deploying ingress..." -ForegroundColor Gray
$ingressContent = Get-Content (Join-Path $manifestsDir "ingress.yml") -Raw
# We change the 'ingressClassName' from 'gce' (Google Cloud) to 'nginx' (Local).
$ingressContent = $ingressContent -replace 'kubernetes.io/ingress.class: "gce"', 'kubernetes.io/ingress.class: "nginx"'
$ingressContent = $ingressContent -replace 'ingressClassName: gce', 'ingressClassName: nginx'

$ingressTempPath = Join-Path $tempDir "ingress.yml"
$ingressContent | Set-Content $ingressTempPath -NoNewline

# Retry Loop for Ingress (Webhook can be flaky during startup)
$ingressDeployed = $false; $retries = 0; $maxRetries = 12
while ($retries -lt $maxRetries -and -not $ingressDeployed) {
    kubectl apply -f $ingressTempPath 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) { $ingressDeployed = $true }
    else { Start-Sleep -Seconds 5; $retries++ }
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Deployment Complete!" -ForegroundColor Cyan
Write-Host "URL: http://localhost:8080" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
