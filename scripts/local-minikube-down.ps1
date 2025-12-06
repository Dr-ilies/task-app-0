#!/usr/bin/env pwsh
# Tear down Minikube cluster deployment

param(
    [switch]$KeepCluster  # Keep the cluster, only delete the namespace
)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Tearing Down Minikube Deployment" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$clusterName = "task-app"

if ($KeepCluster) {
    Write-Host "Deleting task-app namespace (keeping cluster)..." -ForegroundColor Yellow
    kubectl delete namespace task-app --ignore-not-found
    
    Write-Host ""
    Write-Host "Namespace deleted. Cluster '$clusterName' still running." -ForegroundColor Green
    Write-Host ""
    Write-Host "To redeploy: .\scripts\local-minikube-deploy.ps1 -SkipCluster" -ForegroundColor White
}
else {
    Write-Host "Deleting Minikube cluster '$clusterName'..." -ForegroundColor Yellow
    
    $status = minikube status -p $clusterName --format "{{.Host}}" 2>$null
    if ($status) {
        minikube delete -p $clusterName
        Write-Host "Cluster deleted." -ForegroundColor Green
    }
    else {
        Write-Host "Cluster '$clusterName' does not exist." -ForegroundColor Yellow
    }
}

# Cleanup temp files
Remove-Item -Recurse -Force "scripts/.tmp-minikube-manifests" -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Teardown Complete!" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
