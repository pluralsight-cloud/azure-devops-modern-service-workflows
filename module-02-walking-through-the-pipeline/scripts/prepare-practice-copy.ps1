#requires -Version 7.0
param(
    [Parameter(Position = 0)][string]$Scenario = '',
    [Parameter(Position = 1)][string]$Destination = '',
    [Parameter(Position = 2)][string]$BuildId = '',
    [Parameter(ValueFromRemainingArguments = $true)][string[]]$ExtraArguments = @()
)
. (Join-Path $PSScriptRoot '../../shared/LocalChecks.Common.ps1')
$source = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../module-01-setting-up-traceable-delivery/orders-api'))
if (-not (Test-Path -LiteralPath $source -PathType Container)) {
    Write-Output "STOP: canonical orders-api not found at $source"
    exit 66
}
if ($ExtraArguments.Count -or $Scenario -cnotin @('corrected', 'failing', 'duplicate') -or -not $Destination) {
    Write-Output 'Usage: pwsh -File prepare-practice-copy.ps1 corrected|failing|duplicate <empty-or-new-dir> [numeric-seed-build-id]'
    exit 64
}
$destinationPath = [System.IO.Path]::GetFullPath($Destination)
if (Test-Path -LiteralPath $destinationPath) {
    $item = Get-Item -LiteralPath $destinationPath -Force
    if (-not $item.PSIsContainer -or ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -or @(Get-ChildItem -LiteralPath $destinationPath -Force).Count) {
        Write-Output "STOP: $Destination exists and is not an empty ordinary directory; nothing was changed."
        exit 2
    }
}
if ($Scenario -ceq 'duplicate' -and $BuildId -cnotmatch '^[0-9]+$') {
    Write-Output 'STOP: duplicate needs the numeric Build ID of the run that already pushed the package; read it from the feed page, never guess.'
    exit 64
}
$feed = $env:PRACTICE_FEED_URL
if ($feed -and $feed -cnotmatch '^https://pkgs\.dev\.azure\.com/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+/_packaging/[A-Za-z0-9._-]+/nuget/v3/index\.json$') {
    Write-Output 'STOP: PRACTICE_FEED_URL must be a project-scoped https://pkgs.dev.azure.com/<org>/<project>/_packaging/<feed>/nuget/v3/index.json URL.'
    exit 64
}
$python = Find-LocalPython
$resolve = 'import json, pathlib, sys; print(json.dumps({"source": str(pathlib.Path(sys.argv[1]).resolve(strict=True)), "destination": str(pathlib.Path(sys.argv[2]).resolve(strict=False))}))'
$paths = (Invoke-LocalPython $python @('-c', $resolve, $source, $destinationPath)).Text | ConvertFrom-Json
$source = $paths.source
$destinationPath = $paths.destination
$relative = [System.IO.Path]::GetRelativePath($source, $destinationPath)
if ($relative -eq '.' -or (-not [System.IO.Path]::IsPathRooted($relative) -and $relative -ne '..' -and -not $relative.StartsWith("../") -and -not $relative.StartsWith('..\'))) {
    Write-Output 'STOP: the destination must be outside the canonical application.'
    exit 64
}
Copy-LocalApp $source $destinationPath
$stage = Join-Path $destinationPath 'ci/build-stage.yml'
if ($feed) {
    $found = [regex]::Matches([System.IO.File]::ReadAllText($stage), 'https://pkgs\.dev\.azure\.com/[^/\s"]+/[^/\s"]+/_packaging/[^/\s"]+/nuget/v3/index\.json')
    Assert-Local ($found.Count -eq 1) "Expected exactly one feed URL in $stage, found $($found.Count)"
    Set-LocalReplacement $stage $found[0].Value $feed
}
if ($Scenario -ceq 'failing') {
    Set-LocalReplacement (Join-Path $destinationPath 'tests/Orders.Checks/Program.cs') 'order.Status != "ready"' 'order.Status != "shipped"'
} elseif ($Scenario -ceq 'duplicate') {
    Set-LocalReplacement $stage 'PACKAGE_VERSION: 1.0.$(Build.BuildId)' "PACKAGE_VERSION: 1.0.$BuildId"
    Set-LocalReplacement $stage 'Globomantics.Orders.Contracts.1.0.$(Build.BuildId).nupkg' "Globomantics.Orders.Contracts.1.0.$BuildId.nupkg"
}
Write-Output "Prepared '$Scenario' copy in: $destinationPath"
if (-not $feed) {
    Write-Output 'WARNING: PRACTICE_FEED_URL not set; a practice run of this copy pushes to the real feed in ci/build-stage.yml.'
}
Write-Output 'Difference from the canonical sample (empty for corrected):'
foreach ($change in @(Get-LocalTreeChanges $source $destinationPath)) {
    Write-Output "--- canonical/$($change.Path)"
    Write-Output "+++ copy/$($change.Path)"
    foreach ($line in $change.Lines) {
        $prefix = if ($line.SideIndicator -eq '<=') { '-' } else { '+' }
        Write-Output "$prefix$($line.InputObject)"
    }
}
