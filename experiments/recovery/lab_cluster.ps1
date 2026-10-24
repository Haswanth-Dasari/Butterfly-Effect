# lab_cluster.ps1 - Database-level recovery experiment helper functions
# Meant to be dot-sourced into recovery experiment scripts; no code runs on load.

function Assert-LabPrerequisites {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)][string]$LabRoot = 'C:\pg_lab',
        [Parameter(Mandatory = $false)][int]$PrimaryPort = 5544,
        [Parameter(Mandatory = $false)][int]$RestoredPort = 5545
    )

    # 1. Verify required PostgreSQL binaries exist in PATH
    $requiredTools = @('initdb', 'pg_ctl', 'pg_basebackup', 'psql')
    foreach ($tool in $requiredTools) {
        if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
            throw "Prerequisite check failed: PostgreSQL binary '$tool' was not found in PATH. Please ensure PostgreSQL bin directory is added to PATH."
        }
    }

    # 2. Verify PowerShell session is NOT elevated (Administrator)
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if ($isAdmin) {
        throw "Prerequisite check failed: Current PowerShell session is elevated (Administrator). PostgreSQL refuse to run with elevated privileges. Please run from a standard user PowerShell session."
    }

    # 3. Verify ports 5544 and 5545 are not in use by external processes
    $conns = Get-NetTCPConnection -LocalPort $PrimaryPort, $RestoredPort -State Listen -ErrorAction SilentlyContinue
    if ($conns) {
        $labPids = @()
        if (Test-Path $LabRoot) {
            $pidFiles = Get-ChildItem -Path $LabRoot -Filter "postmaster.pid" -Recurse -File -ErrorAction SilentlyContinue
            foreach ($pf in $pidFiles) {
                $firstLine = Get-Content -Path $pf.FullName -TotalCount 1 -ErrorAction SilentlyContinue
                if ($firstLine) {
                    $pidVal = 0
                    if ([int]::TryParse($firstLine.Trim(), [ref]$pidVal)) {
                        $labPids += $pidVal
                    }
                }
            }
        }

        foreach ($conn in $conns) {
            if ($labPids -notcontains $conn.OwningProcess) {
                $proc = Get-Process -Id $conn.OwningProcess -ErrorAction SilentlyContinue
                $procName = "PID $($conn.OwningProcess)"
                if ($proc) {
                    $procName = $proc.ProcessName
                }
                throw "Prerequisite check failed: Port $($conn.LocalPort) is currently in use by process '$procName' (PID $($conn.OwningProcess)), which is not an existing lab cluster under '$LabRoot'."
            }
        }
    }
}

function Get-PostmasterPid {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$DataDir
    )

    $pidFile = Join-Path $DataDir "postmaster.pid"
    if (Test-Path $pidFile) {
        $firstLine = Get-Content -Path $pidFile -TotalCount 1 -ErrorAction SilentlyContinue
        if ($firstLine) {
            $pidVal = 0
            if ([int]::TryParse($firstLine.Trim(), [ref]$pidVal)) {
                return $pidVal
            }
        }
    }
    return 0
}

function Stop-LabCluster {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$DataDir
    )

    if (Test-Path $DataDir) {
        & pg_ctl -D $DataDir stop -m fast 2>&1 | Out-Null
    }
}

function Remove-LabCluster {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)][string]$LabRoot = 'C:\pg_lab'
    )

    if (Test-Path $LabRoot) {
        # Find any clusters under $LabRoot and stop immediately
        $pidFiles = Get-ChildItem -Path $LabRoot -Filter "postmaster.pid" -Recurse -File -ErrorAction SilentlyContinue
        foreach ($pf in $pidFiles) {
            $dataDir = $pf.DirectoryName
            $firstLine = Get-Content -Path $pf.FullName -TotalCount 1 -ErrorAction SilentlyContinue
            $pidVal = 0
            if ($firstLine) {
                [int]::TryParse($firstLine.Trim(), [ref]$pidVal) | Out-Null
            }

            & pg_ctl -D $dataDir stop -m immediate 2>&1 | Out-Null
            if ($pidVal -gt 0) {
                & taskkill /F /T /PID $pidVal 2>&1 | Out-Null
                $p = Get-Process -Id $pidVal -ErrorAction SilentlyContinue
                if ($p) {
                    Stop-Process -Id $pidVal -Force -ErrorAction SilentlyContinue
                }
            }
        }

        # Attempt immediate stop on known standard cluster subdirectories as well
        foreach ($sub in @('primary', 'restore')) {
            $clusterDir = Join-Path $LabRoot $sub
            if (Test-Path $clusterDir) {
                & pg_ctl -D $clusterDir stop -m immediate 2>&1 | Out-Null
            }
        }

        # Wait 2 seconds before deletion
        Start-Sleep -Seconds 2

        # Delete $LabRoot recursively (retry up to 5 times)
        for ($attempt = 1; $attempt -le 5; $attempt++) {
            if (-not (Test-Path $LabRoot)) {
                break
            }
            try {
                Remove-Item -Path $LabRoot -Recurse -Force -ErrorAction Stop
                break
            } catch {
                if ($attempt -lt 5) {
                    Start-Sleep -Seconds 1
                }
            }
        }

        if (Test-Path $LabRoot) {
            Write-Warning "Failed to completely delete '$LabRoot' after 5 attempts."
        }
    }
}

function Initialize-LabCluster {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)][string]$LabRoot = 'C:\pg_lab',
        [switch]$Archive,
        [int]$CheckpointTimeoutMin = 30
    )

    # 1. Create $LabRoot and $LabRoot\wal_archive
    if (-not (Test-Path $LabRoot)) {
        New-Item -ItemType Directory -Path $LabRoot -Force | Out-Null
    }
    $walArchive = Join-Path $LabRoot "wal_archive"
    if (-not (Test-Path $walArchive)) {
        New-Item -ItemType Directory -Path $walArchive -Force | Out-Null
    }

    # 2. Run initdb -D $LabRoot\primary -U postgres -A trust -E UTF8
    $primaryDir = Join-Path $LabRoot "primary"
    & initdb -D $primaryDir -U postgres -A trust -E UTF8
    if ($LASTEXITCODE -ne 0) {
        throw "initdb failed for primary cluster at '$primaryDir'."
    }

    # 3. Append configuration lines to postgresql.conf
    $confFile = Join-Path $primaryDir "postgresql.conf"
    $confLines = @(
        "port = 5544",
        "listen_addresses = 'localhost'",
        "wal_level = replica",
        "max_wal_senders = 5",
        "fsync = on",
        "synchronous_commit = on",
        "checkpoint_timeout = '${CheckpointTimeoutMin}min'",
        "max_wal_size = '4GB'"
    )
    if ($Archive) {
        $doubledLabRoot = $LabRoot.Replace('\', '\\')
        $confLines += "archive_mode = on"
        $confLines += "archive_command = 'copy `"%p`" `"$doubledLabRoot\\wal_archive\\%f`"'"
    }
    Add-Content -Path $confFile -Value $confLines -Encoding UTF8

    # 4. Start primary cluster with pg_ctl
    $primaryLog = Join-Path $LabRoot "primary.log"
    & pg_ctl -D $primaryDir -l $primaryLog -w start
    if ($LASTEXITCODE -ne 0) {
        throw "pg_ctl failed to start primary cluster at '$primaryDir'."
    }

    # 5. Create database butterfly on primary
    & psql -X -h localhost -p 5544 -U postgres -d postgres -c "CREATE DATABASE butterfly;"
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to create database 'butterfly' on localhost:5544."
    }

    # 6. Locate repository root
    $repoRoot = $null
    if (Test-Path "db/schema/_all.sql") {
        $repoRoot = (Get-Location).Path
    } elseif ($PSScriptRoot -and (Test-Path (Join-Path $PSScriptRoot "..\..\db\schema\_all.sql"))) {
        $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
    } else {
        throw "Cannot locate repository root containing db/schema/_all.sql."
    }

    # 7. Apply schema, seed, and benchmark generator scripts in order
    $schemaFile = Join-Path $repoRoot "db\schema\_all.sql"
    & psql -X -v ON_ERROR_STOP=1 -h localhost -p 5544 -U postgres -d butterfly -f $schemaFile
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to apply db/schema/_all.sql on localhost:5544."
    }

    $seedFile = Join-Path $repoRoot "db\seed\_seed_all.sql"
    & psql -X -v ON_ERROR_STOP=1 -h localhost -p 5544 -U postgres -d butterfly -f $seedFile
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to apply db/seed/_seed_all.sql on localhost:5544."
    }

    $benchFile = Join-Path $repoRoot "experiments\recovery\bench_generate.sql"
    & psql -X -v ON_ERROR_STOP=1 -h localhost -p 5544 -U postgres -d butterfly -f $benchFile
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to apply experiments/recovery/bench_generate.sql on localhost:5544."
    }
}

function Invoke-LabPsql {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)][int]$Port = 5544,
        [Parameter(Mandatory = $false)][string]$Database = 'butterfly',
        [Parameter(Mandatory = $false)][string]$Sql,
        [Parameter(Mandatory = $false)][string]$File,
        [switch]$Tuples
    )

    $cmdArgs = @('-X', '-h', 'localhost', '-p', $Port.ToString(), '-U', 'postgres', '-d', $Database)
    if ($Tuples) {
        $cmdArgs += @('-A', '-t')
    }
    if ($Sql) {
        $cmdArgs += @('-c', $Sql)
    }
    if ($File) {
        $cmdArgs += @('-f', $File)
    }

    $output = (& psql @cmdArgs 2>&1 | ForEach-Object { "$_" }) -join "`n"
    return $output
}

function Wait-LabReady {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)][int]$Port = 5544,
        [Parameter(Mandatory = $false)][int]$TimeoutSec = 120
    )

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $ready = $false
    while ($sw.Elapsed.TotalSeconds -lt $TimeoutSec) {
        $null = & psql -X -h localhost -p $Port -U postgres -d postgres -c "SELECT 1;" 2>&1
        if ($LASTEXITCODE -eq 0) {
            $ready = $true
            break
        }
        Start-Sleep -Milliseconds 250
    }
    $sw.Stop()

    if (-not $ready) {
        throw "PostgreSQL on port $Port did not become ready within $TimeoutSec seconds."
    }
    return [Math]::Round($sw.Elapsed.TotalSeconds, 2)
}
