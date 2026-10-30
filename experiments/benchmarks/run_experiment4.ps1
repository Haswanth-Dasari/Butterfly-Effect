[CmdletBinding()]
param(
    [int[]]$Sizes = @(100, 400, 1600, 3200),
    [string]$Database = "butterfly_bench",
    [string]$User = "postgres",
    [switch]$Quick
)

# Password check: script requires $env:PGPASSWORD to be set
if ([string]::IsNullOrWhiteSpace($env:PGPASSWORD)) {
    Write-Error "ERROR: Environment variable PGPASSWORD is not set. Please set `$env:PGPASSWORD before running this script."
    exit 1
}

# Never touch the production database named butterfly
if ($Database -eq "butterfly") {
    Write-Error "ERROR: This benchmark script must never be run against the 'butterfly' database."
    exit 1
}

# Dependency check: psql must be available
if (-not (Get-Command psql -ErrorAction SilentlyContinue)) {
    Write-Error "ERROR: 'psql' command not found in PATH."
    exit 1
}

# Ensure script runs from the repository root
if (-not (Test-Path "db/schema/_all.sql")) {
    if (Test-Path "${PSScriptRoot}/../../db/schema/_all.sql") {
        Set-Location (Resolve-Path "${PSScriptRoot}/../..").Path
    }
}
if (-not (Test-Path "db/schema/_all.sql")) {
    Write-Error "ERROR: This script must be run from the repository root."
    exit 1
}

# If -Quick is specified, run on reduced sizes
if ($Quick) {
    $Sizes = @(100, 400)
}

# Prepare results directory and overwrite CSV files at the start
$resultsDir = "experiments/results"
if (-not (Test-Path $resultsDir)) {
    New-Item -ItemType Directory -Path $resultsDir -Force | Out-Null
}

$branchingCsvPath = Join-Path $resultsDir "exp4_branching.csv"
$snapshotsCsvPath = Join-Path $resultsDir "exp4_snapshots.csv"

$branchingHeader = "days,events,scenario,strategy,fork_ms,replayed_events,digest_ok,child_entity_rows,child_stock_rows,child_state_kb,read_ms"
$snapshotsHeader = "days,events,snapshots,snapshot_kb,parent_entity_rows"

Set-Content -Path $branchingCsvPath -Value $branchingHeader -Encoding UTF8
Set-Content -Path $snapshotsCsvPath -Value $snapshotsHeader -Encoding UTF8

$script:LastPsqlOutput = ""
$script:currentStep = "Initialization"

function Write-StepBanner {
    param([string]$Message)
    $script:currentStep = $Message
    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    Write-Host "================================================================================"
    Write-Host "[${timestamp}] ${Message}"
    Write-Host "================================================================================"
}

function Invoke-Psql {
    param(
        [string]$Db = "postgres",
        [string]$Command = $null,
        [string]$File = $null,
        [switch]$TuplesOnly,
        [switch]$Timing
    )

    $argParts = @("-X", "-v ON_ERROR_STOP=1", "-U `"${User}`"", "-d `"${Db}`"")
    if ($TuplesOnly) {
        $argParts += "-A -t"
    }
    if ($Timing) {
        $argParts += "-c `"\timing on`""
    }
    if ($File) {
        $argParts += "-f `"${File}`""
    }
    if ($Command) {
        $cleanCommand = ($Command -replace "`r`n", " ") -replace "`n", " "
        $escapedCommand = $cleanCommand.Replace('"', '\"')
        $argParts += "-c `"${escapedCommand}`""
    }
    $argString = $argParts -join " "

    $stdoutFile = [System.IO.Path]::GetTempFileName()
    $stderrFile = [System.IO.Path]::GetTempFileName()

    try {
        $p = Start-Process -FilePath "psql" -ArgumentList $argString -NoNewWindow -PassThru -RedirectStandardOutput $stdoutFile -RedirectStandardError $stderrFile
        $null = $p.Handle

        $hasExited = $p.WaitForExit(600000)
        if (-not $hasExited) {
            try {
                $p.Kill()
            }
            catch {
            }
            $stdoutText = ""
            $stderrText = ""
            if (Test-Path $stdoutFile) {
                $stdoutText = [System.IO.File]::ReadAllText($stdoutFile, [System.Text.Encoding]::UTF8)
            }
            if (Test-Path $stderrFile) {
                $stderrText = [System.IO.File]::ReadAllText($stderrFile, [System.Text.Encoding]::UTF8)
            }
            Write-Host "psql timed out after 600000 ms"
            Write-Host "STDOUT: ${stdoutText}"
            Write-Host "STDERR: ${stderrText}"
            throw "psql timed out after 600000 ms"
        }

        $stdoutText = ""
        $stderrText = ""
        if (Test-Path $stdoutFile) {
            $stdoutText = [System.IO.File]::ReadAllText($stdoutFile, [System.Text.Encoding]::UTF8)
        }
        if (Test-Path $stderrFile) {
            $stderrText = [System.IO.File]::ReadAllText($stderrFile, [System.Text.Encoding]::UTF8)
        }

        $combinedText = $stdoutText
        if (-not [string]::IsNullOrWhiteSpace($stderrText)) {
            if ([string]::IsNullOrWhiteSpace($combinedText)) {
                $combinedText = $stderrText
            }
            else {
                $combinedText = "${combinedText}`n${stderrText}"
            }
        }
        $script:LastPsqlOutput = $combinedText

        $code = 0
        try {
            if ($null -ne $p.ExitCode) {
                $code = $p.ExitCode
            }
        }
        catch {
            $code = 0
        }

        if ($code -ne 0) {
            throw "psql exited with code ${code}: ${combinedText}"
        }

        return $combinedText
    }
    finally {
        if (Test-Path $stdoutFile) {
            Remove-Item -Path $stdoutFile -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path $stderrFile) {
            Remove-Item -Path $stderrFile -Force -ErrorAction SilentlyContinue
        }
    }
}

try {
    foreach ($S in $Sizes) {
        Write-StepBanner "Starting Experiment 4 benchmark for size S = ${S} days"

        # 1. Recreate benchmark database (two separate psql calls)
        Write-StepBanner "Recreating benchmark database ${Database}"
        Write-Host "Dropping database ${Database} if exists..."
        $null = Invoke-Psql -Db "postgres" -Command "DROP DATABASE IF EXISTS ${Database} WITH (FORCE);"
        Write-Host "Creating database ${Database}..."
        $null = Invoke-Psql -Db "postgres" -Command "CREATE DATABASE ${Database};"

        Write-StepBanner "Applying db/schema/_all.sql"
        $null = Invoke-Psql -Db $Database -File "db/schema/_all.sql"

        Write-StepBanner "Applying db/seed/_seed_all.sql"
        $null = Invoke-Psql -Db $Database -File "db/seed/_seed_all.sql"

        Write-StepBanner "Applying experiments/recovery/bench_generate.sql"
        $null = Invoke-Psql -Db $Database -File "experiments/recovery/bench_generate.sql"

        Write-StepBanner "Looking up main branch id"
        $mainId = (Invoke-Psql -Db $Database -Command "SELECT branch_id FROM branch WHERE name = 'main' AND parent_id IS NULL;" -TuplesOnly).Trim()
        Write-Host "Main branch ID lookup: ${mainId}"

        # 2. Generate history in K = S / 50 chunks
        $K = [int][math]::Floor($S / 50)
        $pastChunk = [math]::Max(1, [int][math]::Floor($K / 2))
        Write-StepBanner "Generating history for ${S} days in ${K} chunks (50 days per chunk)"
        Write-Host "K = ${K}, pastChunk = ${pastChunk}"

        $hPast = $null
        $dPast = $null

        for ($i = 1; $i -le $K; $i++) {
            Write-StepBanner "Chunk ${i} of ${K}: bench_generate(50)"
            $null = Invoke-Psql -Db $Database -Command "SELECT bench_generate(50);"
            $null = Invoke-Psql -Db $Database -Command "SELECT create_snapshot(${mainId});"

            if ($i -eq $pastChunk) {
                Write-Host "Recording past checkpoint at chunk ${i} of ${K}"
                $hPast = (Invoke-Psql -Db $Database -Command "SELECT max(event_id) FROM event WHERE branch_id = ${mainId};" -TuplesOnly).Trim()
                $dPast = (Invoke-Psql -Db $Database -Command "SELECT branch_projection_digest(${mainId});" -TuplesOnly).Trim()
                Write-Host "Checkpoint H_PAST: ${hPast}, D_PAST: ${dPast}"
            }
        }

        Write-StepBanner "Generating 25 post-snapshot days on main branch"
        $null = Invoke-Psql -Db $Database -Command "SELECT bench_generate(25);"

        $hHead = (Invoke-Psql -Db $Database -Command "SELECT max(event_id) FROM event WHERE branch_id = ${mainId};" -TuplesOnly).Trim()
        $dHead = (Invoke-Psql -Db $Database -Command "SELECT branch_projection_digest(${mainId});" -TuplesOnly).Trim()
        $events = (Invoke-Psql -Db $Database -Command "SELECT count(*) FROM event;" -TuplesOnly).Trim()
        Write-Host "Checkpoint H_HEAD: ${hHead}"
        Write-Host "Checkpoint D_HEAD: ${dHead}"
        Write-Host "Total events: ${events}"

        # 3. Fork scenarios
        # scenario 'head': strategies replay, snapshot_delta, cow
        # scenario 'past': strategies replay, snapshot_delta
        $forkScenarios = @(
            @{ Scenario = "head"; ForkEvent = $hHead; Strategy = "replay" },
            @{ Scenario = "head"; ForkEvent = $hHead; Strategy = "snapshot_delta" },
            @{ Scenario = "head"; ForkEvent = $hHead; Strategy = "cow" },
            @{ Scenario = "past"; ForkEvent = $hPast; Strategy = "replay" },
            @{ Scenario = "past"; ForkEvent = $hPast; Strategy = "snapshot_delta" }
        )

        foreach ($sc in $forkScenarios) {
            $scenario = $sc.Scenario
            $forkEvent = $sc.ForkEvent
            $strategy = $sc.Strategy

            Write-StepBanner "Benchmarking fork: Scenario=${scenario}, Strategy=${strategy}, ForkEvent=${forkEvent}"

            $times = @()
            $replayedEvents = 0
            $lastChildName = ""

            # Repeat 3 times with unique child names and record median
            for ($rep = 1; $rep -le 3; $rep++) {
                $childName = "child_s${S}_${scenario}_${strategy}_r${rep}"
                $lastChildName = $childName

                Write-StepBanner "Fork: scenario=${scenario}, strategy=${strategy}, rep=${rep}"

                $forkSql = "SELECT fork_branch(${mainId}, ${forkEvent}, '${childName}', '${strategy}');"
                $outText = Invoke-Psql -Db $Database -Command $forkSql -Timing

                $t = 0.0
                if ($outText -match '(?i)Time:\s*([0-9]+(?:\.[0-9]+)?)\s*ms') {
                    $t = [double]$Matches[1]
                }
                $times += $t

                if ($strategy -eq "cow") {
                    $replayedEvents = 0
                }
                elseif ($outText -match '(?i)replayed\s+([0-9]+)\s+events') {
                    $replayedEvents = [int64]$Matches[1]
                }
            }

            $sortedTimes = $times | Sort-Object
            $fork_ms = [math]::Round([double]$sortedTimes[1], 2)
            Write-Host "  Fork median time: ${fork_ms} ms (Replayed events: ${replayedEvents})"

            # 4. Measure child state of the LAST repetition ($lastChildName)
            Write-StepBanner "Measuring state and digest of last child ${lastChildName}"
            $childId = (Invoke-Psql -Db $Database -Command "SELECT branch_id FROM branch WHERE name = '${lastChildName}';" -TuplesOnly).Trim()

            $childDigest = (Invoke-Psql -Db $Database -Command "SELECT branch_projection_digest(${childId});" -TuplesOnly).Trim()
            $expectedDigest = $dHead
            if ($scenario -eq "past") {
                $expectedDigest = $dPast
            }

            $digest_ok = "false"
            if ($childDigest -eq $expectedDigest) {
                $digest_ok = "true"
            }

            $child_entity_rows = [int64]((Invoke-Psql -Db $Database -Command "SELECT count(*) FROM entity_state WHERE branch_id = ${childId};" -TuplesOnly).Trim())
            $child_stock_rows = [int64]((Invoke-Psql -Db $Database -Command "SELECT count(*) FROM stock WHERE branch_id = ${childId};" -TuplesOnly).Trim())

            # child_state_kb: sum of pg_column_size(t.*) over child's rows in entity_state, stock, scheduled_effect / 1024 rounded to 1 decimal
            $stateKbSql = "SELECT round(COALESCE(sum(sz), 0)::numeric / 1024.0, 1) FROM (SELECT pg_column_size(t.*) AS sz FROM entity_state t WHERE branch_id = ${childId} UNION ALL SELECT pg_column_size(t.*) AS sz FROM stock t WHERE branch_id = ${childId} UNION ALL SELECT pg_column_size(t.*) AS sz FROM scheduled_effect t WHERE branch_id = ${childId}) sub;"
            $child_state_kb = [double]((Invoke-Psql -Db $Database -Command $stateKbSql -TuplesOnly).Trim())

            # read_ms: median of 3 timings of SELECT branch_projection_digest(<child>)
            $readTimes = @()
            for ($r = 0; $r -lt 3; $r++) {
                $outText = Invoke-Psql -Db $Database -Command "SELECT branch_projection_digest(${childId});" -Timing
                $t = 0.0
                if ($outText -match '(?i)Time:\s*([0-9]+(?:\.[0-9]+)?)\s*ms') {
                    $t = [double]$Matches[1]
                }
                $readTimes += $t
            }
            $sortedReadTimes = $readTimes | Sort-Object
            $read_ms = [math]::Round([double]$sortedReadTimes[1], 2)

            $branchingRow = "${S},${events},${scenario},${strategy},${fork_ms},${replayedEvents},${digest_ok},${child_entity_rows},${child_stock_rows},${child_state_kb},${read_ms}"
            Add-Content -Path $branchingCsvPath -Value $branchingRow -Encoding UTF8
            Write-Host "Recorded branching row: ${branchingRow}"
        }

        # 5. Snapshot storage for size S
        Write-StepBanner "Collecting snapshot storage metrics for main branch"
        $snapshots = [int64]((Invoke-Psql -Db $Database -Command "SELECT count(*) FROM snapshot WHERE branch_id = ${mainId};" -TuplesOnly).Trim())
        $snapKbSql = "SELECT round(COALESCE(sum(pg_column_size(state)), 0)::numeric / 1024.0, 1) FROM snapshot WHERE branch_id = ${mainId};"
        $snapshot_kb = [double]((Invoke-Psql -Db $Database -Command $snapKbSql -TuplesOnly).Trim())
        $parent_entity_rows = [int64]((Invoke-Psql -Db $Database -Command "SELECT count(*) FROM entity_state WHERE branch_id = ${mainId};" -TuplesOnly).Trim())

        $snapshotsRow = "${S},${events},${snapshots},${snapshot_kb},${parent_entity_rows}"
        Add-Content -Path $snapshotsCsvPath -Value $snapshotsRow -Encoding UTF8
        Write-Host "Recorded snapshots row: ${snapshotsRow}"
    }

    # Clean up benchmark database at the end
    Write-StepBanner "Dropping benchmark database ${Database}"
    $null = Invoke-Psql -Db "postgres" -Command "DROP DATABASE IF EXISTS ${Database} WITH (FORCE);"

    # Print results tables
    Write-Host ""
    Write-Host "================================================================================"
    Write-Host "Experiment 4: Branching Strategies Results (${branchingCsvPath})"
    Write-Host "================================================================================"
    Import-Csv -Path $branchingCsvPath | Select-Object days,scenario,strategy,fork_ms,replayed_events,digest_ok,child_entity_rows,child_state_kb | Format-Table -AutoSize

    Write-Host ""
    Write-Host "================================================================================"
    Write-Host "Experiment 4: Snapshot Storage Results (${snapshotsCsvPath})"
    Write-Host "================================================================================"
    Import-Csv -Path $snapshotsCsvPath | Format-Table -AutoSize
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
    # Keep benchmark database in place on error; cleanup only occurs upon success in try block.
}
