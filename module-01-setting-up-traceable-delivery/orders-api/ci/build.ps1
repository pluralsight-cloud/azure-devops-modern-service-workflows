#requires -Version 7.0
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$root = Split-Path -Parent $PSScriptRoot
if (Test-Path -LiteralPath (Join-Path $root 'out')) {
    Write-Output 'STOP: out already exists; inspect and remove only generated output before retry.'
    exit 2
}
$version = if ($env:PACKAGE_VERSION) { $env:PACKAGE_VERSION } else { '1.0.0-local' }
$runId = if ($env:RUN_ID) { $env:RUN_ID } else { 'local' }
$revision = if ($env:SOURCE_REVISION) { $env:SOURCE_REVISION } else { 'unrecorded-local' }
$script:BuildExit = 1

function Invoke-Dotnet {
    param([string[]]$Arguments)
    & dotnet @Arguments
    if ($LASTEXITCODE -ne 0) {
        $script:BuildExit = $LASTEXITCODE
        throw "dotnet $($Arguments -join ' ') failed with exit $script:BuildExit."
    }
}

Push-Location $root
try {
    [void][System.IO.Directory]::CreateDirectory((Join-Path $root 'out/web'))
    [void][System.IO.Directory]::CreateDirectory((Join-Path $root 'out/packages'))
    Invoke-Dotnet @('--version')
    Invoke-Dotnet @('restore', 'src/Orders.Api/Orders.Api.csproj')
    Invoke-Dotnet @('restore', 'tests/Orders.Checks/Orders.Checks.csproj')
    Invoke-Dotnet @('build', 'src/Orders.Api/Orders.Api.csproj', '--configuration', 'Release', '--no-restore')
    Invoke-Dotnet @('build', 'tests/Orders.Checks/Orders.Checks.csproj', '--configuration', 'Release', '--no-restore')
    Invoke-Dotnet @('run', '--project', 'tests/Orders.Checks/Orders.Checks.csproj', '--configuration', 'Release', '--no-build')
    Invoke-Dotnet @('publish', 'src/Orders.Api/Orders.Api.csproj', '--configuration', 'Release', '--no-build', '--output', (Join-Path $root 'out/web'))
    Invoke-Dotnet @('pack', 'src/Orders.Contracts/Orders.Contracts.csproj', '--configuration', 'Release', '--no-build', "-p:PackageVersion=$version", '--output', (Join-Path $root 'out/packages'))
    $evidence = "workload=orders-api`nrun_id=$runId`nsource_revision=$revision`npackage_version=$version`n"
    [System.IO.File]::WriteAllText((Join-Path $root 'out/web/release-evidence.txt'), $evidence, [System.Text.UTF8Encoding]::new($false))
    Write-Host $evidence -NoNewline
    if (-not (Test-Path -LiteralPath (Join-Path $root 'out/web/Orders.Api.dll') -PathType Leaf)) { throw 'Published Orders.Api.dll is missing.' }
    if (-not (Test-Path -LiteralPath (Join-Path $root "out/packages/Globomantics.Orders.Contracts.$version.nupkg") -PathType Leaf)) { throw 'Contracts package is missing.' }
    Write-Output 'PASS: deployable output and contracts package prepared'
    $script:BuildExit = 0
} catch {
    Write-Error $_ -ErrorAction Continue
} finally {
    Pop-Location
}
exit $script:BuildExit
