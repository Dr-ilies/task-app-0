#!/usr/bin/env pwsh
# Local Kubernetes Deployment with Kind and Local Registry
# This script implements the "Local Registry" pattern for faster development cycles.
# =================================================================================================
# SCRIPT: Kind Deployment with Local Registry (Advanced)
# =================================================================================================
# WELCOME STUDENTS!
# This is the "Pro Level" version of using Kind.
#
# PROBLEM WITH 'local-kind-deploy.ps1':
# Loading images with 'kind load' (podman save -> copy -> podman load) is SLOW.
#
# SOLUTION: "Local Registry"
# 1. We start a Docker Registry container on localhost:5001.
# 2. We configure Kind to know about this registry.
# 3. We 'docker push' to localhost:5001.
# 4. Kind 'docker pulls' from localhost:5001.
#
# RESULT:
# Massive speedup because we only push/pull changes (layers), not the whole OS every time.
# =================================================================================================

param(
    [switch]$SkipBuild,      # Skip building container images
    [switch]$SkipCluster     # Skip cluster creation (use existing)
)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Kind Deployment with Local Registry" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$clusterName = "task-app"
$env:KIND_EXPERIMENTAL_PROVIDER = "podman"
$registryName = "kind-registry"
$registryPort = "5001"
$registryUrl = "localhost:${registryPort}"

# Cache directory (still used for temp manifest processing)
$cacheDir = "scripts/.kind-cache"
$manifestsDir = "k8s-manifests"

# App images metadata
$appImages = @(
    @{Name = "auth-api"; BuildContext = "./auth-api" },
    @{Name = "tasks-api"; BuildContext = "./tasks-api" },
    @{Name = "frontend"; BuildContext = "./frontend" }
)

# Step 1: Check prerequisites
Write-Host "[1/8] Checking prerequisites..." -ForegroundColor Yellow

if (-not (Get-Command kind -ErrorAction SilentlyContinue)) {
    Write-Host "  ERROR: 'kind' missing." -ForegroundColor Red; exit 1
}
if (-not (Get-Command kubectl -ErrorAction SilentlyContinue)) {
    Write-Host "  ERROR: 'kubectl' missing." -ForegroundColor Red; exit 1
}
if (-not (Get-Command podman -ErrorAction SilentlyContinue)) {
    Write-Host "  ERROR: 'podman' missing." -ForegroundColor Red; exit 1
}
Write-Host "  All tools installed." -ForegroundColor Green
Write-Host ""

# Step 2: Ensure Local Registry is Running
Write-Host "[2/8] Setting up Local Registry..." -ForegroundColor Yellow

$existingRegistry = podman ps -a --filter "name=${registryName}" --format "{{.ID}}"
if (-not $existingRegistry) {
    Write-Host "  Creating registry container '${registryName}'..." -ForegroundColor Gray
    # Run registry on localhost:5001
    podman run -d --restart=always -p "127.0.0.1:${registryPort}:5000" --name "${registryName}" registry:2
    if ($LASTEXITCODE -ne 0) { Write-Host "  ERROR: Failed to start registry." -ForegroundColor Red; exit 1 }
}
else {
    $isRunning = podman inspect -f '{{.State.Running}}' "${registryName}"
    if ($isRunning -eq "false") {
        Write-Host "  Starting existing registry..." -ForegroundColor Gray
        podman start "${registryName}" | Out-Null
    }
    else {
        Write-Host "  Registry '${registryName}' is already running." -ForegroundColor Green
    }
}
Write-Host ""

# =================================================================================================
# STEP 3: Network Connection
# =================================================================================================
# The Registry and the Cluster are two sibling containers.
# By default, they can't talk to each other unless they are on the same Docker Network.
# Kind creates a network called "kind". We put the registry on it.
# Step 3: Create Kind Cluster with Registry Config
if ($SkipCluster) {
    Write-Host "[3/8] Checking if cluster exists..." -ForegroundColor Yellow
    $existing = kind get clusters 2>$null | Where-Object { $_ -eq $clusterName }
    if (-not $existing) {
        Write-Host "  WARNING: Cluster '$clusterName' not found! Ignoring -SkipCluster and creating it." -ForegroundColor Yellow
        $SkipCluster = $false
    }
    else {
        Write-Host "  Skipping cluster creation (Cluster exists)..." -ForegroundColor Yellow
    }
}

if ($SkipCluster) {
    # Valid skip, do nothing
}
else {
    Write-Host "[3/8] Creating Kind cluster..." -ForegroundColor Yellow
    
    $existingCluster = kind get clusters 2>$null | Where-Object { $_ -eq $clusterName }
    if ($existingCluster) {
        Write-Host "  Cluster exists. Deleting..." -ForegroundColor Gray
        kind delete cluster --name $clusterName
    }

    # Configuration to tell containerd to use the registry mirror
    $kindConfig = @"
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
containerdConfigPatches:
- |-
  [plugins."io.containerd.grpc.v1.cri".registry.mirrors."localhost:${registryPort}"]
    endpoint = ["http://${registryName}:5000"]
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
    
    New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
    $kindConfigPath = Join-Path $cacheDir "kind-registry-config.yml"
    $kindConfig | Set-Content $kindConfigPath

    Write-Host "  Creating cluster..." -ForegroundColor Gray
    kind create cluster --name $clusterName --config $kindConfigPath
    if ($LASTEXITCODE -ne 0) { Write-Host "  ERROR: Cluster creation failed." -ForegroundColor Red; exit 1 }
}
Write-Host ""

# Step 4: Connect Registry to Kind Network
Write-Host "[4/8] Connecting registry to Kind network..." -ForegroundColor Yellow
# Kind (podman provider) usually creates a network named 'kind'
# We need to ensure the registry can talk to the nodes, and vice versa.
# By checking if registry is connected to 'kind' network
$registryNets = podman inspect -f '{{json .NetworkSettings.Networks}}' "${registryName}"
if ($registryNets -notmatch '"kind"') {
    Write-Host "  Connecting '${registryName}' to 'kind' network..." -ForegroundColor Gray
    podman network connect "kind" "${registryName}" 2>$null
    # Ignore error if network doesn't exist (e.g. if kind failed or uses host net)
    # But usually 'kind' network exists after cluster creation.
}
else {
    Write-Host "  Registry already connected to 'kind' network." -ForegroundColor Green
}
Write-Host ""

# Step 5: Build and Push Images
if ($SkipBuild) {
    Write-Host "[5/8] Skipping build..." -ForegroundColor Yellow
}
else {
    Write-Host "[5/8] Building and Pushing images..." -ForegroundColor Yellow
    
    foreach ($app in $appImages) {
        $tag = "${registryUrl}/$($app.Name):latest"
        Write-Host "  Processing $($app.Name)..." -ForegroundColor Gray
        
        # Build
        Write-Host "    Building..." -ForegroundColor Gray
        podman build -t $tag -f "$($app.BuildContext)/Dockerfile" $app.BuildContext
        if ($LASTEXITCODE -ne 0) { Write-Host "    ERROR: Build failed." -ForegroundColor Red; exit 1 }
        
        # Push
        Write-Host "    Pushing to local registry..." -ForegroundColor Gray
        # --tls-verify=false is crucial because localhost:5001 is HTTP
        podman push $tag --tls-verify=false
        if ($LASTEXITCODE -ne 0) { Write-Host "    ERROR: Push failed." -ForegroundColor Red; exit 1 }
    }
    Write-Host "  All images pushed to ${registryUrl}" -ForegroundColor Green
}
Write-Host ""

# Step 6: Install Ingress Controller (Optimized with Local Cache)
Write-Host "[6/8] Installing NGINX Ingress Controller..." -ForegroundColor Yellow

$ingressManifestUrl = "https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.12.2/deploy/static/provider/kind/deploy.yaml"
$ingressManifestPath = Join-Path $cacheDir "ingress-nginx-deploy.yaml"
$ingressImages = @(
    @{Name = "registry.k8s.io/ingress-nginx/controller:v1.12.2"; LocalTag = "${registryUrl}/ingress-nginx/controller:v1.12.2" },
    @{Name = "registry.k8s.io/ingress-nginx/kube-webhook-certgen:v1.5.3"; LocalTag = "${registryUrl}/ingress-nginx/kube-webhook-certgen:v1.5.3" }
)

# 6a. Mirror images to local registry if missing
foreach ($img in $ingressImages) {
    # Check if image exists in local registry (via podman pull dry run or manifest inspect if we wanted to be strict)
    # Simpler: check if we've flagged it as cached before, or just try to pull from local registry to check
    $imgExists = podman manifest inspect $img.LocalTag --tls-verify=false 2>$null
    
    if (-not $imgExists) {
        Write-Host "  Caching $($img.Name) into local registry..." -ForegroundColor Gray
        podman pull $img.Name
        podman tag $img.Name $img.LocalTag
        podman push $img.LocalTag --tls-verify=false
        if ($LASTEXITCODE -ne 0) { Write-Host "  WARNING: Failed to push ingress image. Deployment might be slower." -ForegroundColor Yellow }
    }
    else {
        Write-Host "  Using cached $($img.LocalTag)" -ForegroundColor Green
    }
}

# 6b. Download and patch manifest
if (-not (Test-Path $ingressManifestPath)) {
    Write-Host "  Downloading Ingress manifest..." -ForegroundColor Gray
    Invoke-WebRequest -Uri $ingressManifestUrl -OutFile $ingressManifestPath
}

# Read manifest and replace images with local registry versions
# REGEX update: Robustly strip @sha256 digest by matching until quote/whitespace
$ingressYaml = Get-Content $ingressManifestPath -Raw
$ingressYaml = $ingressYaml -replace "registry.k8s.io/ingress-nginx/controller:v1.12.2[^""\s]*", "${registryUrl}/ingress-nginx/controller:v1.12.2"
$ingressYaml = $ingressYaml -replace "registry.k8s.io/ingress-nginx/kube-webhook-certgen:v1.5.3[^""\s]*", "${registryUrl}/ingress-nginx/kube-webhook-certgen:v1.5.3"
$ingressYaml = $ingressYaml -replace "registry.k8s.io/ingress-nginx/kube-webhook-certgen:v1.4.4[^""\s]*", "${registryUrl}/ingress-nginx/kube-webhook-certgen:v1.4.4"
# Also set pull policy to IfNotPresent (default) but ensure it's not Always which forces contact with registry
$ingressYaml = $ingressYaml -replace "imagePullPolicy: Always", "imagePullPolicy: IfNotPresent"

$cachedIngressDeployPath = Join-Path $cacheDir "ingress-nginx-deploy-local.yaml"
$ingressYaml | Set-Content $cachedIngressDeployPath -NoNewline

# Apply
kubectl apply -f $cachedIngressDeployPath 2>&1 | Out-Null


Write-Host "  Waiting for ingress controller..." -ForegroundColor Gray
kubectl wait --namespace ingress-nginx --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=90s 2>$null
Write-Host "  Ingress controller status checked." -ForegroundColor Green
Write-Host ""

# Step 7: Deploy Application
Write-Host "[7/8] Deploying Application..." -ForegroundColor Yellow

$deployTempDir = Join-Path $cacheDir "registry-manifests"
New-Item -ItemType Directory -Path $deployTempDir -Force | Out-Null

# Namespace
kubectl apply -f (Join-Path $manifestsDir "namespace.yml")

# Resources
$deployOrder = @("database.yml", "auth-api.yml", "tasks-api.yml", "frontend.yml")
foreach ($file in $deployOrder) {
    $content = Get-Content (Join-Path $manifestsDir $file) -Raw
    
    # REPLACE GCR images with Local Registry images
    # NOTE: No need for 'imagePullPolicy: Never' anymore! Default (Always/IfNotPresent) works with registry.
    $content = $content -replace 'us-central1-docker.pkg.dev/PROJECT_ID/task-app-repo/auth-api:latest', "${registryUrl}/auth-api:latest"
    $content = $content -replace 'us-central1-docker.pkg.dev/PROJECT_ID/task-app-repo/tasks-api:latest', "${registryUrl}/tasks-api:latest"
    $content = $content -replace 'us-central1-docker.pkg.dev/PROJECT_ID/task-app-repo/frontend:latest', "${registryUrl}/frontend:latest"
    
    # Remove explicit PullPolicy if it was set to Never in originals (it wasn't in source, but just in case)
    # The source manifests usually have Always or nothing.
    # We leave it, as pulling from registry is fine.

    $targetPath = Join-Path $deployTempDir $file
    $content | Set-Content $targetPath -NoNewline
    
    Write-Host "  Deploying $file..." -ForegroundColor Gray
    kubectl apply -f $targetPath
}

# Step 8: Ingress
Write-Host "[8/8] Deploying Ingress..." -ForegroundColor Yellow

# Workaround: Delete the ValidatingWebhookConfiguration
# The ingress-nginx admission webhook is notoriously flaky in local Kind/Minikube setups
# and often blocks ingress creation with "connection refused".
# Since this is local dev, we don't strictly need API validation.
Write-Host "  Disabling ingress validation webhook (workaround for local dev)..." -ForegroundColor Gray
kubectl delete validatingwebhookconfiguration ingress-nginx-admission 2>&1 | Out-Null

$ingressContent = Get-Content (Join-Path $manifestsDir "ingress.yml") -Raw
$ingressContent = $ingressContent -replace 'kubernetes.io/ingress.class: "gce"', 'kubernetes.io/ingress.class: "nginx"'
$ingressContent = $ingressContent -replace 'ingressClassName: gce', 'ingressClassName: nginx'
$ingressPath = Join-Path $deployTempDir "ingress.yml"
$ingressContent | Set-Content $ingressPath -NoNewline

# Retry loop for ingress webhook
$ingressDeployed = $false
$retries = 0
while ($retries -lt 24 -and -not $ingressDeployed) {
    # Capture output to variable to preserve LASTEXITCODE and hide output
    kubectl apply -f $ingressPath 2>&1 | Out-Null
    
    if ($LASTEXITCODE -eq 0) {
        Start-Sleep -Seconds 2
        $ingressExists = kubectl get ingress -n task-app task-app-ingress -o name 2>$null
        if ($ingressExists) { 
            $ingressDeployed = $true 
            Write-Host "  Ingress deployed and verified" -ForegroundColor Green
        }
        else { Start-Sleep -Seconds 5; $retries++ }
    }
    else { 
        # Optional: Print error if it persists
        # Write-Host "    Retry $retries: $($result[0])" -ForegroundColor Gray
        Start-Sleep -Seconds 5; $retries++ 
    }
}

if (-not $ingressDeployed) {
    Write-Host "  ERROR: Failed to deploy ingress after retries." -ForegroundColor Red
    Write-Host "  Check controller logs or try running: kubectl apply -f $ingressPath" -ForegroundColor Yellow
}

Write-Host "  Waiting for pods to be ready..." -ForegroundColor Gray
kubectl wait --namespace task-app --for=condition=ready pod --all --timeout=180s 2>$null

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Deployment Complete (Registry Mode)!" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "URL: http://localhost:8080" -ForegroundColor Green
Write-Host ""
