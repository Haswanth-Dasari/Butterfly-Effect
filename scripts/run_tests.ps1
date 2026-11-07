<# Runs every SQL test suite, each on a freshly rebuilt and seeded database.
   $env:PGPASSWORD = "..." ; powershell -ExecutionPolicy Bypass -File scripts/run_tests.ps1
   WARNING: this DROPS and recreates the schema in the target database. Use a scratch database. #>
[CmdletBinding()]
param([string]$Database = "butterfly_test", [string]$User = "postgres")
$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($env:PGPASSWORD)) { throw "Set `$env:PGPASSWORD first." }
$root = Resolve-Path (Join-Path $PSScriptRoot ".."); Push-Location $root
$exists = & psql -X -t -A -U $User -d postgres -c "SELECT 1 FROM pg_database WHERE datname='$Database'"
if (-not $exists) { & psql -X -q -U $User -d postgres -c "CREATE DATABASE $Database" }
$pass = 0; $fail = @()
foreach ($t in Get-ChildItem db/tests/*.sql | Sort-Object Name) {
    & psql -X -q -v ON_ERROR_STOP=1 -U $User -d $Database -f db/schema/drop_all.sql 2>&1 | Out-Null
    & psql -X -q -v ON_ERROR_STOP=1 -U $User -d $Database -f db/schema/_all.sql  2>&1 | Out-Null
    & psql -X -q -v ON_ERROR_STOP=1 -U $User -d $Database -f db/seed/_seed_all.sql 2>&1 | Out-Null
    $out = & psql -X -v ON_ERROR_STOP=1 -U $User -d $Database -f $t.FullName 2>&1
    if ($LASTEXITCODE -eq 0) { $pass++; Write-Host "PASS  $($t.Name)" -ForegroundColor Green }
    else { $fail += $t.Name; Write-Host "FAIL  $($t.Name)" -ForegroundColor Red; $out | Select-Object -Last 8 | ForEach-Object { Write-Host "      $_" } }
}
Pop-Location
Write-Host "`n$pass passed, $($fail.Count) failed."; if ($fail.Count) { exit 1 }
