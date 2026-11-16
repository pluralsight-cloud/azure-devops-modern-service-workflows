#requires -Version 7.0
# Replace the course's account-bound names in YOUR copy of the sample pipeline.
# PowerShell twin of set-my-names.sh; see that file or README.md for details.
#   pwsh -File set-my-names.ps1 -Org <your-org> -Project <your-project> -Feed <your-feed> `
#        -App <your-unique-app-name> [-ServiceConnection <name>]
param(
    [Parameter(Mandatory)][string]$Org,
    [Parameter(Mandatory)][string]$Project,
    [Parameter(Mandatory)][string]$Feed,
    [Parameter(Mandatory)][string]$App,
    [string]$ServiceConnection = ''
)
$ErrorActionPreference = 'Stop'
$checks = [ordered]@{
    Org     = @($Org, '^[A-Za-z0-9](?:[A-Za-z0-9-]{0,48}[A-Za-z0-9])?$')
    Project = @($Project, '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$')
    Feed    = @($Feed, '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$')
    App     = @($App, '^[A-Za-z0-9](?:[A-Za-z0-9-]{0,58}[A-Za-z0-9])?$')
}
if ($ServiceConnection) { $checks.ServiceConnection = @($ServiceConnection, '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$') }
foreach ($name in $checks.Keys) {
    if ($checks[$name][0] -cnotmatch $checks[$name][1]) {
        Write-Output "STOP: -$name '$($checks[$name][0])' is not a valid name (letters, digits, '-', no spaces). Nothing was changed."
        exit 64
    }
}
$root = Join-Path $PSScriptRoot 'module-01-setting-up-traceable-delivery/orders-api'
$entry = Join-Path $root 'azure-pipelines.yml'
$stage = Join-Path $root 'ci/build-stage.yml'
$feedUrl = "https://pkgs.dev.azure.com/$Org/$Project/_packaging/$Feed/nuget/v3/index.json"
$edits = @(
    @($stage, 'https://pkgs\.dev\.azure\.com/[^/\s"]+/[^/\s"]+/_packaging/[^/\s"]+/nuget/v3/index\.json', $feedUrl),
    @($stage, '(?m)(displayName: Publish contracts to )\S+$', "`${1}$Feed"),
    @($entry, '(?m)^(\s*appName: )\S+$', "`${1}$App")
)
if ($ServiceConnection) { $edits += , @($entry, '(?m)^(\s*azureSubscription: )\S+$', "`${1}$ServiceConnection") }
$texts = @{ $entry = [System.IO.File]::ReadAllText($entry); $stage = [System.IO.File]::ReadAllText($stage) }
foreach ($edit in $edits) {
    $count = [regex]::Matches($texts[$edit[0]], $edit[1]).Count
    if ($count -ne 1) {
        Write-Output "STOP: expected exactly one match for '$($edit[1])' in $(Split-Path $edit[0] -Leaf), found $count. Nothing was changed."
        exit 2
    }
    $texts[$edit[0]] = [regex]::Replace($texts[$edit[0]], $edit[1], $edit[2])
}
foreach ($path in $texts.Keys) { [System.IO.File]::WriteAllText($path, $texts[$path]) }
Write-Output "Feed URL:            $feedUrl"
Write-Output "App Service name:    $App"
Write-Output "Service connection:  $(if ($ServiceConnection) { $ServiceConnection } else { '(unchanged: sc-globomantics-orders-azure)' })"
Write-Output 'Updated azure-pipelines.yml and ci/build-stage.yml. Review with: git diff'
