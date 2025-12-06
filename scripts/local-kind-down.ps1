#!/usr/bin/env pwsh
# Tear down Kind cluster deployment
# This script removes the Kind cluster and all associated resources

param(
    [switch]$KeepCluster  # Keep the cluster, only delete the namespace
)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Tearing Down Kind Deployment" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$clusterName = "task-app"

if ($KeepCluster) {
    # Only delete the namespace (keep cluster for faster redeployment)
    Write-Host "Deleting task-app namespace (keeping cluster)..." -ForegroundColor Yellow
    Write-Host ""
    
    kubectl delete namespace task-app --ignore-not-found
    
    Write-Host ""
    Write-Host "Namespace deleted. Cluster '$clusterName' is still running." -ForegroundColor Green
    Write-Host ""
    Write-Host "To redeploy, run:" -ForegroundColor Gray
    Write-Host "  .\scripts\local-kind-deploy.ps1 -SkipCluster" -ForegroundColor White
    Write-Host ""
}
else {
    # Delete the entire cluster
    Write-Host "Deleting Kind cluster '$clusterName'..." -ForegroundColor Yellow
    Write-Host ""
    
    # Check if cluster exists
    $existingCluster = kind get clusters 2>$null | Where-Object { $_ -eq $clusterName }
    
    if ($existingCluster) {
        kind delete cluster --name $clusterName
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Cluster deleted successfully." -ForegroundColor Green
        }
        else {
            Write-Host "ERROR: Failed to delete cluster" -ForegroundColor Red
            exit 1
        }
    }
    else {
        Write-Host "Cluster '$clusterName' does not exist." -ForegroundColor Yellow
    }
    
    Write-Host ""
}

# Cleanup temp files if they exist
$tempDirs = @("scripts/.tmp-kind-manifests", "scripts/.kind-config.yml")
foreach ($path in $tempDirs) {
    if (Test-Path $path) {
        Remove-Item -Recurse -Force $path -ErrorAction SilentlyContinue
    }
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Teardown Complete!" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
