[CmdletBinding()]
param(
    [string]$LabRoot = 'C:\pg_lab'
)

$scriptDir = $PSScriptRoot
if (-not $scriptDir) {
    $scriptDir = "."
}
. (Join-Path $scriptDir "lab_cluster.ps1")

Remove-LabCluster -LabRoot $LabRoot
Write-Host "Lab is removed."
