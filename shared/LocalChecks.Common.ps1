#requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:LocalWorkDirectories = [System.Collections.Generic.HashSet[string]]::new()
$script:LocalPwsh = Join-Path $PSHOME $(if ($IsWindows) { 'pwsh.exe' } else { 'pwsh' })

function Assert-Local {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw [System.InvalidOperationException]::new("FAIL: $Message") }
}

function Assert-LocalMatch {
    param([string]$Text, [string]$Pattern)
    Assert-Local ($Text -cmatch $Pattern) "Expected output matching: $Pattern"
}

function Write-LocalText {
    param([string]$Path, [string]$Text)
    [System.IO.File]::WriteAllText($Path, $Text, [System.Text.UTF8Encoding]::new($false))
}

function Start-LocalProcess {
    param([string]$File, [string[]]$Arguments, [string]$Directory, [hashtable]$Environment = @{})
    $info = [System.Diagnostics.ProcessStartInfo]::new()
    $info.FileName = $File
    $info.WorkingDirectory = $Directory
    $info.UseShellExecute = $false
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    foreach ($argument in $Arguments) { $info.ArgumentList.Add($argument) }
    $info.Environment['DOTNET_CLI_TELEMETRY_OPTOUT'] = '1'
    $info.Environment['DOTNET_NOLOGO'] = '1'
    foreach ($entry in $Environment.GetEnumerator()) {
        if ($null -eq $entry.Value) { [void]$info.Environment.Remove($entry.Key) }
        else { $info.Environment[$entry.Key] = [string]$entry.Value }
    }
    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $info
    try { [void]$process.Start() }
    catch [System.ComponentModel.Win32Exception] { $process.Dispose(); throw }
    [pscustomobject]@{
        Process = $process
        Output = $process.StandardOutput.ReadToEndAsync()
        Error = $process.StandardError.ReadToEndAsync()
    }
}

function Stop-LocalProcess {
    param($Owned)
    if ($null -eq $Owned) { return }
    try {
        if (-not $Owned.Process.HasExited) { $Owned.Process.Kill($true) }
        Assert-Local ($Owned.Process.WaitForExit(5000)) 'Owned process did not stop within five seconds.'
    } finally { $Owned.Process.Dispose() }
}

function Invoke-LocalCommand {
    param(
        [string]$File, [string[]]$Arguments, [string]$Directory = (Get-Location).Path,
        [hashtable]$Environment = @{}, [string]$Log,
        [int[]]$ExpectedExit = @(0), [int]$TimeoutSeconds = 300
    )
    $owned = Start-LocalProcess $File $Arguments $Directory $Environment
    try {
        Assert-Local ($owned.Process.WaitForExit($TimeoutSeconds * 1000)) "Timed out running $File"
        $text = $owned.Output.GetAwaiter().GetResult() + $owned.Error.GetAwaiter().GetResult()
        $code = $owned.Process.ExitCode
        if ($Log) { Write-LocalText $Log $text }
        Assert-Local ($code -in $ExpectedExit) "$File exited $code (expected $($ExpectedExit -join ',')).`n$text"
        [pscustomobject]@{ ExitCode = $code; Text = $text }
    } finally { Stop-LocalProcess $owned }
}

function Find-LocalPython {
    $candidates = @()
    if ($env:VIRTUAL_ENV) {
        $relative = if ($IsWindows) { 'Scripts/python.exe' } else { 'bin/python' }
        $venv = Join-Path $env:VIRTUAL_ENV $relative
        if (Test-Path -LiteralPath $venv -PathType Leaf) {
            $candidates += @{ File = $venv; Prefix = @() }
        }
    }
    foreach ($name in 'python', 'python3', 'py') {
        $command = Get-Command $name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($command) {
            $prefix = @()
            if ($name -eq 'py') { $prefix = @('-3') }
            $candidates += @{ File = $command.Source; Prefix = $prefix }
        }
    }
    $failures = @()
    foreach ($candidate in $candidates) {
        try {
            $probe = Invoke-LocalCommand -File $candidate.File -Arguments ($candidate.Prefix + @(
                '-c', 'import sys; assert sys.version_info >= (3, 9); import yaml; print("PYTHON_OK")'
            )) -TimeoutSeconds 10
            Assert-LocalMatch $probe.Text '(?m)^PYTHON_OK\r?$'
            return $candidate
        } catch [System.InvalidOperationException] {
            $failures += "$($candidate.File): $($_.Exception.Message)"
        } catch [System.ComponentModel.Win32Exception] {
            $failures += "$($candidate.File): $($_.Exception.Message)"
        }
    }
    throw "Python 3.9+ with PyYAML is required. Install them, then see the root README (Windows PowerShell setup).`n$($failures -join "`n")"
}

function Invoke-LocalPython {
    param($Python, [string[]]$Arguments, [string]$Log, [int[]]$ExpectedExit = @(0))
    Invoke-LocalCommand -File $Python.File -Arguments ($Python.Prefix + $Arguments) -Log $Log -ExpectedExit $ExpectedExit
}

function New-LocalWork {
    $path = Join-Path ([System.IO.Path]::GetTempPath()) "ps orders checks $([guid]::NewGuid().ToString('N'))"
    [void](New-Item -ItemType Directory -Path $path)
    [void]$script:LocalWorkDirectories.Add($path)
    return $path
}

function Remove-LocalWork {
    param([string]$Path)
    Assert-Local ($script:LocalWorkDirectories.Contains($Path)) "Refusing cleanup of an unowned directory: $Path"
    if (Test-Path -LiteralPath $Path) {
        Assert-Local (-not ((Get-Item -LiteralPath $Path).Attributes -band [System.IO.FileAttributes]::ReparsePoint)) 'Temporary root became a link.'
        Remove-Item -LiteralPath $Path -Recurse -Force
    }
    [void]$script:LocalWorkDirectories.Remove($Path)
}

function Copy-LocalApp {
    param([string]$Source, [string]$Destination)
    [void][System.IO.Directory]::CreateDirectory($Destination)
    foreach ($item in Get-ChildItem -LiteralPath $Source -Force) {
        if ($item.Name -in @('out', 'bin', 'obj', '.git', '.venv', '__pycache__', '.DS_Store')) { continue }
        Assert-Local (-not ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) "Source contains a link: $($item.FullName)"
        $target = Join-Path $Destination $item.Name
        if ($item.PSIsContainer) { Copy-LocalApp $item.FullName $target }
        else { Copy-Item -LiteralPath $item.FullName -Destination $target }
    }
}

function Set-LocalReplacement {
    param([string]$Path, [string]$Old, [string]$New)
    $text = [System.IO.File]::ReadAllText($Path)
    Assert-Local ([regex]::Matches($text, [regex]::Escape($Old)).Count -eq 1) "Expected exactly one '$Old' in $Path"
    Write-LocalText $Path $text.Replace($Old, $New)
}

function Get-LocalTreeChanges {
    param([string]$Source, [string]$Destination)
    $files = @{}
    foreach ($file in Get-ChildItem -LiteralPath $Source -File -Recurse -Force) {
        $relative = [System.IO.Path]::GetRelativePath($Source, $file.FullName).Replace('\', '/')
        if (@($relative.Split('/') | Where-Object { $_ -in @('out', 'bin', 'obj', '.git', '.venv', '__pycache__') }).Count) { continue }
        $files[$relative] = $file.FullName
    }
    foreach ($file in Get-ChildItem -LiteralPath $Destination -File -Recurse -Force) {
        $relative = [System.IO.Path]::GetRelativePath($Destination, $file.FullName).Replace('\', '/')
        if (@($relative.Split('/') | Where-Object { $_ -in @('out', 'bin', 'obj', '.git', '.venv', '__pycache__') }).Count) { continue }
        Assert-Local ($files.ContainsKey($relative)) "Unexpected file in copy: $relative"
        $original = $files[$relative]
        [void]$files.Remove($relative)
        if ((Get-FileHash -LiteralPath $original).Hash -eq (Get-FileHash -LiteralPath $file.FullName).Hash) { continue }
        $lines = @(Compare-Object -ReferenceObject ([System.IO.File]::ReadAllLines($original)) -DifferenceObject ([System.IO.File]::ReadAllLines($file.FullName)) -SyncWindow 0 -CaseSensitive)
        [pscustomobject]@{ Path = $relative; Lines = $lines }
    }
    Assert-Local ($files.Count -eq 0) "Missing files in copy: $($files.Keys -join ', ')"
}

function Invoke-LocalBuild {
    param(
        [string]$App, [string]$Log, [string]$RunId = 'local',
        [string]$Revision = 'unrecorded-local', [string]$Version = '1.0.0-local',
        [hashtable]$ExtraEnvironment = @{}, [int[]]$ExpectedExit = @(0)
    )
    $environment = @{ RUN_ID = $RunId; SOURCE_REVISION = $Revision; PACKAGE_VERSION = $Version; RepositoryUrl = $null }
    foreach ($entry in $ExtraEnvironment.GetEnumerator()) { $environment[$entry.Key] = $entry.Value }
    Invoke-LocalCommand -File $script:LocalPwsh -Arguments @('-NoLogo', '-NoProfile', '-NonInteractive', '-File', (Join-Path $App 'ci/build.ps1')) -Directory $App -Environment $environment -Log $Log -ExpectedExit $ExpectedExit
}

function Get-LocalPackage {
    param([string]$Path)
    $zip = [System.IO.Compression.ZipFile]::OpenRead($Path)
    try {
        $names = @($zip.Entries | ForEach-Object { $_.FullName })
        $spec = @($zip.Entries | Where-Object { $_.FullName.EndsWith('.nuspec') })
        Assert-Local ($spec.Count -eq 1) 'Expected one nuspec in the generated package.'
        $reader = [System.IO.StreamReader]::new($spec[0].Open())
        try { $xml = [xml]$reader.ReadToEnd() } finally { $reader.Dispose() }
        [pscustomobject]@{ Names = $names; Metadata = $xml.package.metadata }
    } finally { $zip.Dispose() }
}

function Get-LocalPort {
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    try { $listener.Start(); return $listener.LocalEndpoint.Port }
    finally { $listener.Stop() }
}

function New-LocalHttpClient {
    $handler = [System.Net.Http.HttpClientHandler]::new()
    $handler.UseProxy = $false
    $client = [System.Net.Http.HttpClient]::new($handler)
    $client.Timeout = [timespan]::FromSeconds(2)
    return $client
}

function Get-LocalHttp {
    param($Client, [string]$Url)
    $response = $Client.GetAsync($Url).GetAwaiter().GetResult()
    try {
        [pscustomobject]@{
            Status = [int]$response.StatusCode
            Content = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
            Type = if ($null -ne $response.Content.Headers.ContentType) { $response.Content.Headers.ContentType.MediaType } else { $null }
        }
    } finally { $response.Dispose() }
}

function Wait-LocalHttp {
    param($Client, [string]$Url, $Owned)
    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    $lastFailure = 'No response.'
    while ($timer.Elapsed.TotalSeconds -lt 15) {
        if ($Owned.Process.HasExited) {
            throw "Listener exited early.`n$($Owned.Error.GetAwaiter().GetResult())"
        }
        try {
            $response = Get-LocalHttp $Client $Url
            if ($response.Status -eq 200) { return $response }
            $lastFailure = "HTTP $($response.Status)"
        } catch [System.Net.Http.HttpRequestException] { $lastFailure = $_.Exception.Message }
        catch [System.Threading.Tasks.TaskCanceledException] { $lastFailure = $_.Exception.Message }
        Start-Sleep -Milliseconds 200
    }
    throw "Listener did not become ready in 15 seconds: $Url. $lastFailure"
}
