# lab_cluster.ps1 - Database-level recovery experiment helper functions
# Meant to be dot-sourced into recovery experiment scripts; no code runs on load.

function Invoke-Native {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $false)][string[]]$Arguments = @(),
        [Parameter(Mandatory = $false)][int[]]$AllowedExitCodes = @(0),
        [Parameter(Mandatory = $false)][int]$TimeoutSec = 300
    )

    # -TimeoutSec parameter is kept for compatibility, but ignored because the call operator (&)
    # runs finite commands synchronously without Start-Process pipe inheritance or null-ExitCode issues.
    $oldEap = $ErrorActionPreference
    $outLines = $null
    $code = 0
    try {
        $ErrorActionPreference = 'Continue'
        $outLines = & $FilePath @Arguments 2>&1 | ForEach-Object { "$_" }
        $code = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $oldEap
    }

    $output = ($outLines -join "`n").TrimEnd("`r", "`n")

    if ($AllowedExitCodes -ne $null -and ($AllowedExitCodes -notcontains $code)) {
        $cmdLine = "$FilePath $($Arguments -join ' ')"
        throw "Native command failed with exit code ${code}.`nCommand: ${cmdLine}`nOutput:`n${output}"
    }

    return $output
}

function Start-BackgroundPsql {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)][int]$Port = 5544,
        [Parameter(Mandatory = $false)][string]$Database = 'butterfly',
        [Parameter(Mandatory = $true)][string]$Sql,
        [Parameter(Mandatory = $true)][string]$OutFile,
        [Parameter(Mandatory = $true)][string]$ErrFile
    )

    $psqlCmd = Get-Command psql -ErrorAction Stop
    $psqlPath = $psqlCmd.Path
    if (-not $psqlPath) {
        $psqlPath = $psqlCmd.Source
    }

    $argString = "-X -v ON_ERROR_STOP=1 -h localhost -p ${Port} -U postgres -d ${Database} -c `"${Sql}`""

    $proc = Start-Process -FilePath $psqlPath `
        -ArgumentList $argString `
        -PassThru `
        -WindowStyle Hidden `
        -RedirectStandardOutput $OutFile `
        -RedirectStandardError $ErrFile

    $null = $proc.Handle

    return $proc
}

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
            throw "Prerequisite check failed: PostgreSQL binary '${tool}' was not found in PATH. Please ensure PostgreSQL bin directory is added to PATH."
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
                throw "Prerequisite check failed: Port $($conn.LocalPort) is currently in use by process '${procName}' (PID $($conn.OwningProcess)), which is not an existing lab cluster under '${LabRoot}'."
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
        $oldEap = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            & pg_ctl -D $DataDir stop -m fast 2>&1 | Out-Null
        } catch {
        } finally {
            $ErrorActionPreference = $oldEap
        }
    }
}

function Remove-LabCluster {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)][string]$LabRoot = 'C:\pg_lab'
    )

    if (Test-Path $LabRoot) {
        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Removing lab cluster at '${LabRoot}'..."

        # Find any clusters under $LabRoot and stop immediately
        $pidFiles = Get-ChildItem -Path $LabRoot -Filter "postmaster.pid" -Recurse -File -ErrorAction SilentlyContinue
        foreach ($pf in $pidFiles) {
            $dataDir = $pf.DirectoryName
            $firstLine = Get-Content -Path $pf.FullName -TotalCount 1 -ErrorAction SilentlyContinue
            $pidVal = 0
            if ($firstLine) {
                [int]::TryParse($firstLine.Trim(), [ref]$pidVal) | Out-Null
            }

            $oldEap = $ErrorActionPreference
            try {
                $ErrorActionPreference = 'Continue'
                & pg_ctl -D $dataDir stop -m immediate 2>&1 | Out-Null
            } catch {
            } finally {
                $ErrorActionPreference = $oldEap
            }

            if ($pidVal -gt 0) {
                $oldEap = $ErrorActionPreference
                try {
                    $ErrorActionPreference = 'Continue'
                    & taskkill /F /T /PID $pidVal 2>&1 | Out-Null
                } catch {
                } finally {
                    $ErrorActionPreference = $oldEap
                }

                try {
                    $p = Get-Process -Id $pidVal -ErrorAction SilentlyContinue
                    if ($p) {
                        Stop-Process -Id $pidVal -Force -ErrorAction SilentlyContinue
                    }
                } catch {
                }
            }
        }

        # Attempt immediate stop on known standard cluster subdirectories as well
        foreach ($sub in @('primary', 'restore')) {
            $clusterDir = Join-Path $LabRoot $sub
            if (Test-Path $clusterDir) {
                $oldEap = $ErrorActionPreference
                try {
                    $ErrorActionPreference = 'Continue'
                    & pg_ctl -D $clusterDir stop -m immediate 2>&1 | Out-Null
                } catch {
                } finally {
                    $ErrorActionPreference = $oldEap
                }
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
            Write-Warning "Failed to completely delete '${LabRoot}' after 5 attempts."
        }
    }
}

function Invoke-LabPsql {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)][int]$Port = 5544,
        [Parameter(Mandatory = $false)][string]$Database = 'butterfly',
        [Parameter(Mandatory = $false)][string]$Sql,
        [Parameter(Mandatory = $false)][string]$File,
        [switch]$Tuples,
        [switch]$AllowFailure,
        [Parameter(Mandatory = $false)][int]$TimeoutSec = 300
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

    $allowed = @(0)
    if ($AllowFailure) {
        $allowed = $null
    }

    return (Invoke-Native -FilePath "psql" -Arguments $cmdArgs -AllowedExitCodes $allowed -TimeoutSec $TimeoutSec)
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
        $oldEap = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            $null = & psql -X -h localhost -p $Port -U postgres -d postgres -c "SELECT 1;" 2>&1
            if ($LASTEXITCODE -eq 0) {
                $ready = $true
                break
            }
        } catch {
        } finally {
            $ErrorActionPreference = $oldEap
        }
        Start-Sleep -Milliseconds 250
    }
    $sw.Stop()

    if (-not $ready) {
        throw "PostgreSQL on port ${Port} did not become ready within ${TimeoutSec} seconds."
    }
    return [Math]::Round($sw.Elapsed.TotalSeconds, 2)
}

function Start-LabServer {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$DataDir,
        [Parameter(Mandatory = $true)][string]$LogFile,
        [Parameter(Mandatory = $false)][int]$Port = 0,
        [Parameter(Mandatory = $false)][int]$TimeoutSec = 120
    )

    if ($Port -le 0) {
        $autoConf = Join-Path $DataDir "postgresql.auto.conf"
        $mainConf = Join-Path $DataDir "postgresql.conf"
        if (Test-Path $autoConf) {
            $m = Select-String -Path $autoConf -Pattern '^\s*port\s*=\s*[''"]?(\d+)' | Select-Object -First 1
            if ($m -and $m.Matches[0].Groups[1].Value) {
                $Port = [int]$m.Matches[0].Groups[1].Value
            }
        }
        if ($Port -le 0 -and (Test-Path $mainConf)) {
            $m = Select-String -Path $mainConf -Pattern '^\s*port\s*=\s*[''"]?(\d+)' | Select-Object -First 1
            if ($m -and $m.Matches[0].Groups[1].Value) {
                $Port = [int]$m.Matches[0].Groups[1].Value
            }
        }
        if ($Port -le 0) {
            $Port = 5544
        }
    }

    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Starting cluster in '${DataDir}' on port ${Port}..."

    $pgCtlCmd = Get-Command pg_ctl -ErrorAction Stop
    $pgCtlPath = $pgCtlCmd.Source
    if (-not $pgCtlPath) {
        $pgCtlPath = $pgCtlCmd.Path
    }

    $argString = "-D `"${DataDir}`" -l `"${LogFile}`" -w start"
    $p = Start-Process -FilePath $pgCtlPath `
        -ArgumentList $argString `
        -NoNewWindow `
        -PassThru

    $null = $p.Handle

    $timeoutMs = $TimeoutSec * 1000
    $exited = $p.WaitForExit($timeoutMs)

    if (-not $exited) {
        try {
            $p.Kill()
        } catch {
        }
        throw "pg_ctl start timed out after ${TimeoutSec}s for data directory '${DataDir}'."
    }

    $code = $null
    try {
        $code = $p.ExitCode
    } catch {
    }

    if ($code -ne $null -and $code -ne 0) {
        $logExcerpt = ""
        if (Test-Path $LogFile) {
            $tailLines = Get-Content -Path $LogFile -Tail 40 -ErrorAction SilentlyContinue
            if ($tailLines) {
                $logExcerpt = ($tailLines -join "`n")
            }
        }
        throw "pg_ctl start failed with exit code ${code} for data directory '${DataDir}'.`nLast 40 lines of ${LogFile}:`n${logExcerpt}"
    }

    try {
        $readyTime = Wait-LabReady -Port $Port -TimeoutSec $TimeoutSec
        return $readyTime
    } catch {
        $logExcerpt = ""
        if (Test-Path $LogFile) {
            $tailLines = Get-Content -Path $LogFile -Tail 40 -ErrorAction SilentlyContinue
            if ($tailLines) {
                $logExcerpt = ($tailLines -join "`n")
            }
        }
        throw "PostgreSQL on port ${Port} did not become ready within ${TimeoutSec} seconds for data directory '${DataDir}'.`nLast 40 lines of ${LogFile}:`n${logExcerpt}"
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
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Creating lab directories at '${LabRoot}'..."
    if (-not (Test-Path $LabRoot)) {
        New-Item -ItemType Directory -Path $LabRoot -Force | Out-Null
    }
    $walArchive = Join-Path $LabRoot "wal_archive"
    if (-not (Test-Path $walArchive)) {
        New-Item -ItemType Directory -Path $walArchive -Force | Out-Null
    }

    # 2. Run initdb -D $LabRoot\primary -U postgres -A trust -E UTF8
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Initializing primary cluster with initdb..."
    $primaryDir = Join-Path $LabRoot "primary"
    Invoke-Native -FilePath "initdb" -Arguments @("-D", $primaryDir, "-U", "postgres", "-A", "trust", "-E", "UTF8") | Out-Null

    # 3. Append configuration lines to postgresql.conf
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Configuring primary cluster postgresql.conf..."
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
        $confLines += "archive_command = 'copy `"%p`" `"${doubledLabRoot}\\wal_archive\\%f`"'"
    }
    Add-Content -Path $confFile -Value $confLines -Encoding UTF8

    # 4. Start primary cluster with pg_ctl
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Starting primary cluster on port 5544..."
    $primaryLog = Join-Path $LabRoot "primary.log"
    $null = Start-LabServer -DataDir $primaryDir -LogFile $primaryLog -Port 5544

    # 5. Create database butterfly on primary
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Creating database butterfly on port 5544..."
    Invoke-Native -FilePath "psql" -Arguments @("-X", "-h", "localhost", "-p", "5544", "-U", "postgres", "-d", "postgres", "-c", "CREATE DATABASE butterfly;") | Out-Null

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
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Applying schema, seed, and benchmark generator scripts..."
    $schemaFile = Join-Path $repoRoot "db\schema\_all.sql"
    Invoke-Native -FilePath "psql" -Arguments @("-X", "-v", "ON_ERROR_STOP=1", "-h", "localhost", "-p", "5544", "-U", "postgres", "-d", "butterfly", "-f", $schemaFile) | Out-Null

    $seedFile = Join-Path $repoRoot "db\seed\_seed_all.sql"
    Invoke-Native -FilePath "psql" -Arguments @("-X", "-v", "ON_ERROR_STOP=1", "-h", "localhost", "-p", "5544", "-U", "postgres", "-d", "butterfly", "-f", $seedFile) | Out-Null

    $benchFile = Join-Path $repoRoot "experiments\recovery\bench_generate.sql"
    Invoke-Native -FilePath "psql" -Arguments @("-X", "-v", "ON_ERROR_STOP=1", "-h", "localhost", "-p", "5544", "-U", "postgres", "-d", "butterfly", "-f", $benchFile) | Out-Null
}

# powershell -ExecutionPolicy Bypass -Command ". experiments/recovery/lab_cluster.ps1; Test-LabHelpers"
function Test-LabHelpers {
    [CmdletBinding()]
    param()

    # Test 1: psql --version (must succeed with exit code 0 and return output)
    $test1Pass = $false
    try {
        $vOut = Invoke-Native -FilePath "psql" -Arguments @("--version") -AllowedExitCodes @(0)
        if ($vOut -and $vOut.Length -gt 0) {
            $test1Pass = $true
        }
    } catch {
        $test1Pass = $false
    }

    if ($test1Pass) {
        Write-Host "PASS: psql --version returned exit code 0 with output." -ForegroundColor Green
    } else {
        Write-Host "FAIL: psql --version did not return expected output or exit code 0." -ForegroundColor Red
    }

    # Test 2: psql connection failure to port 1 (must fail with exit code 2 and return error output)
    $test2Pass = $false
    try {
        $failOut = Invoke-Native -FilePath "psql" -Arguments @("-h", "localhost", "-p", "1", "-U", "postgres", "-c", "select 1") -AllowedExitCodes @(2)
        if ($failOut -ne $null) {
            $test2Pass = $true
        }
    } catch {
        $test2Pass = $false
    }

    if ($test2Pass) {
        Write-Host "PASS: psql to invalid port returned expected exit code 2." -ForegroundColor Green
    } else {
        Write-Host "FAIL: psql to invalid port did not return expected exit code 2." -ForegroundColor Red
    }
}
