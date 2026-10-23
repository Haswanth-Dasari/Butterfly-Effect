[CmdletBinding()]
param(
    [int[]]$Days = @(50, 200, 800),
    [string]$Database = "butterfly_bench",
    [string]$User = "postgres"
)

# Password check: script requires $env:PGPASSWORD to be set
if ([string]::IsNullOrWhiteSpace($env:PGPASSWORD)) {
    Write-Error "ERROR: Environment variable PGPASSWORD is not set. Please set `$env:PGPASSWORD before running this script."
    exit 1
}

# Dependency check: psql must be available
if (-not (Get-Command psql -ErrorAction SilentlyContinue)) {
    Write-Error "ERROR: 'psql' command not found in PATH."
    exit 1
}

# Ensure script runs from the repository root
if (-not (Test-Path "db/schema/_all.sql")) {
    if (Test-Path "$PSScriptRoot/../../db/schema/_all.sql") {
        Set-Location (Resolve-Path "$PSScriptRoot/../..").Path
    }
}
if (-not (Test-Path "db/schema/_all.sql")) {
    Write-Error "ERROR: This script must be run from the repository root."
    exit 1
}

# Prepare results directory and overwrite CSV file at the start
$resultsDir = "experiments/results"
if (-not (Test-Path $resultsDir)) {
    New-Item -ItemType Directory -Path $resultsDir -Force | Out-Null
}
$csvPath = Join-Path $resultsDir "exp7a_rebuild.csv"
$csvHeader = "days,events,entity_rows,closure_rows,rebuild_projections_ms,rebuild_world_ms,digest_equal"
Set-Content -Path $csvPath -Value $csvHeader -Encoding UTF8

foreach ($S in $Days) {
    Write-Host "=========================================="
    Write-Host "Running recovery benchmark for $S days..."
    Write-Host "=========================================="

    # 1. Drop and create benchmark database
    Write-Host "Recreating database $Database..."
    & psql -X -v ON_ERROR_STOP=1 -U $User -d postgres -c "DROP DATABASE IF EXISTS $Database WITH (FORCE);" -c "CREATE DATABASE $Database;"
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to recreate database $Database"
        exit 1
    }

    # 2. Apply schema, seed, and benchmark generator scripts in order
    Write-Host "Applying db/schema/_all.sql..."
    & psql -X -v ON_ERROR_STOP=1 -U $User -d $Database -f "db/schema/_all.sql"
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to apply db/schema/_all.sql"
        exit 1
    }

    Write-Host "Applying db/seed/_seed_all.sql..."
    & psql -X -v ON_ERROR_STOP=1 -U $User -d $Database -f "db/seed/_seed_all.sql"
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to apply db/seed/_seed_all.sql"
        exit 1
    }

    Write-Host "Applying experiments/recovery/bench_generate.sql..."
    & psql -X -v ON_ERROR_STOP=1 -U $User -d $Database -f "experiments/recovery/bench_generate.sql"
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to apply experiments/recovery/bench_generate.sql"
        exit 1
    }

    # 3. Generate synthetic history
    Write-Host "Executing bench_generate($S)..."
    & psql -X -v ON_ERROR_STOP=1 -U $User -d $Database -c "SELECT bench_generate($S);"
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to execute bench_generate($S)"
        exit 1
    }

    # Look up main branch id through psql -X -A -t and print it
    $mainId = (& psql -X -A -t -U $User -d $Database -c "SELECT branch_id FROM branch WHERE name = 'main' AND parent_id IS NULL;").Trim()
    Write-Host "Main branch ID lookup: $mainId"

    # 4. Collect metric counts
    $events = (& psql -X -A -t -U $User -d $Database -c "SELECT count(*) FROM event;").Trim()
    $entityRows = (& psql -X -A -t -U $User -d $Database -c "SELECT count(*) FROM entity_state;").Trim()
    $closureRows = (& psql -X -A -t -U $User -d $Database -c "SELECT count(*) FROM causal_closure;").Trim()

    # 5. Compute pre-rebuild digest
    $digestBefore = (& psql -X -A -t -U $User -d $Database -c "SELECT branch_projection_digest($mainId);").Trim()

    # 6. Time rebuild_projections
    Write-Host "Timing rebuild_projections($mainId)..."
    $outProj = (& psql -X -U $User -d $Database -c '\timing on' -c "SELECT rebuild_projections($mainId);" 2>&1 | ForEach-Object { "$_" }) -join "`n"
    $timeProj = "0"
    if ($outProj -match 'Time:\s*([0-9]+(?:\.[0-9]+)?)\s*ms') {
        $timeProj = $Matches[1]
    }

    # 7. Compute post-rebuild digest and verify equality
    $digestAfter = (& psql -X -A -t -U $User -d $Database -c "SELECT branch_projection_digest($mainId);").Trim()
    $digestEqual = "false"
    if ($digestBefore -eq $digestAfter) {
        $digestEqual = "true"
    }

    # 8. Time rebuild_world the same way
    Write-Host "Timing rebuild_world($mainId)..."
    $outWorld = (& psql -X -U $User -d $Database -c '\timing on' -c "SELECT rebuild_world($mainId);" 2>&1 | ForEach-Object { "$_" }) -join "`n"
    $timeWorld = "0"
    if ($outWorld -match 'Time:\s*([0-9]+(?:\.[0-9]+)?)\s*ms') {
        $timeWorld = $Matches[1]
    }

    # 9. Append CSV row
    $csvRow = "$S,$events,$entityRows,$closureRows,$timeProj,$timeWorld,$digestEqual"
    Add-Content -Path $csvPath -Value $csvRow -Encoding UTF8
    Write-Host "Recorded: $csvRow"
}

# Clean up benchmark database at the end
Write-Host "Dropping benchmark database $Database..."
& psql -X -U $User -d postgres -c "DROP DATABASE IF EXISTS $Database WITH (FORCE);"

# Print results table
Write-Host ""
Write-Host "Recovery Benchmark Results ($csvPath):"
Import-Csv -Path $csvPath | Format-Table -AutoSize
