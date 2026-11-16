#requires -Version 7.0
. (Join-Path $PSScriptRoot '../../shared/LocalChecks.Common.ps1')
$python = Find-LocalPython
$work = New-LocalWork
$source = Join-Path $PSScriptRoot '../orders-api'
$revision = '0123456789abcdef0123456789abcdef01234567'
try {
    Write-Output '== 1. Happy path: native PowerShell build in an isolated copy =='
    $app = Join-Path $work 'happy'
    Copy-LocalApp $source $app
    $run = Invoke-LocalBuild $app (Join-Path $work 'happy.log') '999999' $revision '1.0.999999'
    Write-Output $run.Text
    Assert-LocalMatch $run.Text '(?m)^PASS: positive order and invalid-ID checks\r?$'
    Assert-LocalMatch $run.Text '(?m)^PASS: deployable output and contracts package prepared\r?$'
    Assert-Local (Test-Path -LiteralPath (Join-Path $app 'out/web/Orders.Api.dll')) 'Web output missing.'
    $package = Get-LocalPackage (Join-Path $app 'out/packages/Globomantics.Orders.Contracts.1.0.999999.nupkg')
    Assert-Local ('README.md' -cin $package.Names) 'Package README missing.'
    Assert-Local (Test-Path -LiteralPath (Join-Path $app 'out/web/release-evidence.txt')) 'Evidence missing.'
    Write-Output 'SMOKE-1 ok: pass lines, web output, evidence and package README exist; nothing pushed'

    $guard = Invoke-LocalBuild -App $app -Log (Join-Path $work 'guard.log') -ExpectedExit 2
    Assert-LocalMatch $guard.Text '(?m)^STOP: out already exists'
    Write-Output 'SMOKE-2 ok: stale output exits 2 with STOP line'

    $bad = Join-Path $work 'failing'
    Copy-LocalApp $source $bad
    Set-LocalReplacement (Join-Path $bad 'tests/Orders.Checks/Program.cs') 'order.Status != "ready"' 'order.Status != "shipped"'
    $negative = Invoke-LocalBuild -App $bad -Log (Join-Path $work 'negative.log') -ExpectedExit 1
    Assert-LocalMatch $negative.Text '(?m)^FAIL: positive order contract\r?$'
    Assert-Local (-not (Test-Path -LiteralPath (Join-Path $bad 'out/web/Orders.Api.dll'))) 'Failed check published web output.'
    Assert-Local (@(Get-ChildItem -LiteralPath (Join-Path $bad 'out/packages') -Force).Count -eq 0) 'Failed check packed a package.'
    Write-Output 'SMOKE-3 ok: check exits 1; no publish or package output'

    $clean = Join-Path $work 'clean'
    Copy-LocalApp $source $clean
    $cache = Join-Path $work 'clean-nuget'
    $cliHome = Join-Path $work 'clean-home'
    [void][System.IO.Directory]::CreateDirectory($cache)
    [void][System.IO.Directory]::CreateDirectory($cliHome)
    $cold = Invoke-LocalBuild $clean (Join-Path $work 'clean.log') '999998' $revision '1.0.999998' @{ NUGET_PACKAGES = $cache; DOTNET_CLI_HOME = $cliHome }
    Assert-LocalMatch $cold.Text '(?m)^PASS: deployable output and contracts package prepared\r?$'
    Assert-LocalMatch ([System.IO.File]::ReadAllText((Join-Path $clean 'out/web/release-evidence.txt'))) '(?m)^package_version=1\.0\.999998$'
    Assert-Local (Test-Path -LiteralPath (Join-Path $clean 'out/packages/Globomantics.Orders.Contracts.1.0.999998.nupkg')) 'Cold-cache package missing.'
    Assert-Local (@(Get-ChildItem -LiteralPath $cache -Directory | Where-Object { -not $_.Name.StartsWith('.') }).Count -eq 0) 'Unexpected third-party packages in cold cache.'
    Write-Output 'SMOKE-4 ok: cold cache builds; evidence version equals package version; no third-party packages restored'
    Write-Output 'ALL SMOKE CHECKS PASSED'
} finally { Remove-LocalWork $work }
