#requires -Version 7.0
. (Join-Path $PSScriptRoot '../../shared/LocalChecks.Common.ps1')
$python = Find-LocalPython
$m1 = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../module-01-setting-up-traceable-delivery'))
$work = New-LocalWork
$owned = $null
$client = New-LocalHttpClient
$revision = '0123456789abcdef0123456789abcdef01234567'
try {
    $yaml = Invoke-LocalPython $python @((Join-Path $m1 'scripts/check-yaml.py'))
    Write-Output $yaml.Text
    $entry = [System.IO.File]::ReadAllText((Join-Path $m1 'orders-api/azure-pipelines.yml'))
    foreach ($literal in @("eq(parameters.deployStaging, true)", "eq(variables['Build.SourceBranch'], 'refs/heads/main')", 'environment: staging', 'artifact: orders-api-web', 'appType: webAppLinux')) {
        Assert-Local ($entry.Contains($literal)) "Deployment YAML missing $literal"
    }
    Assert-Local ($entry -cmatch '(?m)^\s*azureSubscription: [A-Za-z0-9._-]+\s*$') 'Deployment YAML missing azureSubscription'
    Assert-Local ($entry -cmatch '(?m)^\s*appName: [A-Za-z0-9-]+\s*$') 'Deployment YAML missing appName'
    Write-Output 'M3-1 ok: opt-in/main deployment gate, staging environment, artifact and named service connection and App Service'

    $app = Join-Path $work 'orders-api'
    Copy-LocalApp (Join-Path $m1 'orders-api') $app
    $build = Invoke-LocalBuild $app (Join-Path $work 'build.log') '4300' $revision '1.0.4300'
    Assert-LocalMatch $build.Text '(?m)^PASS: deployable output and contracts package prepared\r?$'
    $web = Join-Path $app 'out/web'
    Assert-Local (Test-Path -LiteralPath (Join-Path $web 'Orders.Api.dll')) 'Web assembly missing.'
    Assert-Local (Test-Path -LiteralPath (Join-Path $web 'release-evidence.txt')) 'Evidence file missing.'
    Write-Output 'M3-2 ok: isolated web output and evidence built; nothing pushed'

    $url = "http://127.0.0.1:$(Get-LocalPort)"
    $owned = Start-LocalProcess 'dotnet' @('Orders.Api.dll', '--urls', $url) $web
    $health = Wait-LocalHttp $client "$url/health" $owned
    $release = Get-LocalHttp $client "$url/release"
    $order = Get-LocalHttp $client "$url/orders/42"
    $expected = "workload=orders-api`nrun_id=4300`nsource_revision=$revision`npackage_version=1.0.4300`n"
    Assert-Local ($release.Status -eq 200 -and $release.Type -ceq 'text/plain' -and $release.Content -ceq $expected) 'Release HTTP status/type/four-line metadata differ.'
    Assert-Local ($health.Status -eq 200 -and $health.Content -ceq '{"status":"ok"}') 'Health response differs.'
    Assert-Local ($order.Status -eq 200 -and $order.Content -ceq '{"id":42,"status":"ready"}') 'Order response differs.'
    Write-Output "--- GET /release ---`n$($release.Content)"
    Write-Output "--- GET /health ---`n$($health.Content)"
    Write-Output "--- GET /orders/42 ---`n$($order.Content)"
    Write-Output 'M3-3 ok: actual loopback endpoints have expected status, content type and body'

    Remove-Item -LiteralPath (Join-Path $web 'release-evidence.txt')
    $missing = Get-LocalHttp $client "$url/release"
    Assert-Local ($missing.Status -eq 404) 'Missing evidence must return HTTP 404.'
    Write-Output 'M3-4 ok: missing evidence returns HTTP 404'
    Stop-LocalProcess $owned
    $owned = $null

    $template = Join-Path $m1 '../shared/release-evidence.md'
    $text = [System.IO.File]::ReadAllText($template).Replace("`r`n", "`n")
    $old = "- Run ID: pending`n- Revision (full 40-character commit ID): pending`n- Package ("
    Assert-Local ($text.Contains($old)) 'Section C fixture marker missing.'
    $text = $text.Replace($old, "- Run ID: 4300`n- Revision (full 40-character commit ID): $revision`n- Package (")
    $text = $text.Replace('- Deployment (`staging` environment history): pending', '- Deployment (`staging` environment history): run 4300, example entry' + "`n- Approval (staging check): example-approver, 2026-01-01T00:00Z`n- Work item: 128`n- Runtime (/release): run_id=4300, source_revision=$revision")
    $evidencePath = Join-Path $work 'evidence.md'
    Write-LocalText $evidencePath $text
    $check = Invoke-LocalPython $python @((Join-Path $m1 'scripts/check-evidence.py'), $evidencePath)
    $duplicatePath = Join-Path $work 'duplicate-evidence.md'
    Write-LocalText $duplicatePath $text.Replace('- Run ID: pending', '- Run ID: 4300')
    $negative = Invoke-LocalPython -Python $python -Arguments @((Join-Path $m1 'scripts/check-evidence.py'), $duplicatePath) -ExpectedExit 1
    Assert-LocalMatch $negative.Text 'share Run ID 4300'
    $check = Invoke-LocalPython $python @((Join-Path $m1 'scripts/check-evidence.py'), $template)
    Write-Output 'M3-5 ok: Section C extra fields pass; duplicate run IDs fail; supplied template unchanged'
    Write-Output 'NOT PROVEN LOCALLY: hosted approvals, deployment history, service connections or App Service.'
    Write-Output 'ALL MODULE 3 LOCAL CHECKS PASSED'
} finally {
    try { Stop-LocalProcess $owned }
    finally { $client.Dispose(); Remove-LocalWork $work }
}
