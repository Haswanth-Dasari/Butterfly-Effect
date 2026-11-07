[CmdletBinding()]
param(
    [int]$SmallDays = 200,
    [int]$Days = 800,
    [int]$Chunks = 16,
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
$csvPath = Join-Path $resultsDir "exp7d_mvcc.csv"
$csvHeader = "scenario,days,calls,events,generation_ms,ms_per_day,rebuild_projections_ms"
Set-Content -Path $csvPath -Value $csvHeader -Encoding UTF8

$script:LastPsqlOutput = ""
$script:currentStep = "Initialization"

function Invoke-Psql {
    param(
        [string]$Db = "postgres",
        [string]$Command = $null,
        [string]$File = $null,
        [switch]$TuplesOnly
    )
    $argsList = @("-X", "-v", "ON_ERROR_STOP=1", "-U", $User, "-d", $Db)
    if ($TuplesOnly) {
        $argsList += @("-A", "-t")
    }
    if ($File) {
        $argsList += @("-f", $File)
    }
    if ($Command) {
        $argsList += @("-c", $Command)
    }

    $oldEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $rawOutput = & psql $argsList 2>&1
        $code = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $oldEap
    }

    $outText = ($rawOutput | ForEach-Object { "$_" }) -join "`n"
    $script:LastPsqlOutput = $outText

    if ($code -ne 0) {
        throw "psql exited with code ${code}: ${outText}"
    }

    return $outText
}

function Recreate-ScenarioDatabase {
    param([string]$Db)

    $script:currentStep = "Recreating database ${Db}: DROP DATABASE"
    Write-Host "Dropping database ${Db} if exists..."
    $null = Invoke-Psql -Db "postgres" -Command "DROP DATABASE IF EXISTS ${Db} WITH (FORCE);"

    $script:currentStep = "Recreating database ${Db}: CREATE DATABASE"
    Write-Host "Creating database ${Db}..."
    $null = Invoke-Psql -Db "postgres" -Command "CREATE DATABASE ${Db};"

    $script:currentStep = "Applying db/schema/_all.sql to ${Db}"
    Write-Host "Applying db/schema/_all.sql..."
    $null = Invoke-Psql -Db $Db -File "db/schema/_all.sql"

    $script:currentStep = "Applying db/seed/_seed_all.sql to ${Db}"
    Write-Host "Applying db/seed/_seed_all.sql..."
    $null = Invoke-Psql -Db $Db -File "db/seed/_seed_all.sql"

    $script:currentStep = "Applying experiments/recovery/bench_generate.sql to ${Db}"
    Write-Host "Applying experiments/recovery/bench_generate.sql..."
    $null = Invoke-Psql -Db $Db -File "experiments/recovery/bench_generate.sql"
}

function Measure-RebuildProjectionsMedian {
    param(
        [string]$Db,
        [string]$MainBranchId
    )
    $timesProj = @()
    for ($i = 0; $i -lt 3; $i++) {
        $argsList = @("-X", "-U", $User, "-d", $Db, "-c", '\timing on', "-c", "SELECT rebuild_projections(${MainBranchId});")
        $oldEap = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            $rawOutput = & psql $argsList 2>&1
            $code = $LASTEXITCODE
        }
        finally {
            $ErrorActionPreference = $oldEap
        }
        $outProj = ($rawOutput | ForEach-Object { "$_" }) -join "`n"
        $script:LastPsqlOutput = $outProj
        if ($code -ne 0) {
            throw "rebuild_projections(${MainBranchId}) failed with exit code ${code}: ${outProj}"
        }
        $tProj = 0.0
        if ($outProj -match 'Time:\s*([0-9]+(?:\.[0-9]+)?)\s*ms') {
            $tProj = [double]$Matches[1]
        }
        $timesProj += $tProj
    }
    $sortedProj = $timesProj | Sort-Object
    return [math]::Round([double]$sortedProj[1], 2)
}

try {
    # -------------------------------------------------------------------------
    # Scenario A: single_small
    # -------------------------------------------------------------------------
    Write-Host "================================================================================"
    Write-Host "Scenario A: single_small (${SmallDays} days, 1 call)"
    Write-Host "================================================================================"
    Recreate-ScenarioDatabase -Db $Database

    $script:currentStep = "Scenario A: Generating ${SmallDays} days in 1 transaction"
    Write-Host "Executing bench_generate(${SmallDays}) in 1 call..."
    $swA = [System.Diagnostics.Stopwatch]::StartNew()
    $null = Invoke-Psql -Db $Database -Command "SELECT bench_generate(${SmallDays});"
    $swA.Stop()
    $genMsA = [math]::Round($swA.Elapsed.TotalMilliseconds, 2)
    $msPerDayA = [math]::Round(($genMsA / $SmallDays), 2)

    $script:currentStep = "Scenario A: Looking up main branch id"
    $mainIdA = (Invoke-Psql -Db $Database -Command "SELECT branch_id FROM branch WHERE name = 'main' AND parent_id IS NULL;" -TuplesOnly).Trim()

    $script:currentStep = "Scenario A: Counting events"
    $eventsA = [int64]((Invoke-Psql -Db $Database -Command "SELECT count(*) FROM event;" -TuplesOnly).Trim())

    $script:currentStep = "Scenario A: Timing rebuild_projections(${mainIdA})"
    Write-Host "Timing rebuild_projections(${mainIdA}) (3 runs)..."
    $rebuildMsA = Measure-RebuildProjectionsMedian -Db $Database -MainBranchId $mainIdA

    $rowA = "single_small,${SmallDays},1,${eventsA},${genMsA},${msPerDayA},${rebuildMsA}"
    Add-Content -Path $csvPath -Value $rowA -Encoding UTF8
    Write-Host "Recorded: ${rowA}"

    # -------------------------------------------------------------------------
    # Scenario B: single_large
    # -------------------------------------------------------------------------
    Write-Host ""
    Write-Host "================================================================================"
    Write-Host "Scenario B: single_large (${Days} days, 1 call)"
    Write-Host "================================================================================"
    Recreate-ScenarioDatabase -Db $Database

    $script:currentStep = "Scenario B: Generating ${Days} days in 1 transaction"
    Write-Host "Executing bench_generate(${Days}) in 1 call..."
    $swB = [System.Diagnostics.Stopwatch]::StartNew()
    $null = Invoke-Psql -Db $Database -Command "SELECT bench_generate(${Days});"
    $swB.Stop()
    $genMsB = [math]::Round($swB.Elapsed.TotalMilliseconds, 2)
    $msPerDayB = [math]::Round(($genMsB / $Days), 2)

    $script:currentStep = "Scenario B: Looking up main branch id"
    $mainIdB = (Invoke-Psql -Db $Database -Command "SELECT branch_id FROM branch WHERE name = 'main' AND parent_id IS NULL;" -TuplesOnly).Trim()

    $script:currentStep = "Scenario B: Counting events"
    $eventsB = [int64]((Invoke-Psql -Db $Database -Command "SELECT count(*) FROM event;" -TuplesOnly).Trim())

    $script:currentStep = "Scenario B: Timing rebuild_projections(${mainIdB})"
    Write-Host "Timing rebuild_projections(${mainIdB}) (3 runs)..."
    $rebuildMsB = Measure-RebuildProjectionsMedian -Db $Database -MainBranchId $mainIdB

    $rowB = "single_large,${Days},1,${eventsB},${genMsB},${msPerDayB},${rebuildMsB}"
    Add-Content -Path $csvPath -Value $rowB -Encoding UTF8
    Write-Host "Recorded: ${rowB}"

    # -------------------------------------------------------------------------
    # Scenario C: chunked_large
    # -------------------------------------------------------------------------
    Write-Host ""
    Write-Host "================================================================================"
    Write-Host "Scenario C: chunked_large (${Days} days across ${Chunks} calls)"
    Write-Host "================================================================================"
    Recreate-ScenarioDatabase -Db $Database

    $chunkDays = [int][math]::Floor($Days / $Chunks)
    $totalChunkDays = $chunkDays * $Chunks
    $script:currentStep = "Scenario C: Generating ${totalChunkDays} days across ${Chunks} transactions"
    Write-Host "Executing ${Chunks} separate psql calls of bench_generate(${chunkDays})..."
    $swC = [System.Diagnostics.Stopwatch]::StartNew()
    for ($c = 1; $c -le $Chunks; $c++) {
        $null = Invoke-Psql -Db $Database -Command "SELECT bench_generate(${chunkDays});"
    }
    $swC.Stop()
    $genMsC = [math]::Round($swC.Elapsed.TotalMilliseconds, 2)
    $msPerDayC = [math]::Round(($genMsC / $totalChunkDays), 2)

    $script:currentStep = "Scenario C: Looking up main branch id"
    $mainIdC = (Invoke-Psql -Db $Database -Command "SELECT branch_id FROM branch WHERE name = 'main' AND parent_id IS NULL;" -TuplesOnly).Trim()

    $script:currentStep = "Scenario C: Counting events"
    $eventsC = [int64]((Invoke-Psql -Db $Database -Command "SELECT count(*) FROM event;" -TuplesOnly).Trim())

    $script:currentStep = "Scenario C: Timing rebuild_projections(${mainIdC})"
    Write-Host "Timing rebuild_projections(${mainIdC}) (3 runs)..."
    $rebuildMsC = Measure-RebuildProjectionsMedian -Db $Database -MainBranchId $mainIdC

    $rowC = "chunked_large,${totalChunkDays},${Chunks},${eventsC},${genMsC},${msPerDayC},${rebuildMsC}"
    Add-Content -Path $csvPath -Value $rowC -Encoding UTF8
    Write-Host "Recorded: ${rowC}"

    # Clean up benchmark database at the end
    $script:currentStep = "Dropping benchmark database ${Database}"
    Write-Host ""
    Write-Host "Dropping benchmark database ${Database}..."
    $null = Invoke-Psql -Db "postgres" -Command "DROP DATABASE IF EXISTS ${Database} WITH (FORCE);"

    # Print results table
    Write-Host ""
    Write-Host "================================================================================"
    Write-Host "Experiment 7d: MVCC Transaction Length Results (${csvPath})"
    Write-Host "================================================================================"
    Import-Csv -Path $csvPath | Format-Table -AutoSize

    # Compute and print ratios
    $ratioLargeToChunked = 0.0
    if ($msPerDayC -gt 0) {
        $ratioLargeToChunked = [math]::Round(($msPerDayB / $msPerDayC), 2)
    }
    $ratioLargeToSmall = 0.0
    if ($msPerDayA -gt 0) {
        $ratioLargeToSmall = [math]::Round(($msPerDayB / $msPerDayA), 2)
    }

    $formattedX = [string]::Format([System.Globalization.CultureInfo]::InvariantCulture, "{0:F2}", $ratioLargeToChunked)
    $formattedY = [string]::Format([System.Globalization.CultureInfo]::InvariantCulture, "{0:F2}", $ratioLargeToSmall)

    Write-Host "ratio single_large / chunked_large (ms per day): ${formattedX}"
    Write-Host "ratio single_large / single_small (ms per day): ${formattedY}"

    if ($ratioLargeToChunked -gt 1.5) {
        Write-Host "Per-day cost grows with transaction length: long single transactions are slower (MVCC version chains)."
    } else {
        Write-Host "No strong single-transaction effect: look elsewhere for the cause."
    }
}
catch {
    $step = $script:currentStep
    Write-Host ""
    Write-Error "ERROR during step '${step}': $($_.Exception.Message)"
    if (-not [string]::IsNullOrWhiteSpace($script:LastPsqlOutput)) {
        Write-Host "Last psql output:"
        Write-Host $script:LastPsqlOutput
    }
    Write-Host "Benchmark database '${Database}' left in place for inspection."
    exit 1
}
finally {
    # No action needed on finally; failure leaves the database intact for inspection.
}
