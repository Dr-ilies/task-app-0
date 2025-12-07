#!/usr/bin/env pwsh
# =================================================================================================
# SCRIPT: Teardown Minikube
# =================================================================================================
# WELCOME STUDENTS!
# This cleans up the Minikube cluster.
# =================================================================================================

param(
    [switch]$KeepCluster,  # Keep the VM running
    [switch]$SkipCluster   # Alias for KeepCluster
)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Tearing Down Minikube Deployment" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$clusterName = "task-app"

if ($KeepCluster -or $SkipCluster) {
    Write-Host "Deleting task-app namespace (keeping cluster)..." -ForegroundColor Yellow
    
    # Just delete the namespace. The VM stays running.
    # Next deployment will be very fast.
    kubectl delete namespace task-app --ignore-not-found
    
    Write-Host "Namespace deleted. Cluster '$clusterName' still running." -ForegroundColor Green
}
else {
    Write-Host "Deleting Minikube cluster '$clusterName'..." -ForegroundColor Yellow
    
    # Check if it exists before trying to delete
    $status = minikube status -p $clusterName --format "{{.Host}}" 2>$null
    if ($status) {
        # This deletes the VM/Container entirely. Frees up RAM/CPU.
        minikube delete -p $clusterName
        Write-Host "Cluster deleted." -ForegroundColor Green
    }
    else {
        Write-Host "Cluster '$clusterName' does not exist." -ForegroundColor Yellow
    }
}

Remove-Item -Recurse -Force "scripts/.tmp-minikube-manifests" -ErrorAction SilentlyContinue

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Teardown Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
