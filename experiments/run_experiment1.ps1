[CmdletBinding()]
param(
    [string]$Database = "butterfly",
    [string]$User = "postgres",
    [int]$Loaves = 100,
    [int]$Clients = 20,
    [int]$TxPerClient = 50,
    [int]$MaxTries = 50
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
$csvPath = Join-Path $resultsDir "exp1_last_loaf.csv"

# Overwrite CSV at the start
$csvHeader = "variant,mode,clients,tx_per_client,tps,failed,retried,sales,final_qty,removed,phantom,oversold,correct"
Set-Content -Path $csvPath -Value $csvHeader -Encoding UTF8

$variants = @(
    @{ Name = 'naive'; Script = 'loaf_naive.sql' },
    @{ Name = 'for_update'; Script = 'loaf_for_update.sql' },
    @{ Name = 'atomic_check'; Script = 'loaf_atomic_check.sql' },
    @{ Name = 'optimistic'; Script = 'loaf_optimistic.sql' },
    @{ Name = 'serializable'; Script = 'loaf_serializable.sql' }
)

$results = @()

foreach ($v in $variants) {
    $varName = $v.Name
    $scriptFile = $v.Script

    # Resolve benchmark script path
    $benchFile = "experiments/pgbench/$scriptFile"
    if (-not (Test-Path $benchFile)) {
        $benchFile = Join-Path $ScriptDir "pgbench\$scriptFile"
    }

    $m = 1
    if ($varName -eq 'serializable') {
        $m = $MaxTries
    }

    # Two modes: control and contended
    $modes = @(
        @{ Mode = 'control'; Clients = 1; Tx = ($TxPerClient * $Clients) },
        @{ Mode = 'contended'; Clients = $Clients; Tx = $TxPerClient }
    )

    foreach ($mInfo in $modes) {
        $modeName = $mInfo.Mode
        $c = $mInfo.Clients
        $tx = $mInfo.Tx
        $threads = [Math]::Min($c, 4)

        Write-Host "Running Variant: $varName | Mode: $modeName | Clients: $c | Tx/Client: $tx | MaxTries: $m..."

        # Reset loaves before each run
        & psql -X -v ON_ERROR_STOP=1 -U $User -d $Database -c "SELECT lab.reset_loaves($Loaves);" | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Error "ERROR: Failed to reset loaves."
            exit 1
        }

        # Run pgbench and capture output as flattened string joined with newlines
        $outputLines = & pgbench -n -U $User -d $Database -c $c -j $threads -t $tx -f $benchFile "--max-tries=$m" 2>&1 | ForEach-Object { "$_" }
        $benchText = $outputLines -join "`n"

        # Parse metrics with regexes (default to 0 when absent)
        $tps = 0.0
        if ($benchText -match 'tps\s*=\s*([\d\.]+)\s*\(without initial connection time\)') {
            $tps = [double]$Matches[1]
        } elseif ($benchText -match 'tps\s*=\s*([\d\.]+)') {
            $tps = [double]$Matches[1]
        }

        $failed = 0
        if ($benchText -match 'number of failed transactions:\s*(\d+)') {
            $failed = [int64]$Matches[1]
        }

        $retried = 0
        if ($benchText -match 'number of transactions retried:\s*(\d+)') {
            $retried = [int64]$Matches[1]
        }

        # Query state after run
        $salesRaw = (& psql -X -A -t -U $User -d $Database -c "SELECT count(*) FROM lab.sale;" 2>&1 | ForEach-Object { "$_" }) -join ""
        $salesMatch = [regex]::Match($salesRaw, '(\d+)')
        $sales = 0
        if ($salesMatch.Success) {
            $sales = [int64]$salesMatch.Groups[1].Value
        }

        $finalQtyRaw = (& psql -X -A -t -U $User -d $Database -c "SELECT qty FROM lab.shelf WHERE item = 'bread';" 2>&1 | ForEach-Object { "$_" }) -join ""
        $qtyMatch = [regex]::Match($finalQtyRaw, '(-?\d+)')
        $final_qty = 0
        if ($qtyMatch.Success) {
            $final_qty = [int64]$qtyMatch.Groups[1].Value
        }

        # Compute derived values
        $removed = $Loaves - $final_qty
        $phantom = $sales - $removed
        $oversold = [Math]::Max([int64]0, [int64]($sales - $Loaves))
        $isCorrect = ($phantom -eq 0 -and $final_qty -ge 0)
        $correct = "false"
        if ($isCorrect) {
            $correct = "true"
        }

        # Append row to CSV
        $csvLine = "$varName,$modeName,$c,$tx,$tps,$failed,$retried,$sales,$final_qty,$removed,$phantom,$oversold,$correct"
        Add-Content -Path $csvPath -Value $csvLine -Encoding UTF8

        # Record result object
        $rowObj = [PSCustomObject]@{
            variant       = $varName
            mode          = $modeName
            clients       = $c
            tx_per_client = $tx
            tps           = $tps
            failed        = $failed
            retried       = $retried
            sales         = $sales
            final_qty     = $final_qty
            removed       = $removed
            phantom       = $phantom
            oversold      = $oversold
            correct       = $correct
        }
        $results += $rowObj
    }
}

Write-Host "`n--- Experiment 1 Results ---"
$results | Format-Table -AutoSize
