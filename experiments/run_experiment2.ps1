[CmdletBinding()]
param(
    [string]$Database = "butterfly",
    [string]$User = "postgres",
    [int]$Clients = 4,
    [int]$TxPerClient = 25
)

# Password check: script requires $env:PGPASSWORD to be set
if ([string]::IsNullOrWhiteSpace($env:PGPASSWORD)) {
    Write-Error "ERROR: Environment variable PGPASSWORD is not set. Please set `$env:PGPASSWORD before running this script."
    exit 1
}

# Dependency checks: psql and pgbench must be available
if (-not (Get-Command psql -ErrorAction SilentlyContinue)) {
    Write-Error "ERROR: 'psql' command not found in PATH."
    exit 1
}
if (-not (Get-Command pgbench -ErrorAction SilentlyContinue)) {
    Write-Error "ERROR: 'pgbench' command not found in PATH."
    exit 1
}

$ScriptDir = $PSScriptRoot
if (-not $ScriptDir) {
    $ScriptDir = "."
}

# Resolve lab schema script
$labSql = "experiments/lab/00_lab.sql"
if (-not (Test-Path $labSql)) {
    $labSql = Join-Path $ScriptDir "lab\00_lab.sql"
}

Write-Host "Initializing lab schema with $labSql..."
& psql -X -v ON_ERROR_STOP=1 -U $User -d $Database -f $labSql
if ($LASTEXITCODE -ne 0) {
    Write-Error "ERROR: Failed to initialize schema from $labSql"
    exit 1
}

# Prepare results directory and CSV file
$resultsDir = "experiments/results"
if (-not (Test-Path $resultsDir)) {
    $resultsDir = Join-Path $ScriptDir "results"
    if (-not (Test-Path $resultsDir)) {
        New-Item -ItemType Directory -Path $resultsDir -Force | Out-Null
    }
}
$csvPath = Join-Path $resultsDir "exp2_deadlock.csv"

# Write CSV header at the start
$csvHeader = "variant,clients,processed,failed,deadlock_failures,serialization_failures,tps,sum_coins,conserved,ledger_consistent"
Set-Content -Path $csvPath -Value $csvHeader -Encoding UTF8

$variants = @(
    @{ Name = 'unordered'; Script = 'transfer_unordered.sql' },
    @{ Name = 'ordered'; Script = 'transfer_ordered.sql' }
)

$results = @()

$origPgOptions = $env:PGOPTIONS
try {
    # Set deadlock_timeout for the duration of the experiment runs
    $env:PGOPTIONS = "-c deadlock_timeout=100ms"

    foreach ($v in $variants) {
        $varName = $v.Name
        $scriptFile = $v.Script

        # Resolve benchmark script path
        $benchFile = "experiments/pgbench/$scriptFile"
        if (-not (Test-Path $benchFile)) {
            $benchFile = Join-Path $ScriptDir "pgbench\$scriptFile"
        }

        Write-Host "Running Variant: $varName | Clients: $Clients | Tx/Client: $TxPerClient..."

        # Reset purses before each variant run
        & psql -X -v ON_ERROR_STOP=1 -U $User -d $Database -c "SELECT lab.reset_purses();" | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Error "ERROR: Failed to reset purses."
            exit 1
        }

        # Run pgbench with -n -c <Clients> -j 2 -t <TxPerClient> -f <script> --failures-detailed --max-tries=1
        $outputLines = & pgbench -n -U $User -d $Database -c $Clients -j 2 -t $TxPerClient -f $benchFile --failures-detailed --max-tries=1 2>&1 | ForEach-Object { "$_" }
        $benchText = $outputLines -join "`n"

        # Parse metrics with regexes
        $processed = 0
        if ($benchText -match 'number of transactions actually processed:\s*(\d+)/(\d+)') {
            $processed = [int64]$Matches[1]
        } elseif ($benchText -match 'number of transactions actually processed:\s*(\d+)') {
            $processed = [int64]$Matches[1]
        }

        $failed = 0
        if ($benchText -match 'number of failed transactions:\s*(\d+)') {
            $failed = [int64]$Matches[1]
        }

        $deadlock_failures = 0
        if ($benchText -match 'number of deadlock failures:\s*(\d+)') {
            $deadlock_failures = [int64]$Matches[1]
        }

        $serialization_failures = 0
        if ($benchText -match 'number of serialization failures:\s*(\d+)') {
            $serialization_failures = [int64]$Matches[1]
        }

        $tps = 0.0
        if ($benchText -match 'tps\s*=\s*([\d\.]+)\s*\(without initial connection time\)') {
            $tps = [double]$Matches[1]
        } elseif ($benchText -match 'tps\s*=\s*([\d\.]+)') {
            $tps = [double]$Matches[1]
        }

        # Query state after run
        $sumCoinsRaw = (& psql -X -A -t -U $User -d $Database -c "SELECT COALESCE(SUM(coins), 0) FROM lab.purse;" 2>&1 | ForEach-Object { "$_" }) -join ""
        $coinsMatch = [regex]::Match($sumCoinsRaw, '(-?\d+)')
        $sum_coins = 0
        if ($coinsMatch.Success) {
            $sum_coins = [int64]$coinsMatch.Groups[1].Value
        }

        $isConserved = ($sum_coins -eq 200)
        $conserved = "false"
        if ($isConserved) {
            $conserved = "true"
        }

        $ledgerQuery = "SELECT (COUNT(*) = 2 AND BOOL_AND(coins = 100 + COALESCE((SELECT SUM(amt) FROM lab.transfer_log WHERE to_owner = p.owner), 0) - COALESCE((SELECT SUM(amt) FROM lab.transfer_log WHERE from_owner = p.owner), 0))) FROM lab.purse p;"
        $ledgerRaw = (& psql -X -A -t -U $User -d $Database -c $ledgerQuery 2>&1 | ForEach-Object { "$_" }) -join ""
        $isLedgerConsistent = ($ledgerRaw.Trim() -eq "t" -or $ledgerRaw.Trim() -eq "true")
        $ledger_consistent = "false"
        if ($isLedgerConsistent) {
            $ledger_consistent = "true"
        }

        # Append row to CSV
        $csvLine = "$varName,$Clients,$processed,$failed,$deadlock_failures,$serialization_failures,$tps,$sum_coins,$conserved,$ledger_consistent"
        Add-Content -Path $csvPath -Value $csvLine -Encoding UTF8

        # Record result object
        $rowObj = [PSCustomObject]@{
            variant                = $varName
            clients                = $Clients
            processed              = $processed
            failed                 = $failed
            deadlock_failures      = $deadlock_failures
            serialization_failures = $serialization_failures
            tps                    = $tps
            sum_coins              = $sum_coins
            conserved              = $conserved
            ledger_consistent      = $ledger_consistent
        }
        $results += $rowObj
    }
}
finally {
    # Restore previous PGOPTIONS
    if ($null -eq $origPgOptions) {
        Remove-Item Env:\PGOPTIONS -ErrorAction SilentlyContinue
    } else {
        $env:PGOPTIONS = $origPgOptions
    }
}

Write-Host "`n--- Experiment 2 Results ---"
$results | Format-Table -AutoSize
