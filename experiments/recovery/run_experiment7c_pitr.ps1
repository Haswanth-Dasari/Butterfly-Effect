[CmdletBinding()]
param(
    [int]$Days = 100,
    [switch]$Keep,
    [string]$LabRoot = 'C:\pg_lab'
)

$ErrorActionPreference = 'Stop'
$scriptFailed = $false
$primaryDir = Join-Path $LabRoot "primary"
$restoreDir = Join-Path $LabRoot "restore"

try {
    # 1. Dot-source lab_cluster.ps1 and initialize primary cluster with WAL archiving enabled
    $scriptDir = $PSScriptRoot
    if (-not $scriptDir) {
        $scriptDir = "."
    }
    . (Join-Path $scriptDir "lab_cluster.ps1")

    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Checking prerequisites..."
    Assert-LabPrerequisites -LabRoot $LabRoot -PrimaryPort 5544 -RestoredPort 5545

    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Ensuring clean lab environment at ${LabRoot}..."
    Remove-LabCluster -LabRoot $LabRoot

    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Initializing lab primary cluster (archive = on, checkpoint_timeout = 5min)..."
    Initialize-LabCluster -LabRoot $LabRoot -Archive -CheckpointTimeoutMin 5

    $mainId = (Invoke-LabPsql -Port 5544 -Database butterfly -Sql "SELECT branch_id FROM branch WHERE name = 'main' AND parent_id IS NULL;" -Tuples).Trim()
    Write-Host "Main branch ID: ${mainId}"

    # 2. Base backup of primary cluster
    $baseDir = Join-Path $LabRoot "base"
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Taking physical base backup to ${baseDir}..."
    $bbSw = [System.Diagnostics.Stopwatch]::StartNew()
    Invoke-Native -FilePath "pg_basebackup" -Arguments @("-h", "localhost", "-p", "5544", "-U", "postgres", "-D", $baseDir, "-Fp", "-X", "stream", "-c", "fast") | Out-Null
    $bbSw.Stop()
    $base_backup_seconds = [Math]::Round($bbSw.Elapsed.TotalSeconds, 2)
    Write-Host "Base backup completed in ${base_backup_seconds} seconds."

    # 3. Generate history and record baseline state at restore point
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Generating ${Days} days of history on primary..."
    $genOut = Invoke-LabPsql -Port 5544 -Database butterfly -Sql "SELECT bench_generate(${Days});"
    $events_at_restore_point = [int](Invoke-LabPsql -Port 5544 -Database butterfly -Sql "SELECT count(*) FROM event;" -Tuples).Trim()
    $digest_at_restore_point = (Invoke-LabPsql -Port 5544 -Database butterfly -Sql "SELECT branch_projection_digest(${mainId});" -Tuples).Trim()
    $entity_rows_at_restore_point = [int](Invoke-LabPsql -Port 5544 -Database butterfly -Sql "SELECT count(*) FROM entity_state;" -Tuples).Trim()
    Write-Host "State at restore point: events=${events_at_restore_point}, entity_rows=${entity_rows_at_restore_point}, digest=${digest_at_restore_point}"

    # 4. Create named restore point 'before_oops'
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Creating named restore point 'before_oops'..."
    $null = Invoke-LabPsql -Port 5544 -Database butterfly -Sql "SELECT pg_create_restore_point('before_oops');"

    # 5. Simulate human disaster: DROP TABLE stock; and TRUNCATE entity_state;
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Simulating disaster: dropping table stock and truncating entity_state..."
    $null = Invoke-LabPsql -Port 5544 -Database butterfly -Sql "DROP TABLE stock;"
    $null = Invoke-LabPsql -Port 5544 -Database butterfly -Sql "TRUNCATE entity_state;"

    # Confirm disaster on primary (intentionally allowed to fail with relation does not exist)
    $stockCheck = Invoke-LabPsql -Port 5544 -Database butterfly -Sql "SELECT count(*) FROM stock;" -AllowFailure
    $disaster_confirmed = ($stockCheck -like "*does not exist*")
    if (-not $disaster_confirmed) {
        Write-Warning "Disaster check warning: table stock query did not report missing relation: ${stockCheck}"
    } else {
        Write-Host "Disaster confirmed: SELECT count(*) FROM stock failed with 'does not exist'."
    }

    # 6. Archive everything: switch WAL and verify WAL segment is archived
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Switching WAL and waiting for archive..."
    $last = (Invoke-LabPsql -Port 5544 -Database butterfly -Sql "SELECT pg_walfile_name(pg_current_wal_lsn());" -Tuples).Trim()
    Write-Host "Current WAL segment at disaster: ${last}"
    $null = Invoke-LabPsql -Port 5544 -Database butterfly -Sql "SELECT pg_switch_wal();"

    $walArchiveDir = Join-Path $LabRoot "wal_archive"
    $lastWalTarget = Join-Path $walArchiveDir $last
    $walArchived = $false
    $archiveSw = [System.Diagnostics.Stopwatch]::StartNew()
    while ($archiveSw.Elapsed.TotalSeconds -lt 60) {
        if (Test-Path $lastWalTarget) {
            $walArchived = $true
            break
        }
        Start-Sleep -Milliseconds 500
    }
    $archiveSw.Stop()

    if (-not $walArchived) {
        throw "WAL segment '${last}' was not copied to '${walArchiveDir}' within 60 seconds."
    }
    $archived_wal_files = (Get-ChildItem -Path $walArchiveDir -File).Count
    Write-Host "WAL archive contains ${archived_wal_files} files."

    # 7. Restore: Copy base backup, configure PITR, start recovered cluster on port 5545
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Copying base backup to ${restoreDir}..."
    Copy-Item -Path $baseDir -Destination $restoreDir -Recurse -Force

    $postmasterPidRestore = Join-Path $restoreDir "postmaster.pid"
    if (Test-Path $postmasterPidRestore) {
        Remove-Item -Path $postmasterPidRestore -Force
    }

    $doubledLabRoot = $LabRoot.Replace('\', '\\')
    $restoreAutoConf = Join-Path $restoreDir "postgresql.auto.conf"
    $autoConfLines = @(
        "port = 5545",
        "archive_mode = off",
        "restore_command = 'copy `"${doubledLabRoot}\\wal_archive\\%f`" `"%p`"'",
        "recovery_target_name = 'before_oops'",
        "recovery_target_action = 'promote'"
    )
    Add-Content -Path $restoreAutoConf -Value $autoConfLines -Encoding UTF8

    Write-Host "Appended to ${restoreAutoConf}:"
    Write-Host "  port = 5545"
    Write-Host "  archive_mode = off"
    Write-Host "  restore_command = 'copy `"${doubledLabRoot}\\wal_archive\\%f`" `"%p`"'"
    Write-Host "  recovery_target_name = 'before_oops'"
    Write-Host "  recovery_target_action = 'promote'"

    $recoverySignal = Join-Path $restoreDir "recovery.signal"
    Set-Content -Path $recoverySignal -Value $null -Encoding UTF8

    $restoreLog = Join-Path $LabRoot "restore.log"
    $restoreSw = [System.Diagnostics.Stopwatch]::StartNew()
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Starting the restored cluster on port 5545..."

    $null = Start-LabServer -DataDir $restoreDir -LogFile $restoreLog -Port 5545 -TimeoutSec 120

    # Wait-for-promotion loop: poll every second, up to 120s
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Waiting for recovery promotion on port 5545..."
    $promoted = $false
    while ($restoreSw.Elapsed.TotalSeconds -lt 120) {
        # Check that restored cluster's postmaster is still alive
        $pidVal = Get-PostmasterPid -DataDir $restoreDir
        $procAlive = $false
        if ($pidVal -gt 0) {
            $p = Get-Process -Id $pidVal -ErrorAction SilentlyContinue
            if ($p -and -not $p.HasExited) {
                $procAlive = $true
            }
        }
        if (-not $procAlive) {
            Write-Host "[ERROR] Restored cluster postmaster (PID ${pidVal}) is not running!" -ForegroundColor Red
            if (Test-Path $restoreLog) {
                Write-Host "=== Last 40 lines of ${restoreLog} ===" -ForegroundColor Cyan
                Get-Content -Path $restoreLog -Tail 40 -ErrorAction SilentlyContinue | ForEach-Object { Write-Host $_ }
            }
            throw "Restored cluster postmaster process is not running. See restore.log output above."
        }

        $recStatus = Invoke-LabPsql -Port 5545 -Database butterfly -Sql "SELECT pg_is_in_recovery();" -Tuples -AllowFailure
        if ($recStatus.Trim() -eq 'f') {
            $promoted = $true
            break
        }
        Start-Sleep -Seconds 1
    }
    $restoreSw.Stop()

    if (-not $promoted) {
        if (Test-Path $restoreLog) {
            Write-Host "=== Last 40 lines of ${restoreLog} ===" -ForegroundColor Cyan
            Get-Content -Path $restoreLog -Tail 40 -ErrorAction SilentlyContinue | ForEach-Object { Write-Host $_ }
        }
        throw "Restored cluster on port 5545 did not finish recovery within 120 seconds."
    }
    $restore_seconds = [Math]::Round($restoreSw.Elapsed.TotalSeconds, 2)
    Write-Host "PITR recovery and promotion completed in ${restore_seconds} seconds."

    # 8. Verify restored state on port 5545 and damaged state on port 5544
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Verifying restored state on port 5545 and damaged state on port 5544..."
    $stockCountRestored = [int](Invoke-LabPsql -Port 5545 -Database butterfly -Sql "SELECT count(*) FROM stock;" -Tuples).Trim()
    $stock_present = ($stockCountRestored -gt 0)

    $events_restored = [int](Invoke-LabPsql -Port 5545 -Database butterfly -Sql "SELECT count(*) FROM event;" -Tuples).Trim()
    $entity_rows_restored = [int](Invoke-LabPsql -Port 5545 -Database butterfly -Sql "SELECT count(*) FROM entity_state;" -Tuples).Trim()
    $digest_restored = (Invoke-LabPsql -Port 5545 -Database butterfly -Sql "SELECT branch_projection_digest(${mainId});" -Tuples).Trim()

    $chainRowsRestored = (Invoke-LabPsql -Port 5545 -Database butterfly -Sql "SELECT * FROM verify_event_chain();" -Tuples).Trim()
    $chain_problems = 0
    if (-not [string]::IsNullOrWhiteSpace($chainRowsRestored)) {
        $chain_problems = ($chainRowsRestored -split "`r?`n").Count
    }

    $digest_equal = ($digest_restored -eq $digest_at_restore_point)
    $events_equal = ($events_restored -eq $events_at_restore_point)
    $entity_equal = ($entity_rows_restored -eq $entity_rows_at_restore_point)

    # Verify damaged primary on port 5544 still has missing stock
    $primaryStockCheck = Invoke-LabPsql -Port 5544 -Database butterfly -Sql "SELECT count(*) FROM stock;" -AllowFailure
    $primary_still_damaged = ($primaryStockCheck -like "*does not exist*")

    Write-Host "Verification: stock_present=${stock_present}, digest_equal=${digest_equal}, events_equal=${events_equal}, entity_equal=${entity_equal}, primary_still_damaged=${primary_still_damaged}"

    # 9. Evidence: Select-String restore.log for key PITR events
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Extracting PITR events from restore log..."
    $matchingLines = @()
    if (Test-Path $restoreLog) {
        $matchesPitr = Select-String -Path $restoreLog -Pattern 'point-in-time recovery|restore point|recovery stopping|redo done|promoted'
        if ($matchesPitr) {
            $matchingLines = @($matchesPitr | ForEach-Object { $_.Line.Trim() })
        }
    }

    $resultsDir = "experiments/results"
    if (-not (Test-Path $resultsDir)) {
        New-Item -ItemType Directory -Path $resultsDir -Force | Out-Null
    }
    $restoreLogDest = Join-Path $resultsDir "exp7c_restore_log.txt"
    Set-Content -Path $restoreLogDest -Value $matchingLines -Encoding UTF8

    $restore_point_reached = $false
    foreach ($line in $matchingLines) {
        if ($line -like "*recovery stopping*" -and $line -like "*before_oops*") {
            $restore_point_reached = $true
            break
        }
    }

    # 10. Write experiments/results/exp7c_pitr.csv and print via Format-List
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Writing CSV results..."
    $stockPresentStr = $stock_present.ToString().ToLower()
    $digestEqualStr = $digest_equal.ToString().ToLower()
    $disasterConfirmedStr = $disaster_confirmed.ToString().ToLower()
    $primaryDamagedStr = $primary_still_damaged.ToString().ToLower()
    $restorePointReachedStr = $restore_point_reached.ToString().ToLower()

    $csvPath = Join-Path $resultsDir "exp7c_pitr.csv"
    $csvHeader = "base_backup_seconds,events_at_restore_point,events_restored,entity_rows_at_restore_point,entity_rows_restored,stock_present,digest_equal,chain_problems,disaster_confirmed,primary_still_damaged,restore_point_reached,archived_wal_files,restore_seconds"
    $csvRow = "${base_backup_seconds},${events_at_restore_point},${events_restored},${entity_rows_at_restore_point},${entity_rows_restored},${stockPresentStr},${digestEqualStr},${chain_problems},${disasterConfirmedStr},${primaryDamagedStr},${restorePointReachedStr},${archived_wal_files},${restore_seconds}"
    Set-Content -Path $csvPath -Value @($csvHeader, $csvRow) -Encoding UTF8

    $resultObj = [PSCustomObject]@{
        base_backup_seconds          = $base_backup_seconds
        events_at_restore_point      = $events_at_restore_point
        events_restored              = $events_restored
        entity_rows_at_restore_point = $entity_rows_at_restore_point
        entity_rows_restored         = $entity_rows_restored
        stock_present                = $stockPresentStr
        digest_equal                 = $digestEqualStr
        chain_problems               = $chain_problems
        disaster_confirmed           = $disasterConfirmedStr
        primary_still_damaged        = $primaryDamagedStr
        restore_point_reached        = $restorePointReachedStr
        archived_wal_files           = $archived_wal_files
        restore_seconds              = $restore_seconds
    }

    Write-Host "`n--- Experiment 7c Results ---"
    $resultObj | Format-List
    Write-Host "Results written to CSV: ${csvPath}"
}
catch {
    $scriptFailed = $true
    Write-Host "`n[ERROR] An error occurred during experiment execution:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    if ($_.ScriptStackTrace) {
        Write-Host "`nStack trace:" -ForegroundColor Yellow
        Write-Host $_.ScriptStackTrace
    }

    if (Test-Path $LabRoot) {
        $logFiles = Get-ChildItem -Path $LabRoot -Filter "*.log" -File -Recurse -ErrorAction SilentlyContinue
        foreach ($lf in $logFiles) {
            Write-Host "`n=== Last 40 lines of $($lf.FullName) ===" -ForegroundColor Cyan
            $lines = Get-Content -Path $lf.FullName -Tail 40 -ErrorAction SilentlyContinue
            if ($lines) {
                $lines | ForEach-Object { Write-Host $_ }
            } else {
                Write-Host "(log file is empty)"
            }
        }
    }

    Write-Host "`nLab left in place for inspection; run experiments/recovery/cleanup_lab.ps1 to remove it" -ForegroundColor Yellow
    exit 1
}
finally {
    if (-not $scriptFailed) {
        if (-not $Keep) {
            Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Stopping restored and primary clusters, and cleaning up..."
            Stop-LabCluster -DataDir $restoreDir
            Stop-LabCluster -DataDir $primaryDir
            Remove-LabCluster -LabRoot $LabRoot
        } else {
            Write-Host "Lab clusters retained at ${LabRoot} (-Keep specified)."
        }
    }
}
