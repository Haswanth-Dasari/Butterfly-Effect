[CmdletBinding()]
param(
    [int64[]]$Sizes = @(10000, 100000, 1000000),
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

# Prepare results directory and overwrite CSV files at the start
$resultsDir = "experiments/results"
if (-not (Test-Path $resultsDir)) {
    New-Item -ItemType Directory -Path $resultsDir -Force | Out-Null
}

$queriesCsvPath = Join-Path $resultsDir "exp5_index_queries.csv"
$summaryCsvPath = Join-Path $resultsDir "exp5_index_summary.csv"

$queriesHeader = "events,query,description,before_ms,after_ms,speedup,before_scan,after_scan"
$summaryHeader = "events,index_build_seconds,index_size_mb,table_size_mb,engine_write_before_ms,engine_write_after_ms"

Set-Content -Path $queriesCsvPath -Value $queriesHeader -Encoding UTF8
Set-Content -Path $summaryCsvPath -Value $summaryHeader -Encoding UTF8

$script:LastPsqlOutput = ""
$currentStep = "Initialization"

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

function Get-ScanType {
    param([string]$PlanText)
    if ($PlanText -match 'Seq Scan') {
        return 'Seq'
    } elseif ($PlanText -match 'Index Only Scan') {
        return 'IndexOnly'
    } elseif (($PlanText -match 'Index Scan') -or ($PlanText -match 'Bitmap')) {
        return 'Index'
    } else {
        return 'Other'
    }
}

function Measure-QueryPlan {
    param(
        [string]$Db,
        [string]$Sql
    )
    # Warm-up run
    $null = Invoke-Psql -Db $Db -Command $Sql

    # Three timed runs
    $times = @()
    $lastPlan = ""
    for ($i = 0; $i -lt 3; $i++) {
        $planText = Invoke-Psql -Db $Db -Command $Sql
        $lastPlan = $planText
        $t = 0.0
        if ($planText -match '(?i)Execution Time:\s*([0-9]+(?:\.[0-9]+)?)\s*ms') {
            $t = [double]$Matches[1]
        }
        $times += $t
    }

    $sortedTimes = $times | Sort-Object
    $medianTime = $sortedTimes[1]
    $scanType = Get-ScanType -PlanText $lastPlan

    return @{
        MedianMs = [math]::Round($medianTime, 2)
        ScanType = $scanType
        PlanText = $lastPlan
    }
}

function Measure-EngineWrite {
    param([string]$Db)
    $argsList = @("-X", "-U", $User, "-d", $Db, "-c", "\timing on", "-c", "SELECT bench_generate(20);")
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
        throw "bench_generate(20) failed: $outText"
    }
    $ms = "0"
    if ($outText -match 'Time:\s*([0-9]+(?:\.[0-9]+)?)\s*ms') {
        $ms = $Matches[1]
    }
    return [math]::Round([double]$ms, 2)
}

$isFirstSize = $true
$largestSize = ($Sizes | Measure-Object -Maximum).Maximum

try {
    foreach ($N in $Sizes) {
        Write-Host "================================================================================"
        Write-Host "Experiment 5: Benchmarking dataset size N = $N"
        Write-Host "================================================================================"

        # 1. Drop and create benchmark database
        $currentStep = "Recreating database ${Database}"
        Write-Host "Recreating database ${Database}..."
        $null = Invoke-Psql -Db "postgres" -Command "DROP DATABASE IF EXISTS ${Database} WITH (FORCE);"
        $null = Invoke-Psql -Db "postgres" -Command "CREATE DATABASE ${Database};"

        # 2. In <db> run in order: schema, seed, indexes drop, bench_generate, bulk_load, then load and analyze
        $currentStep = "Applying db/schema/_all.sql"
        Write-Host "Applying db/schema/_all.sql..."
        $null = Invoke-Psql -Db $Database -File "db/schema/_all.sql"

        $currentStep = "Applying db/seed/_seed_all.sql"
        Write-Host "Applying db/seed/_seed_all.sql..."
        $null = Invoke-Psql -Db $Database -File "db/seed/_seed_all.sql"

        $currentStep = "Applying db/schema/08_indexes_drop.sql (recreating 'before' unindexed state)"
        Write-Host "Recreating 'before' state via db/schema/08_indexes_drop.sql..."
        $null = Invoke-Psql -Db $Database -File "db/schema/08_indexes_drop.sql"

        $currentStep = "Applying experiments/recovery/bench_generate.sql"
        Write-Host "Applying experiments/recovery/bench_generate.sql..."
        $null = Invoke-Psql -Db $Database -File "experiments/recovery/bench_generate.sql"

        $currentStep = "Applying experiments/benchmarks/bulk_load.sql"
        Write-Host "Applying experiments/benchmarks/bulk_load.sql..."
        $null = Invoke-Psql -Db $Database -File "experiments/benchmarks/bulk_load.sql"

        $currentStep = "Executing bench_bulk_load($N)"
        Write-Host "Bulk loading $N events..."
        $null = Invoke-Psql -Db $Database -Command "SELECT bench_bulk_load($N);"

        $currentStep = "Running ANALYZE before index creation"
        Write-Host "Running ANALYZE..."
        $null = Invoke-Psql -Db $Database -Command "ANALYZE;"

        # 3. For the FIRST size only: verify consistency of causal structures
        if ($isFirstSize) {
            $currentStep = "Verifying consistency of causal structures"
            Write-Host "Verifying causal structures consistency on first dataset size..."
            $verifyCountRaw = (Invoke-Psql -Db $Database -Command "SELECT count(*) FROM verify_causal_structures();" -TuplesOnly).Trim()
            $verifyCount = [int64]$verifyCountRaw
            if ($verifyCount -ne 0) {
                $details = Invoke-Psql -Db $Database -Command "SELECT kind, detail FROM verify_causal_structures();"
                throw "verify_causal_structures() returned $verifyCount inconsistencies:`n$details"
            }
            Write-Host "Causal structures verified successfully (0 inconsistencies)."
            $isFirstSize = $false
        }

        # 4. Discover parameters
        $currentStep = "Discovering query parameters"
        Write-Host "Discovering query parameters..."
        $t2Raw = (Invoke-Psql -Db $Database -Command "SELECT COALESCE(MAX(tick), 0) FROM event WHERE branch_id = 2;" -TuplesOnly).Trim()
        $t2 = [int64]$t2Raw
        $mid = [math]::Floor($t2 / 2)

        $offsetVal = [math]::Floor($N / 8)
        $deepSql = "SELECT descendant_id FROM causal_closure WHERE depth = 3 ORDER BY descendant_id OFFSET $offsetVal LIMIT 1;"
        $deepRaw = (Invoke-Psql -Db $Database -Command $deepSql -TuplesOnly).Trim()
        $deep = [int64]$deepRaw
        $head = $deep - 3

        Write-Host "Parameters: T2 = $t2, MID = $mid, DEEP = $deep, HEAD = $head"

        # 5. Build queries list
        $queryDefs = @(
            @{
                Id = "Q1"
                Desc = "range"
                Sql = "EXPLAIN (ANALYZE) SELECT count(*) FROM event WHERE branch_id = 2 AND tick BETWEEN $mid AND $($mid + 10);"
            },
            @{
                Id = "Q2"
                Desc = "current_tick"
                Sql = "EXPLAIN (ANALYZE) SELECT COALESCE(MAX(tick),0) FROM event WHERE branch_id = 3;"
            },
            @{
                Id = "Q3"
                Desc = "chain_prev"
                Sql = "EXPLAIN (ANALYZE) SELECT hash FROM event WHERE branch_id = 4 ORDER BY event_id DESC LIMIT 1;"
            },
            @{
                Id = "Q4"
                Desc = "ask_why_recursive"
                Sql = "EXPLAIN (ANALYZE) WITH RECURSIVE up AS (SELECT cause_id AS event_id, 1 AS depth FROM event_cause WHERE effect_id = $deep UNION ALL SELECT ec.cause_id, up.depth + 1 FROM event_cause ec JOIN up ON ec.effect_id = up.event_id) SELECT event_id, MIN(depth) FROM up GROUP BY event_id;"
            },
            @{
                Id = "Q5"
                Desc = "closure"
                Sql = "EXPLAIN (ANALYZE) SELECT ancestor_id, depth FROM causal_closure WHERE descendant_id = $deep AND depth > 0;"
            },
            @{
                Id = "Q6"
                Desc = "downward"
                Sql = "EXPLAIN (ANALYZE) SELECT effect_id FROM event_cause WHERE cause_id = $head;"
            },
            @{
                Id = "Q7"
                Desc = "path_prefix"
                Sql = "EXPLAIN (ANALYZE) SELECT count(*) FROM causal_path WHERE path LIKE '$head/%';"
            },
            @{
                Id = "Q8"
                Desc = "witness_by_actor"
                Sql = "EXPLAIN (ANALYZE) SELECT count(*) FROM event_witness WHERE actor_id = 7;"
            },
            @{
                Id = "Q9"
                Desc = "player_rls"
                Sql = "BEGIN; SET LOCAL ROLE player_role; SELECT set_config('app.actor_id','7',true); EXPLAIN (ANALYZE) SELECT count(*) FROM event WHERE branch_id = 2 AND tick BETWEEN $mid AND $($mid + 10); ROLLBACK;"
            },
            @{
                Id = "Q10"
                Desc = "pending_claim"
                Sql = "EXPLAIN (ANALYZE) SELECT scheduled_id FROM scheduled_effect WHERE branch_id = 2 AND NOT processed AND due_tick <= $mid ORDER BY due_tick, scheduled_id LIMIT 10;"
            },
            @{
                Id = "Q11"
                Desc = "open_row"
                Sql = "EXPLAIN (ANALYZE) SELECT state FROM entity_state WHERE entity_id = 5 AND branch_id = 1 AND upper_inf(valid_ticks);"
            }
        )

        # 6. Measure 'before' phase query suite
        $currentStep = "Measuring 'before' query suite"
        Write-Host "Running 'before' query suite (unindexed)..."
        $beforeResults = @{}
        foreach ($q in $queryDefs) {
            $qid = $q.Id
            $qDesc = $q.Desc
            $qSql = $q.Sql
            Write-Host "  Measuring $qid ($qDesc)..."
            $meas = Measure-QueryPlan -Db $Database -Sql $qSql
            $beforeResults[$qid] = @{
                Desc = $qDesc
                MedianMs = $meas.MedianMs
                ScanType = $meas.ScanType
                PlanText = $meas.PlanText
            }
        }

        # 7. Write cost 'before'
        $currentStep = "Measuring write cost before indexes"
        Write-Host "Measuring engine write cost before indexes (bench_generate(20))..."
        $engineWriteBeforeMs = Measure-EngineWrite -Db $Database
        Write-Host "Engine write cost before: $engineWriteBeforeMs ms"

        # 8. Create indexes, time build, analyze, collect index and table sizes
        $currentStep = "Building secondary and partial indexes"
        Write-Host "Building secondary and partial indexes from db/schema/08_indexes.sql..."
        $swIndex = [System.Diagnostics.Stopwatch]::StartNew()
        $null = Invoke-Psql -Db $Database -File "db/schema/08_indexes.sql"
        $swIndex.Stop()
        $indexBuildSeconds = [math]::Round($swIndex.Elapsed.TotalSeconds, 2)
        Write-Host "Index build completed in $indexBuildSeconds seconds."

        $currentStep = "Running ANALYZE after index creation"
        Write-Host "Running ANALYZE after index build..."
        $null = Invoke-Psql -Db $Database -Command "ANALYZE;"

        $currentStep = "Collecting index and table sizes"
        $indexSizeSql = @"
SELECT COALESCE(round(sum(pg_relation_size(c.oid))::numeric / (1024 * 1024), 2), 0)
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relname IN (
      'event_branch_tick_idx',
      'event_branch_event_idx',
      'event_cause_cause_idx',
      'causal_closure_desc_idx',
      'causal_path_prefix_idx',
      'event_witness_actor_idx',
      'scheduled_pending_idx',
      'entity_state_open_idx',
      'snapshot_branch_event_idx'
  );
"@
        $indexSizeMb = [double]((Invoke-Psql -Db $Database -Command $indexSizeSql -TuplesOnly).Trim())

        $tableSizeSql = @"
SELECT COALESCE(round(sum(pg_total_relation_size(c.oid))::numeric / (1024 * 1024), 2), 0)
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relname IN (
      'event',
      'event_cause',
      'event_witness',
      'causal_closure',
      'causal_path'
  );
"@
        $tableSizeMb = [double]((Invoke-Psql -Db $Database -Command $tableSizeSql -TuplesOnly).Trim())

        Write-Host "Storage: index_size_mb = $indexSizeMb MB, table_size_mb = $tableSizeMb MB"

        # 9. Measure 'after' phase query suite and write cost 'after'
        $currentStep = "Measuring 'after' query suite"
        Write-Host "Running 'after' query suite (indexed)..."
        $afterResults = @{}
        foreach ($q in $queryDefs) {
            $qid = $q.Id
            $qDesc = $q.Desc
            $qSql = $q.Sql
            Write-Host "  Measuring $qid ($qDesc)..."
            $meas = Measure-QueryPlan -Db $Database -Sql $qSql
            $afterResults[$qid] = @{
                Desc = $qDesc
                MedianMs = $meas.MedianMs
                ScanType = $meas.ScanType
                PlanText = $meas.PlanText
            }
        }

        $currentStep = "Measuring write cost after indexes"
        Write-Host "Measuring engine write cost after indexes (bench_generate(20))..."
        $engineWriteAfterMs = Measure-EngineWrite -Db $Database
        Write-Host "Engine write cost after: $engineWriteAfterMs ms"

        # 10. Record CSV rows and save plans for largest size
        foreach ($q in $queryDefs) {
            $qid = $q.Id
            $qDesc = $q.Desc
            $beforeRes = $beforeResults[$qid]
            $afterRes = $afterResults[$qid]

            $bMs = $beforeRes.MedianMs
            $aMs = $afterRes.MedianMs

            $speedup = 0.0
            if ($aMs -gt 0) {
                $speedup = [math]::Round(($bMs / $aMs), 1)
            } else {
                $speedup = [math]::Round($bMs, 1)
            }

            $queryRow = "$N,$qid,$qDesc,$bMs,$aMs,$speedup,$($beforeRes.ScanType),$($afterRes.ScanType)"
            Add-Content -Path $queriesCsvPath -Value $queryRow -Encoding UTF8
        }

        $summaryRow = "$N,$indexBuildSeconds,$indexSizeMb,$tableSizeMb,$engineWriteBeforeMs,$engineWriteAfterMs"
        Add-Content -Path $summaryCsvPath -Value $summaryRow -Encoding UTF8

        if ($N -eq $largestSize) {
            $planFilePath = Join-Path $resultsDir "exp5_plans_$N.txt"
            $planLines = @()
            $planLines += "================================================================================"
            $planLines += "EXPLAIN (ANALYZE) Query Plans for Dataset Size N = $N"
            $planLines += "================================================================================"
            $planLines += ""
            $planLines += "################################################################################"
            $planLines += "PHASE 1: BEFORE INDEXES"
            $planLines += "################################################################################"
            $planLines += ""
            foreach ($q in $queryDefs) {
                $qid = $q.Id
                $res = $beforeResults[$qid]
                $planLines += "--------------------------------------------------------------------------------"
                $planLines += "Query: $qid ($($res.Desc)) [Scan: $($res.ScanType), Median Time: $($res.MedianMs) ms]"
                $planLines += "--------------------------------------------------------------------------------"
                $planLines += $res.PlanText
                $planLines += ""
            }
            $planLines += "################################################################################"
            $planLines += "PHASE 2: AFTER INDEXES"
            $planLines += "################################################################################"
            $planLines += ""
            foreach ($q in $queryDefs) {
                $qid = $q.Id
                $res = $afterResults[$qid]
                $planLines += "--------------------------------------------------------------------------------"
                $planLines += "Query: $qid ($($res.Desc)) [Scan: $($res.ScanType), Median Time: $($res.MedianMs) ms]"
                $planLines += "--------------------------------------------------------------------------------"
                $planLines += $res.PlanText
                $planLines += ""
            }
            Set-Content -Path $planFilePath -Value $planLines -Encoding UTF8
            Write-Host "Saved full EXPLAIN ANALYZE plans to $planFilePath"
        }
    }

    # At the end of all sizes, drop the benchmark database
    $currentStep = "Dropping benchmark database $Database"
    Write-Host "Dropping benchmark database $Database..."
    $null = Invoke-Psql -Db "postgres" -Command "DROP DATABASE IF EXISTS $Database WITH (FORCE);"

    # Print both CSV outputs
    Write-Host ""
    Write-Host "================================================================================"
    Write-Host "Experiment 5: Index Impact - Query Results ($queriesCsvPath)"
    Write-Host "================================================================================"
    Import-Csv -Path $queriesCsvPath | Select-Object events, query, before_ms, after_ms, speedup, after_scan | Format-Table -AutoSize

    Write-Host ""
    Write-Host "================================================================================"
    Write-Host "Experiment 5: Index Impact - Summary ($summaryCsvPath)"
    Write-Host "================================================================================"
    Import-Csv -Path $summaryCsvPath | Format-Table -AutoSize
}
catch {
    Write-Host ""
    Write-Error "ERROR during step '$currentStep': $($_.Exception.Message)"
    if (-not [string]::IsNullOrWhiteSpace($script:LastPsqlOutput)) {
        Write-Host "Last psql output:"
        Write-Host $script:LastPsqlOutput
    }
    Write-Host "Benchmark database '$Database' left in place for inspection."
    exit 1
}
