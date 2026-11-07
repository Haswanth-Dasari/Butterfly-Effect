[CmdletBinding()]
param(
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
$csvPath = Join-Path $resultsDir "exp3_askwhy.csv"
$csvHeader = "sweep,events,depth,chains,closure_rows,closure_rows_ok,up_cte_ms,up_closure_ms,up_path_ms,down_cte_ms,down_closure_ms,down_path_ms,write_base_ms,write_closure_ms,edges_mb,closure_mb,path_mb"
Set-Content -Path $csvPath -Value $csvHeader -Encoding UTF8

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

function Measure-ExplainAnalyze {
    param(
        [string]$Db,
        [string]$Sql
    )
    # 1 warm-up run
    $null = Invoke-Psql -Db $Db -Command "EXPLAIN (ANALYZE) ${Sql}"

    # 5 timed runs
    $times = @()
    for ($i = 0; $i -lt 5; $i++) {
        $planText = Invoke-Psql -Db $Db -Command "EXPLAIN (ANALYZE) ${Sql}"
        $t = 0.0
        if ($planText -match '(?i)Execution Time:\s*([0-9]+(?:\.[0-9]+)?)\s*ms') {
            $t = [double]$Matches[1]
        }
        $times += $t
    }
    $sortedTimes = $times | Sort-Object
    return [math]::Round([double]$sortedTimes[2], 3)
}

# Define configuration sweeps
if ($Quick) {
    $configs = @(
        @{ Sweep = "depth"; Events = 10000; Depth = 2 },
        @{ Sweep = "both";  Events = 10000; Depth = 8 },
        @{ Sweep = "depth"; Events = 10000; Depth = 32 }
    )
} else {
    $configs = @(
        @{ Sweep = "depth"; Events = 100000; Depth = 2 },
        @{ Sweep = "depth"; Events = 100000; Depth = 4 },
        @{ Sweep = "both";  Events = 100000; Depth = 8 },
        @{ Sweep = "depth"; Events = 100000; Depth = 16 },
        @{ Sweep = "depth"; Events = 100000; Depth = 32 },
        @{ Sweep = "depth"; Events = 100000; Depth = 64 },
        @{ Sweep = "size";  Events = 10000;  Depth = 8 },
        @{ Sweep = "size";  Events = 1000000; Depth = 8 }
    )
}

$isFirstConfig = $true

try {
    foreach ($cfg in $configs) {
        $sweep = $cfg.Sweep
        $N = $cfg.Events
        $D = $cfg.Depth

        Write-StepBanner "Starting configuration: Sweep=${sweep}, Events=${N}, Depth=${D}"

        # 1. Recreate database (two separate psql calls)
        Write-StepBanner "Recreating benchmark database ${Database}"
        Write-Host "Dropping database ${Database} if exists..."
        $null = Invoke-Psql -Db "postgres" -Command "DROP DATABASE IF EXISTS ${Database} WITH (FORCE);"
        Write-Host "Creating database ${Database}..."
        $null = Invoke-Psql -Db "postgres" -Command "CREATE DATABASE ${Database};"

        Write-StepBanner "Applying db/schema/_all.sql"
        $null = Invoke-Psql -Db $Database -File "db/schema/_all.sql"

        Write-StepBanner "Applying db/seed/_seed_all.sql"
        $null = Invoke-Psql -Db $Database -File "db/seed/_seed_all.sql"

        Write-StepBanner "Applying db/schema/08_indexes_drop.sql (unindexed state for bulk load)"
        $null = Invoke-Psql -Db $Database -File "db/schema/08_indexes_drop.sql"

        Write-StepBanner "Applying experiments/benchmarks/causal_load.sql"
        $null = Invoke-Psql -Db $Database -File "experiments/benchmarks/causal_load.sql"

        Write-StepBanner "Executing bench_causal_load(${N}, ${D})"
        $null = Invoke-Psql -Db $Database -Command "SELECT bench_causal_load(${N}, ${D});"

        Write-StepBanner "Applying db/schema/08_indexes.sql"
        $null = Invoke-Psql -Db $Database -File "db/schema/08_indexes.sql"

        Write-StepBanner "Running ANALYZE"
        $null = Invoke-Psql -Db $Database -Command "ANALYZE;"

        # 2. For the FIRST configuration only: verify consistency of causal structures
        if ($isFirstConfig) {
            Write-StepBanner "Verifying consistency of causal structures on first configuration"
            $verifyCountRaw = (Invoke-Psql -Db $Database -Command "SELECT count(*) FROM verify_causal_structures();" -TuplesOnly).Trim()
            $verifyCount = [int64]$verifyCountRaw
            if ($verifyCount -ne 0) {
                $details = Invoke-Psql -Db $Database -Command "SELECT kind, detail FROM verify_causal_structures();"
                throw "verify_causal_structures() returned ${verifyCount} inconsistencies:`n${details}"
            }
            Write-Host "Causal structures verified successfully (0 inconsistencies)."
            $isFirstConfig = $false
        }

        # 3. Consistency check
        Write-StepBanner "Validating causal closure and path row counts"
        $chains = [math]::Floor($N / ($D + 1))
        $closureRowsRaw = (Invoke-Psql -Db $Database -Command "SELECT count(*) FROM causal_closure;" -TuplesOnly).Trim()
        $closure_rows = [int64]$closureRowsRaw
        $expected = [int64]($chains * ($D + 1) * ($D + 2) / 2)
        $closure_rows_ok = "false"
        if ($closure_rows -eq $expected) {
            $closure_rows_ok = "true"
        }
        $pathRowsRaw = (Invoke-Psql -Db $Database -Command "SELECT count(*) FROM causal_path;" -TuplesOnly).Trim()
        $path_rows = [int64]$pathRowsRaw
        Write-Host "Chains: ${chains}, Closure rows: ${closure_rows} (Expected: ${expected}, OK: ${closure_rows_ok}), Path rows: ${path_rows}"

        # 4. Parameters computation
        Write-StepBanner "Computing query parameters MIDC, HEAD, TAIL"
        $midc = [math]::Floor($chains / 2)
        $vBaseRaw = (Invoke-Psql -Db $Database -Command "SELECT min(event_id) FROM event WHERE action_type = 'steal';" -TuplesOnly).Trim()
        $vBase = [int64]$vBaseRaw - 1
        $head = $vBase + $midc * ($D + 1) + 1
        $tail = $head + $D
        Write-Host "Parameters: V_BASE=${vBase}, MIDC=${midc}, HEAD=${head}, TAIL=${tail}"

        # 5. Reads (EXPLAIN ANALYZE queries: warm-up then 5 timed runs, median)
        Write-StepBanner "Measuring upward provenance queries (TAIL=${tail})"
        $qUpCte = "WITH RECURSIVE up AS (SELECT cause_id AS event_id, 1 AS depth FROM event_cause WHERE effect_id = ${tail} UNION ALL SELECT ec.cause_id, up.depth + 1 FROM event_cause ec JOIN up ON ec.effect_id = up.event_id) SELECT event_id, MIN(depth) FROM up GROUP BY event_id;"
        $up_cte_ms = Measure-ExplainAnalyze -Db $Database -Sql $qUpCte
        Write-Host "  up_cte_ms: ${up_cte_ms}"

        $qUpClosure = "SELECT ancestor_id, depth FROM causal_closure WHERE descendant_id = ${tail} AND depth > 0;"
        $up_closure_ms = Measure-ExplainAnalyze -Db $Database -Sql $qUpClosure
        Write-Host "  up_closure_ms: ${up_closure_ms}"

        $qUpPath = "SELECT t.id::bigint, array_length(a.arr, 1) - t.pos AS depth FROM (SELECT string_to_array(path, '/') AS arr FROM causal_path WHERE event_id = ${tail}) a, unnest(a.arr) WITH ORDINALITY AS t(id, pos) WHERE t.pos < array_length(a.arr, 1);"
        $up_path_ms = Measure-ExplainAnalyze -Db $Database -Sql $qUpPath
        Write-Host "  up_path_ms: ${up_path_ms}"

        Write-StepBanner "Measuring downward provenance queries (HEAD=${head})"
        $qDownCte = "WITH RECURSIVE down AS (SELECT effect_id AS event_id, 1 AS depth FROM event_cause WHERE cause_id = ${head} UNION ALL SELECT ec.effect_id, down.depth + 1 FROM event_cause ec JOIN down ON ec.cause_id = down.event_id) SELECT count(*) FROM down;"
        $down_cte_ms = Measure-ExplainAnalyze -Db $Database -Sql $qDownCte
        Write-Host "  down_cte_ms: ${down_cte_ms}"

        $qDownClosure = "SELECT count(*) FROM causal_closure WHERE ancestor_id = ${head} AND depth > 0;"
        $down_closure_ms = Measure-ExplainAnalyze -Db $Database -Sql $qDownClosure
        Write-Host "  down_closure_ms: ${down_closure_ms}"

        $qDownPath = "SELECT count(*) FROM causal_path WHERE path LIKE '${head}/%';"
        $down_path_ms = Measure-ExplainAnalyze -Db $Database -Sql $qDownPath
        Write-Host "  down_path_ms: ${down_path_ms}"

        # 6. Storage in MB
        Write-StepBanner "Measuring causal tables storage sizes"
        $edgesMbRaw = (Invoke-Psql -Db $Database -Command "SELECT round(pg_total_relation_size('event_cause')::numeric / 1048576.0, 2);" -TuplesOnly).Trim()
        $closureMbRaw = (Invoke-Psql -Db $Database -Command "SELECT round(pg_total_relation_size('causal_closure')::numeric / 1048576.0, 2);" -TuplesOnly).Trim()
        $pathMbRaw = (Invoke-Psql -Db $Database -Command "SELECT round(pg_total_relation_size('causal_path')::numeric / 1048576.0, 2);" -TuplesOnly).Trim()
        $edges_mb = [math]::Round([double]$edgesMbRaw, 2)
        $closure_mb = [math]::Round([double]$closureMbRaw, 2)
        $path_mb = [math]::Round([double]$pathMbRaw, 2)
        Write-Host "Storage: edges_mb=${edges_mb}, closure_mb=${closure_mb}, path_mb=${path_mb}"

        # 7. Writes
        Write-StepBanner "Measuring causal write costs"
        $writeOps = 200
        $disabledFirstChain = 200
        if ($Quick) {
            $writeOps = 50
            $disabledFirstChain = 200
        }

        $writeClosureRaw = (Invoke-Psql -Db $Database -Command "SELECT bench_causal_write(${writeOps}, 0, ${D}, true);" -TuplesOnly).Trim()
        $write_closure_ms = [double]$writeClosureRaw

        $writeBaseRaw = (Invoke-Psql -Db $Database -Command "SELECT bench_causal_write(${writeOps}, ${disabledFirstChain}, ${D}, false);" -TuplesOnly).Trim()
        $write_base_ms = [double]$writeBaseRaw
        Write-Host "Write cost: write_base_ms=${write_base_ms}, write_closure_ms=${write_closure_ms}"

        # Append row to CSV
        $row = "${sweep},${N},${D},${chains},${closure_rows},${closure_rows_ok},${up_cte_ms},${up_closure_ms},${up_path_ms},${down_cte_ms},${down_closure_ms},${down_path_ms},${write_base_ms},${write_closure_ms},${edges_mb},${closure_mb},${path_mb}"
        Add-Content -Path $csvPath -Value $row -Encoding UTF8
        Write-Host "Recorded: ${row}"
    }

    # Clean up benchmark database at the end
    Write-StepBanner "Dropping benchmark database ${Database}"
    $null = Invoke-Psql -Db "postgres" -Command "DROP DATABASE IF EXISTS ${Database} WITH (FORCE);"

    # Print results tables
    Write-Host ""
    Write-Host "================================================================================"
    Write-Host "Experiment 3: Upward Provenance Queries (exp3_askwhy.csv)"
    Write-Host "================================================================================"
    Import-Csv -Path $csvPath | Select-Object sweep,events,depth,closure_rows_ok,up_cte_ms,up_closure_ms,up_path_ms | Format-Table -AutoSize

    Write-Host ""
    Write-Host "================================================================================"
    Write-Host "Experiment 3: Downward Provenance Queries"
    Write-Host "================================================================================"
    Import-Csv -Path $csvPath | Select-Object sweep,events,depth,down_cte_ms,down_closure_ms,down_path_ms | Format-Table -AutoSize

    Write-Host ""
    Write-Host "================================================================================"
    Write-Host "Experiment 3: Write Cost and Storage"
    Write-Host "================================================================================"
    Import-Csv -Path $csvPath | Select-Object sweep,events,depth,write_base_ms,write_closure_ms,edges_mb,closure_mb,path_mb | Format-Table -AutoSize
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
