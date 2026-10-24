[CmdletBinding()]
param(
    [int]$InflightDays = 3000,
    [switch]$Keep,
    [string]$LabRoot = 'C:\pg_lab'
)

# 1. Dot-source lab_cluster.ps1 and initialize scratch primary cluster
$scriptDir = $PSScriptRoot
if (-not $scriptDir) {
    $scriptDir = "."
}
. (Join-Path $scriptDir "lab_cluster.ps1")

Write-Host "Checking prerequisites..."
Assert-LabPrerequisites -LabRoot $LabRoot -PrimaryPort 5544 -RestoredPort 5545

Write-Host "Ensuring clean lab environment at $LabRoot..."
Remove-LabCluster -LabRoot $LabRoot

Write-Host "Initializing lab primary cluster (checkpoint_timeout = 30min, archive = off)..."
Initialize-LabCluster -LabRoot $LabRoot -CheckpointTimeoutMin 30

$mainId = (Invoke-LabPsql -Port 5544 -Database butterfly -Sql "SELECT branch_id FROM branch WHERE name = 'main' AND parent_id IS NULL;" -Tuples).Trim()
Write-Host "Main branch ID: $mainId"

# 2. Phase 1: Call advance_day(<main>) five times in separate psql calls
Write-Host "Phase 1: advancing 5 days sequentially..."
$acked = @()
for ($i = 1; $i -le 5; $i++) {
    $tickVal = (Invoke-LabPsql -Port 5544 -Database butterfly -Sql "SELECT advance_day($mainId);" -Tuples).Trim()
    $acked += [int]$tickVal
}
Write-Host "Acknowledged ticks: $($acked -join ', ')"

$events_before = [int](Invoke-LabPsql -Port 5544 -Database butterfly -Sql "SELECT count(*) FROM event;" -Tuples).Trim()
$tick_before = [int](Invoke-LabPsql -Port 5544 -Database butterfly -Sql "SELECT max(tick) FROM event WHERE branch_id = $mainId;" -Tuples).Trim()
$digest_before = (Invoke-LabPsql -Port 5544 -Database butterfly -Sql "SELECT branch_projection_digest($mainId);" -Tuples).Trim()

$chainRowsBefore = (Invoke-LabPsql -Port 5544 -Database butterfly -Sql "SELECT * FROM verify_event_chain();" -Tuples).Trim()
$chainProblemsBefore = 0
if (-not [string]::IsNullOrWhiteSpace($chainRowsBefore)) {
    $chainProblemsBefore = ($chainRowsBefore -split "`r?`n").Count
}
if ($chainProblemsBefore -ne 0) {
    throw "Initial event chain verification failed with $chainProblemsBefore problem(s)."
}

# 3. Phase 2: Start long-running synthetic load in background and sleep 4 seconds
Write-Host "Phase 2: launching background load bench_generate($InflightDays)..."
$bgStdout = Join-Path $LabRoot "bench_generate.stdout.log"
$bgStderr = Join-Path $LabRoot "bench_generate.stderr.log"
$benchProc = Start-Process -FilePath "psql" `
    -ArgumentList "-X", "-h", "localhost", "-p", "5544", "-U", "postgres", "-d", "butterfly", "-c", "SELECT bench_generate($InflightDays);" `
    -RedirectStandardOutput $bgStdout `
    -RedirectStandardError $bgStderr `
    -WindowStyle Hidden `
    -PassThru

Start-Sleep -Seconds 4

if ($benchProc.HasExited) {
    throw "The background load finished too quickly ($InflightDays days). Please rerun with a larger -InflightDays."
}
$inflight_at_kill = $true
Write-Host "Background load is actively running in-flight (PID $($benchProc.Id))."

# 4. Crash: Read postmaster PID, kill postmaster process tree, kill background psql
$primaryDir = Join-Path $LabRoot "primary"
$postmasterPid = Get-PostmasterPid -DataDir $primaryDir
if ($postmasterPid -le 0) {
    throw "Could not retrieve postmaster PID from '$primaryDir\postmaster.pid'."
}

Write-Host "Crashing cluster by killing postmaster process tree (PID $postmasterPid)..."
& taskkill /F /T /PID $postmasterPid 2>&1 | Out-Null

if (-not $benchProc.HasExited) {
    & taskkill /F /T /PID $benchProc.Id 2>&1 | Out-Null
    Stop-Process -Id $benchProc.Id -Force -ErrorAction SilentlyContinue
}

# Confirm cluster is no longer accepting connections
$dead = $false
for ($attempt = 0; $attempt -lt 10; $attempt++) {
    $null = & psql -X -h localhost -p 5544 -U postgres -d postgres -c "SELECT 1;" 2>&1
    if ($LASTEXITCODE -ne 0) {
        $dead = $true
        break
    }
    Start-Sleep -Milliseconds 500
}
if (-not $dead) {
    throw "Cluster on port 5544 is still accepting connections after taskkill."
}
Write-Host "Cluster crash confirmed: port 5544 is down."

# 5. Recovery: Restart primary cluster and time recovery until ready
Write-Host "Starting recovery restart..."
$recoverySw = [System.Diagnostics.Stopwatch]::StartNew()
$primary2Log = Join-Path $LabRoot "primary2.log"
& pg_ctl -D $primaryDir -l $primary2Log -w start 2>&1 | Out-Null
$null = Wait-LabReady -Port 5544 -TimeoutSec 120
$recoverySw.Stop()
$recovery_seconds = [Math]::Round($recoverySw.Elapsed.TotalSeconds, 2)
Write-Host "Recovery completed in $recovery_seconds seconds."

# 6. Verify post-recovery database state
$tick_after = [int](Invoke-LabPsql -Port 5544 -Database butterfly -Sql "SELECT max(tick) FROM event WHERE branch_id = $mainId;" -Tuples).Trim()
$events_after = [int](Invoke-LabPsql -Port 5544 -Database butterfly -Sql "SELECT count(*) FROM event;" -Tuples).Trim()
$partial_players_found = [int](Invoke-LabPsql -Port 5544 -Database butterfly -Sql "SELECT count(*) FROM actor WHERE name LIKE 'bench_%';" -Tuples).Trim()

$chainRowsAfter = (Invoke-LabPsql -Port 5544 -Database butterfly -Sql "SELECT * FROM verify_event_chain();" -Tuples).Trim()
$chain_problems = 0
if (-not [string]::IsNullOrWhiteSpace($chainRowsAfter)) {
    $chain_problems = ($chainRowsAfter -split "`r?`n").Count
}

$digest_after = (Invoke-LabPsql -Port 5544 -Database butterfly -Sql "SELECT branch_projection_digest($mainId);" -Tuples).Trim()
$digest_equal = ($digest_after -eq $digest_before)
$lastAcked = $acked[-1]
$tick_ok = ($tick_after -eq $lastAcked)
$events_ok = ($events_after -eq $events_before)

Write-Host "Verification: tick_ok=$tick_ok, events_ok=$events_ok, digest_equal=$digest_equal, chain_problems=$chain_problems, partial_players=$partial_players_found"

# 7. Evidence: Extract crash recovery lines from server logs
$logFiles = Get-ChildItem -Path $LabRoot -Filter "*.log" -File | Select-Object -ExpandProperty FullName
$matchingLines = @()
if ($logFiles) {
    $selMatches = Select-String -Path $logFiles -Pattern 'not properly shut down|automatic recovery|redo starts|redo done|ready to accept connections'
    if ($selMatches) {
        $matchingLines = @($selMatches | ForEach-Object { $_.Line.Trim() })
    }
}

$resultsDir = "experiments/results"
if (-not (Test-Path $resultsDir)) {
    New-Item -ItemType Directory -Path $resultsDir -Force | Out-Null
}
$logDest = Join-Path $resultsDir "exp7b_recovery_log.txt"
Set-Content -Path $logDest -Value $matchingLines -Encoding UTF8

$crash_recovery_logged = $false
foreach ($line in $matchingLines) {
    if ($line -like "*automatic recovery*") {
        $crash_recovery_logged = $true
        break
    }
}

# 8. Write CSV results and print via Format-List
$ackedTicksStr = ($acked -join ';')
$digestEqualStr = $digest_equal.ToString().ToLower()
$crashRecoveryLoggedStr = $crash_recovery_logged.ToString().ToLower()
$inflightAtKillStr = $inflight_at_kill.ToString().ToLower()

$csvPath = Join-Path $resultsDir "exp7b_crash.csv"
$csvHeader = "acked_ticks,tick_after,events_before,events_after,partial_players_found,chain_problems,digest_equal,crash_recovery_logged,inflight_at_kill,recovery_seconds"
$csvRow = "$ackedTicksStr,$tick_after,$events_before,$events_after,$partial_players_found,$chain_problems,$digestEqualStr,$crashRecoveryLoggedStr,$inflightAtKillStr,$recovery_seconds"
Set-Content -Path $csvPath -Value @($csvHeader, $csvRow) -Encoding UTF8

$resultObj = [PSCustomObject]@{
    acked_ticks           = $ackedTicksStr
    tick_after            = $tick_after
    events_before         = $events_before
    events_after          = $events_after
    partial_players_found = $partial_players_found
    chain_problems        = $chain_problems
    digest_equal          = $digestEqualStr
    crash_recovery_logged = $crashRecoveryLoggedStr
    inflight_at_kill      = $inflightAtKillStr
    recovery_seconds      = $recovery_seconds
}

Write-Host "`n--- Experiment 7b Results ---"
$resultObj | Format-List

# Cleanup unless -Keep
if (-not $Keep) {
    Write-Host "Cleaning up lab cluster..."
    Stop-LabCluster -DataDir $primaryDir
    Remove-LabCluster -LabRoot $LabRoot
} else {
    Write-Host "Scratch cluster retained at $LabRoot (-Keep specified)."
}
