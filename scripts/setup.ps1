<#
 One-command setup for Windows PowerShell.
   $env:PGPASSWORD = "your_postgres_password"
   powershell -ExecutionPolicy Bypass -File scripts/setup.ps1
 Options: -Reset (drop and rebuild an existing database), -Database, -User, -NoNpm
#>
[CmdletBinding()]
param(
    [string]$Database = "butterfly",
    [string]$User = "postgres",
    [string]$AppPassword = "change_me",
    [switch]$Reset,
    [switch]$NoNpm
)
$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($env:PGPASSWORD)) { throw "Set `$env:PGPASSWORD to your PostgreSQL password first." }
if (-not (Get-Command psql -ErrorAction SilentlyContinue)) { throw "psql not found. Install PostgreSQL 16+ and add its bin folder to PATH." }
$root = Resolve-Path (Join-Path $PSScriptRoot "..")
Push-Location $root
function Run-Psql($db, $file) { & psql -X -q -v ON_ERROR_STOP=1 -U $User -d $db -f $file | Out-Null; if ($LASTEXITCODE -ne 0) { throw "psql failed on $file" } }
try {
    $exists = & psql -X -t -A -U $User -d postgres -c "SELECT 1 FROM pg_database WHERE datname='$Database'"
    if (-not $exists) { Write-Host "Creating database $Database ..."; & psql -X -q -U $User -d postgres -c "CREATE DATABASE $Database" }
    elseif ($Reset) { Write-Host "Resetting $Database ..."; Run-Psql $Database "db/schema/drop_all.sql" }
    elseif ((& psql -X -t -A -U $User -d $Database -c "SELECT to_regclass('public.event') IS NOT NULL") -eq "t") {
        Write-Host "Database $Database already has the schema. Re-run with -Reset to rebuild."; $skip = $true
    }
    if (-not $skip) {
        Write-Host "Applying schema, procedures, views and security ..."; Run-Psql $Database "db/schema/_all.sql"
        Write-Host "Seeding Alderbrook ...";                              Run-Psql $Database "db/seed/_seed_all.sql"
        Write-Host "Loading the story pack (Who Burned the Mill?) ...";  Run-Psql $Database "db/seed/_seed_story.sql"
        & psql -X -q -U $User -d $Database -c "ALTER ROLE butterfly_app PASSWORD '$AppPassword'" | Out-Null
        & psql -X -q -U $User -d $Database -c "ALTER ROLE butterfly_gm PASSWORD '$AppPassword'" | Out-Null
    }
    if (-not (Test-Path "backend/.env")) {
        $secret = -join ((48..57) + (97..102) | Get-Random -Count 48 | ForEach-Object { [char]$_ })
        (Get-Content "backend/.env.example") `
            -replace "PG_APP_PASSWORD=.*", "PG_APP_PASSWORD=$AppPassword" `
            -replace "PG_GM_PASSWORD=.*", "PG_GM_PASSWORD=$AppPassword" `
            -replace "SESSION_SECRET=.*", "SESSION_SECRET=$secret" | Set-Content "backend/.env"
        Write-Host "Wrote backend/.env (random SESSION_SECRET)."
    }
    if (-not $NoNpm) { Push-Location backend; npm install --no-audit --no-fund; Pop-Location }
    Write-Host ""
    Write-Host "Done. Start the game:  cd backend ; npm start   then open http://localhost:4000" -ForegroundColor Green
    Write-Host "No database handy?   cd backend ; npm run mock   then open http://localhost:4100"
} finally { Pop-Location }
