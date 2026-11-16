#requires -Version 7.0
. (Join-Path $PSScriptRoot '../../shared/LocalChecks.Common.ps1')
$python = Find-LocalPython
$m1 = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../module-01-setting-up-traceable-delivery'))
$workflow = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../workflows/orders-api-github.yml'))
$checker = Join-Path $PSScriptRoot 'check-workflow.py'
$source = Join-Path $m1 'orders-api'
$work = New-LocalWork
$client = New-LocalHttpClient
$owned = $null
$revision = '0123456789abcdef0123456789abcdef01234567'

function Assert-OwnerVariables {
    param([hashtable]$Variables)
    $missing = @('AZURE_CLIENT_ID', 'AZURE_TENANT_ID', 'AZURE_SUBSCRIPTION_ID', 'AZURE_WEBAPP_NAME' | Where-Object { [string]::IsNullOrEmpty($Variables[$_]) })
    Assert-Local ($missing.Count -eq 0) "Owner-provided variable(s) not set: $($missing -join ', '). Ask the owner; values are not printed."
}

function Assert-DeploymentOutput {
    param([string]$Directory, [string]$Version)
    Assert-Local (Test-Path -LiteralPath (Join-Path $Directory 'Orders.Api.dll') -PathType Leaf) 'Downloaded Orders.Api.dll missing.'
    $evidence = Join-Path $Directory 'release-evidence.txt'
    Assert-Local (Test-Path -LiteralPath $evidence -PathType Leaf) 'Downloaded release-evidence.txt missing.'
    Assert-Local ([System.IO.File]::ReadAllLines($evidence) -ccontains "package_version=$Version") 'Downloaded package_version does not match this run.'
}

function Assert-GuardFailure {
    param([scriptblock]$Action, [string]$Pattern)
    $message = ''
    try { & $Action }
    catch [System.InvalidOperationException] { $message = $_.Exception.Message }
    Assert-LocalMatch $message $Pattern
}

try {
    $check = Invoke-LocalPython $python @($checker, $workflow)
    Write-Output $check.Text
    Write-Output 'M4-1 ok: manual dispatch, narrow job permissions, opt-in deployment and full action pins'

    $src = [System.IO.File]::ReadAllText($workflow).Replace("`r`n", "`n")
    $mutations = [ordered]@{
        'bad-yaml' = $src.Replace("    permissions:`n      contents: read`n      packages: write`n", "    permissions:`n`tcontents: read`n      packages: write`n")
        'no-packages' = $src.Replace("      packages: write`n", '')
        'wide' = $src.Replace("permissions:`n  contents: read`n`njobs:", "permissions:`n  contents: read`n  packages: write`n`njobs:")
        'no-attempt' = $src.Replace('-attempt.${GITHUB_RUN_ATTEMPT}', '')
        'wide-oidc' = $src.Replace("permissions:`n  contents: read`n`njobs:", "permissions:`n  contents: read`n  id-token: write`n`njobs:")
        'cancel' = $src.Replace('cancel-in-progress: false', 'cancel-in-progress: true')
        'no-skip' = $src.Replace(" || needs.publish-package.result == 'skipped'", '')
        'literal-id' = $src.Replace('client-id: ${{ vars.AZURE_CLIENT_ID }}', 'client-id: 11111111-2222-3333-4444-555555555555')
        'secret-id' = $src.Replace('client-id: ${{ vars.AZURE_CLIENT_ID }}', 'client-id: ${{ secrets.AZURE_CLIENT_ID }}')
        'no-optin' = $src.Replace('inputs.deployStaging && ', '')
        'wrong-path' = $src.Replace('        package: ${{ runner.temp }}/orders-api-web', '        package: ${{ runner.temp }}/orders-api')
        'tag-pin' = [regex]::Replace($src, '(uses: actions/checkout)@[0-9a-f]{40} # v7\.0\.1', '${1}@v7')
        'no-timeout' = ([regex]::new("    timeout-minutes: 10`n")).Replace($src, '', 1)
    }
    foreach ($mutation in $mutations.GetEnumerator()) {
        Assert-Local ($mutation.Value -cne $src) "Mutation $($mutation.Key) changed nothing."
        $path = Join-Path $work "$($mutation.Key).yml"
        Write-LocalText $path $mutation.Value
        $expectedExit = if ($mutation.Key -eq 'bad-yaml') { 2 } else { 1 }
        $negative = Invoke-LocalPython -Python $python -Arguments @($checker, $path) -ExpectedExit $expectedExit
        Assert-LocalMatch $negative.Text '(?m)^(YAML ERROR|FAIL)'
        Write-Output "-- $($mutation.Key): exit $($negative.ExitCode)"
    }
    Write-Output 'M4-2 ok: malformed YAML exits 2; twelve structural/safety mutations exit 1 and name the rule'

    foreach ($attempt in 1, 2) {
        $app = Join-Path $work "app$attempt"
        Copy-LocalApp $source $app
        $version = "1.0.12-attempt.$attempt"
        $build = Invoke-LocalBuild $app (Join-Path $work "build$attempt.log") "9876543210-$attempt" $revision $version @{ RepositoryUrl = 'https://github.com/globomantics/orders-api' }
        Assert-LocalMatch $build.Text '(?m)^PASS: deployable output and contracts package prepared\r?$'
        $evidence = [System.IO.File]::ReadAllBytes((Join-Path $app 'out/web/release-evidence.txt'))
        $expected = [System.Text.Encoding]::UTF8.GetBytes("workload=orders-api`nrun_id=9876543210-$attempt`nsource_revision=$revision`npackage_version=$version`n")
        Assert-Local ([System.Convert]::ToBase64String($evidence) -ceq [System.Convert]::ToBase64String($expected)) 'Evidence is not exact UTF-8/no-BOM/LF metadata.'
        Assert-Local (Test-Path -LiteralPath (Join-Path $app 'out/web/Orders.Api.dll')) 'Web output missing.'
        $package = Get-LocalPackage (Join-Path $app "out/packages/Globomantics.Orders.Contracts.$version.nupkg")
        Assert-Local ($package.Metadata.version -ceq $version -and $package.Metadata.repository.url -ceq 'https://github.com/globomantics/orders-api') 'nuspec version/repository differ.'
    }
    Write-Output 'M4-3 ok: two attempts have distinct package versions; nuspec and exact evidence bytes agree'

    $compiler = Join-Path $work 'compiler'
    Copy-LocalApp $source $compiler
    $rules = Join-Path $compiler 'src/Orders.Contracts/OrderRules.cs'
    Write-LocalText $rules ([System.IO.File]::ReadAllText($rules) + "`ninternal static class Broken { public static int X = `"not a number`"; }`n")
    $negative = Invoke-LocalBuild -App $compiler -Log (Join-Path $work 'compiler.log') -ExpectedExit 1
    Assert-LocalMatch $negative.Text 'error CS[0-9]+:'
    Assert-Local ($negative.Text -cnotmatch '(?m)^PASS:') 'Compiler failure ran checks.'
    Assert-Local (@(Get-ChildItem -LiteralPath (Join-Path $compiler 'out/packages') -Force).Count -eq 0) 'Compiler failure packed output.'
    $badCheck = Join-Path $work 'check'
    Copy-LocalApp $source $badCheck
    Set-LocalReplacement (Join-Path $badCheck 'tests/Orders.Checks/Program.cs') 'order.Status != "ready"' 'order.Status != "shipped"'
    $negative = Invoke-LocalBuild -App $badCheck -Log (Join-Path $work 'check.log') -ExpectedExit 1
    Assert-LocalMatch $negative.Text '(?m)^FAIL: positive order contract\r?$'
    Assert-Local ($negative.Text -cnotmatch 'error CS') 'Check failure was a compiler error.'
    $corrected = Join-Path $work 'corrected'
    Copy-LocalApp $source $corrected
    $build = Invoke-LocalBuild $corrected (Join-Path $work 'corrected.log')
    Assert-LocalMatch $build.Text '(?m)^PASS: positive order and invalid-ID checks\r?$'
    Assert-LocalMatch $build.Text '(?m)^PASS: deployable output and contracts package prepared\r?$'
    Write-Output 'M4-4 ok: compiler error, failed assertion and corrected run are distinct'

    foreach ($status in 401, 403, 409, 201) {
        $port = Get-LocalPort
        $url = "http://127.0.0.1:$port/index.json"
        $owned = Start-LocalProcess $python.File ($python.Prefix + @((Join-Path $PSScriptRoot 'mock-feed.py'), "$status", "$port")) $work
        try {
            $ready = Wait-LocalHttp $client $url $owned
            $attempt = if ($status -eq 201) { 2 } else { 1 }
            $packagePath = Join-Path $work "app$attempt/out/packages/Globomantics.Orders.Contracts.1.0.12-attempt.$attempt.nupkg"
            $expectedExit = if ($status -eq 201) { 0 } else { 1 }
            $push = Invoke-LocalCommand -File 'dotnet' -Arguments @('nuget', 'push', $packagePath, '--source', $url, '--api-key', 'MOCK', '--allow-insecure-connections') -Log (Join-Path $work "push$status.log") -ExpectedExit $expectedExit
            $signal = switch ($status) {
                401 { '401 \(Unauthorized\)' }
                403 { '403 \(Forbidden\)' }
                409 { '409 \(Conflict\)' }
                201 { 'Your package was pushed\.' }
            }
            Assert-LocalMatch $push.Text $signal
            if ($status -eq 409) { Assert-LocalMatch $push.Text '--skip-duplicate' }
            Write-Output "-- mock HTTP $status : exit $($push.ExitCode)"
        } finally { Stop-LocalProcess $owned; $owned = $null }
    }
    Write-Output 'M4-5 ok: mock 401/403/409 failures and new-version 201 success; not real registry wording'

    $entry = [System.IO.File]::ReadAllText((Join-Path $source 'azure-pipelines.yml')).Replace("`r`n", "`n")
    $artifact = [regex]::Match($entry, 'download: current\s+artifact: (\S+)').Groups[1].Value
    $packageInput = [regex]::Match($entry, 'package: (\S+)').Groups[1].Value
    Assert-Local ($artifact -ceq 'orders-api-web' -and $packageInput -ceq ('$(Pipeline.Workspace)/' + $artifact)) 'Canonical deployment folder differs.'
    $mismatch = $entry.Replace('package: $(Pipeline.Workspace)/orders-api-web', 'package: $(Pipeline.Workspace)/orders-api')
    Assert-Local ([regex]::Match($mismatch, 'package: (\S+)').Groups[1].Value -cne ('$(Pipeline.Workspace)/' + $artifact)) 'Mismatch was not detectable.'
    $workspace = Join-Path $work 'workspace/orders-api-web'
    [void][System.IO.Directory]::CreateDirectory($workspace)
    Copy-Item -LiteralPath (Join-Path $work 'app1/out/web/Orders.Api.dll') -Destination $workspace
    Assert-Local (-not (Test-Path -LiteralPath (Join-Path $work 'workspace/orders-api'))) 'Unexpected wrong-path folder.'
    Write-Output 'M4-6 ok: download/deploy folder mismatch detected statically and in a local directory'

    $extract = 'import json, pathlib, sys, yaml; d=yaml.safe_load(pathlib.Path(sys.argv[1]).read_text()); print(json.dumps(d["jobs"]["deploy-staging"]["steps"]))'
    $parsed = Invoke-LocalPython $python @('-c', $extract, $workflow)
    $steps = @($parsed.Text | ConvertFrom-Json)
    $guardText = $steps[0].run
    $confirmText = @($steps | Where-Object { $_.PSObject.Properties.Name -contains 'run' -and $_.run.Contains('release-evidence.txt') })[0].run
    $variables = @{ AZURE_CLIENT_ID = 'c'; AZURE_TENANT_ID = 't'; AZURE_SUBSCRIPTION_ID = 's'; AZURE_WEBAPP_NAME = 'a' }
    foreach ($name in @($variables.Keys)) {
        Assert-Local ($guardText.Contains($name)) "Hosted guard does not mention $name"
        $missing = $variables.Clone()
        $missing.Remove($name)
        Assert-GuardFailure { Assert-OwnerVariables $missing } ([regex]::Escape($name))
    }
    Assert-OwnerVariables $variables
    foreach ($literal in 'Orders.Api.dll', 'release-evidence.txt', 'package_version=${PACKAGE_VERSION}', '${RUNNER_TEMP}/orders-api-web') {
        Assert-Local ($confirmText.Contains($literal)) "Hosted output guard missing $literal"
    }
    $download = Join-Path $work 'downloaded'
    Copy-LocalApp (Join-Path $work 'app1/out/web') $download
    Assert-DeploymentOutput $download '1.0.12-attempt.1'
    Assert-GuardFailure { Assert-DeploymentOutput $download '1.0.12-attempt.2' } 'package_version'
    Remove-Item -LiteralPath (Join-Path $download 'Orders.Api.dll')
    Assert-GuardFailure { Assert-DeploymentOutput $download '1.0.12-attempt.1' } 'Orders.Api.dll'
    Copy-Item -LiteralPath (Join-Path $work 'app1/out/web/Orders.Api.dll') -Destination $download
    Remove-Item -LiteralPath (Join-Path $download 'release-evidence.txt')
    Assert-GuardFailure { Assert-DeploymentOutput $download '1.0.12-attempt.1' } 'release-evidence.txt'
    Write-Output 'M4-7 ok: native PowerShell guard equivalents reject missing variables/files and wrong-attempt output; hosted Bash checked statically, not executed'
    Write-Output 'NOT PROVEN LOCALLY: GitHub parsing/permissions, approval, OIDC, Azure login or deployment.'
    Write-Output 'ALL MODULE 4 LOCAL CHECKS PASSED'
} finally {
    try { Stop-LocalProcess $owned }
    finally { $client.Dispose(); Remove-LocalWork $work }
}
