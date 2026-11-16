#requires -Version 7.0
. (Join-Path $PSScriptRoot '../../shared/LocalChecks.Common.ps1')
$python = Find-LocalPython
$m1 = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../module-01-setting-up-traceable-delivery'))
$source = Join-Path $m1 'orders-api'
$work = New-LocalWork
$prepare = Join-Path $PSScriptRoot 'prepare-practice-copy.ps1'
$revision = '0123456789abcdef0123456789abcdef01234567'

function New-PracticeCopy {
    param([string]$Scenario, [string]$Destination, [string]$BuildId = '', [string]$Feed, [int[]]$ExpectedExit = @(0))
    Invoke-LocalCommand -File $script:LocalPwsh -Arguments @('-NoLogo', '-NoProfile', '-NonInteractive', '-File', $prepare, $Scenario, $Destination, $BuildId) -Environment @{ PRACTICE_FEED_URL = $Feed } -ExpectedExit $ExpectedExit
}

try {
    $yaml = Invoke-LocalPython $python @((Join-Path $m1 'scripts/check-yaml.py'))
    Write-Output $yaml.Text
    $stage = [System.IO.File]::ReadAllText((Join-Path $source 'ci/build-stage.yml'))
    Assert-Local (-not $stage.Contains('--skip-duplicate')) 'Push must not skip duplicate versions.'
    Assert-Local ($stage.Contains('dotnet nuget push') -and $stage.Contains('PACKAGE_VERSION: 1.0.$(Build.BuildId)')) 'Build version or push step missing.'
    Write-Output 'M2-1 ok: default options, main/publish gates, no skip-duplicate and Build ID version rule'

    $corrected = Join-Path $work 'corrected'
    $prep = New-PracticeCopy corrected $corrected
    Assert-Local (@(Get-LocalTreeChanges $source $corrected).Count -eq 0) 'Corrected copy differs from canonical source.'
    $build = Invoke-LocalBuild $corrected (Join-Path $work 'corrected.log') '111' $revision '1.0.111'
    Assert-LocalMatch $build.Text '(?m)^PASS: positive order and invalid-ID checks\r?$'
    foreach ($path in 'out/web/Orders.Api.dll', 'out/web/release-evidence.txt', 'out/packages/Globomantics.Orders.Contracts.1.0.111.nupkg') {
        Assert-Local (Test-Path -LiteralPath (Join-Path $corrected $path)) "Missing $path"
    }
    Assert-LocalMatch ([System.IO.File]::ReadAllText((Join-Path $corrected 'out/web/release-evidence.txt'))) '(?m)^package_version=1\.0\.111$'
    Write-Output 'M2-2 ok: canonical check passes; web, evidence and package output exist'

    $failing = Join-Path $work 'failing'
    $prep = New-PracticeCopy failing $failing
    $changes = @(Get-LocalTreeChanges $source $failing)
    Assert-Local ($changes.Count -eq 1 -and $changes[0].Path -ceq 'tests/Orders.Checks/Program.cs' -and $changes[0].Lines.Count -eq 2) 'Expected exactly one assertion line changed.'
    $negative = Invoke-LocalBuild -App $failing -Log (Join-Path $work 'failing.log') -RunId '112' -Revision $revision -Version '1.0.112' -ExpectedExit 1
    Assert-LocalMatch $negative.Text '(?m)^FAIL: positive order contract\r?$'
    Assert-Local ($negative.Text -cnotmatch '(?m)^PASS:') 'Failed run emitted a PASS line.'
    foreach ($path in 'out/web/Orders.Api.dll', 'out/web/release-evidence.txt') {
        Assert-Local (-not (Test-Path -LiteralPath (Join-Path $failing $path))) "Failed run produced $path"
    }
    Assert-Local (@(Get-ChildItem -LiteralPath (Join-Path $failing 'out/packages') -Force).Count -eq 0) 'Failed check packed a package.'
    Write-Output 'M2-3 ok: one changed assertion, exit 1, no publish/pack output'

    $duplicate = Join-Path $work 'duplicate'
    $prep = New-PracticeCopy duplicate $duplicate '4242'
    $changes = @(Get-LocalTreeChanges $source $duplicate)
    Assert-Local ($changes.Count -eq 1 -and $changes[0].Path -ceq 'ci/build-stage.yml' -and $changes[0].Lines.Count -eq 4) 'Expected exactly two version-pin changes.'
    $pinned = [System.IO.File]::ReadAllText((Join-Path $duplicate 'ci/build-stage.yml'))
    Assert-Local ($pinned.Contains('PACKAGE_VERSION: 1.0.4242') -and $pinned.Contains('Globomantics.Orders.Contracts.1.0.4242.nupkg')) 'Duplicate pins missing.'
    Assert-Local ($pinned -cnotmatch '(?m)^.*(?:PACKAGE_VERSION|\.nupkg).*\$\(Build\.BuildId\)') 'Version is still derived from Build ID.'
    $check = Invoke-LocalPython $python @((Join-Path $m1 'scripts/check-yaml.py'), $duplicate)
    $invalid = New-PracticeCopy duplicate (Join-Path $work 'bad-id') 'abc' -ExpectedExit 64
    $occupied = New-PracticeCopy failing $failing -ExpectedExit 2
    $warning = New-PracticeCopy corrected (Join-Path $work 'warning')
    Assert-LocalMatch $warning.Text 'WARNING: PRACTICE_FEED_URL not set'
    $retargeted = Join-Path $work 'retargeted'
    $feed = 'https://pkgs.dev.azure.com/sandbox-org/sandbox-proj/_packaging/practice-feed/nuget/v3/index.json'
    $prep = New-PracticeCopy duplicate $retargeted '4242' $feed
    $text = [System.IO.File]::ReadAllText((Join-Path $retargeted 'ci/build-stage.yml'))
    $urls = @([regex]::Matches($text, 'https://pkgs\.dev\.azure\.com/[^\s"]*/index\.json') | ForEach-Object Value)
    Assert-Local ($urls.Count -eq 1 -and $urls[0] -ceq $feed) 'Feed URL did not retarget.'
    $invalid = New-PracticeCopy failing (Join-Path $work 'bad-url') -Feed 'https://example.com/feed' -ExpectedExit 64
    Write-Output 'M2-4b ok: feed override retargets; unset warns; invalid URL exits 64'
    Write-Output 'M2-4 ok: two version pins; bad Build ID exits 64; occupied target exits 2'
    Write-Output 'NOT PROVEN LOCALLY: real Azure Artifacts duplicate-version HTTP 409.'

    $evidence = Invoke-LocalPython $python @((Join-Path $m1 'scripts/check-evidence.py'), (Join-Path $m1 '../shared/release-evidence.md'))
    Write-Output $evidence.Text
    Write-Output 'ALL MODULE 2 LOCAL CHECKS PASSED'
} finally { Remove-LocalWork $work }
