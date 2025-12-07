#!/usr/bin/env pwsh
# =================================================================================================
# SCRIPT: Teardown Kind Cluster
# =================================================================================================
# WELCOME STUDENTS!
# This script destroys the Kind cluster.
# Two modes:
# 1. Total Destruction: Deletes the Docker container acting as the cluster.
# 2. Keep Cluster: Only deletes the 'task-app' namespace. Useful for fast reboot.
# =================================================================================================

param(
    # If -KeepCluster is passed, we won't delete the Kind node.
    [switch]$KeepCluster
)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Tearing Down Kind Deployment" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$clusterName = "task-app"

if ($KeepCluster) {
    # OPTION A: Fast Wipe
    Write-Host "Deleting task-app namespace (keeping cluster)..." -ForegroundColor Yellow
    
    # Deleting the namespace deletes ALL resources inside it (Deployment, Service, Ingress...).
    kubectl delete namespace task-app --ignore-not-found
    
    Write-Host "Namespace deleted. Cluster '$clusterName' is still running." -ForegroundColor Green
    Write-Host "To redeploy, run with -SkipCluster." -ForegroundColor White
}
else {
    # OPTION B: Full Destroy
    Write-Host "Deleting Kind cluster '$clusterName'..." -ForegroundColor Yellow
    
    $existingCluster = kind get clusters 2>$null | Where-Object { $_ -eq $clusterName }
    
    if ($existingCluster) {
        # This stops and removes the 'task-app-control-plane' container.
        kind delete cluster --name $clusterName
        Write-Host "Cluster deleted successfully." -ForegroundColor Green
    }
    else {
        Write-Host "Cluster '$clusterName' does not exist." -ForegroundColor Yellow
    }
}

# Cleanup temporary manifest files
$tempDirs = @("scripts/.tmp-kind-manifests", "scripts/.kind-config.yml")
foreach ($path in $tempDirs) {
    if (Test-Path $path) {
        Remove-Item -Recurse -Force $path -ErrorAction SilentlyContinue
    }
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Teardown Complete!" -ForegroundColor Green
