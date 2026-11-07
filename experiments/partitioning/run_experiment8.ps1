[CmdletBinding()]
param(
    [string]$Database = "butterfly",
    [string]$User = "postgres",
    [int]$Events = 400000
)
if ([string]::IsNullOrWhiteSpace($env:PGPASSWORD)) { Write-Error "Set `$env:PGPASSWORD first."; exit 1 }
if (-not (Get-Command psql -ErrorAction SilentlyContinue)) { Write-Error "psql not found in PATH."; exit 1 }
$root = Resolve-Path (Join-Path $PSScriptRoot "..\..")
Push-Location $root
try {
    New-Item -ItemType Directory -Force -Path "experiments/results" | Out-Null
    & psql -X -U $User -d $Database -v n=$Events -v out="experiments/results/exp8_partitioning.csv" -f "experiments/partitioning/exp8_partitioning.sql"
    if ($LASTEXITCODE -ne 0) { Write-Error "Experiment 8 failed."; exit 1 }
} finally { Pop-Location }
