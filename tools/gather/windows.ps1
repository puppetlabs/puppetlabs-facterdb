# Gather Facter facts on a hosted Windows runner by installing a pinned Puppet Core puppet-agent MSI
# from artifacts-puppetcore.puppet.com.
#
# Env: PUPPET_FORGE_TOKEN (secret), FACTER_VERSION, AGENT_VERSION, AGENT_MAJOR, PLATFORM_ID, OUT_DIR.
# Exit: 0 and OUT_DIR\result.json for gathered (plus facts.json) or skipped (HTTP 404, no package);
#       non-zero for bad input (2) or any credential, network, install or version error.
# The Basic auth header is built in memory; the token and header are never printed or written to OUT_DIR.
# NOTE: os_version for Server 2022/2025 is confirmed in the 03-07 spike (research A4).
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

foreach ($name in 'PUPPET_FORGE_TOKEN', 'FACTER_VERSION', 'AGENT_VERSION', 'AGENT_MAJOR', 'PLATFORM_ID', 'OUT_DIR') {
  if (-not [Environment]::GetEnvironmentVariable($name)) {
    [Console]::Error.WriteLine("missing required env var: $name")
    exit 2
  }
}

if (($env:FACTER_VERSION -notmatch '^\d+\.\d+\.\d+$') -or
    ($env:AGENT_VERSION -notmatch '^\d+\.\d+\.\d+$') -or
    ($env:AGENT_MAJOR -notmatch '^\d+$') -or
    ($env:PLATFORM_ID -notmatch '^[a-zA-Z0-9._-]+$')) {
  [Console]::Error.WriteLine('invalid input')
  exit 2
}

$utf8 = New-Object Text.UTF8Encoding $false
$facter = 'C:\Program Files\Puppet Labs\Puppet\bin\facter.bat'

function Write-Result([string]$outcome, [string]$reason) {
  New-Item -ItemType Directory -Force -Path $env:OUT_DIR | Out-Null
  $json = '{{"id":"{0}","outcome":"{1}","reason":"{2}"}}' -f $env:PLATFORM_ID, $outcome, $reason
  [IO.File]::WriteAllText((Join-Path $env:OUT_DIR 'result.json'), $json + "`n", $utf8)
}

$osVersion = ([Version](Get-CimInstance Win32_OperatingSystem).Version).Major
$url = "https://artifacts-puppetcore.puppet.com/v1/download?type=native&version=$env:AGENT_VERSION&os_name=windows&os_version=$osVersion&os_arch=x64&fips=false"
$msi = Join-Path ([IO.Path]::GetTempPath()) 'puppet-agent.msi'

$b64 = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("forge-key:$env:PUPPET_FORGE_TOKEN"))
try {
  Invoke-WebRequest -Uri $url -Headers @{ Authorization = "Basic $b64" } -OutFile $msi -UseBasicParsing
} catch {
  $status = $null
  if ($_.Exception.Response) { $status = [int]$_.Exception.Response.StatusCode }
  if ($status -eq 404) {
    Write-Result 'skipped' "puppet-agent $env:AGENT_VERSION not published for Windows $osVersion x64"
    Write-Output 'skipped: no package'
    exit 0
  }
  [Console]::Error.WriteLine("agent download failed with HTTP $status")
  exit 1
}

$proc = Start-Process msiexec.exe -ArgumentList '/qn', '/norestart', '/i', $msi -Wait -PassThru
if (@(0, 1641, 3010) -notcontains $proc.ExitCode) {
  [Console]::Error.WriteLine("msiexec failed with exit code $($proc.ExitCode)")
  exit 1
}

$actual = (& $facter --version | Out-String).Trim()
if ($actual -ne $env:FACTER_VERSION) {
  [Console]::Error.WriteLine("facter $actual != $env:FACTER_VERSION")
  exit 1
}

New-Item -ItemType Directory -Force -Path $env:OUT_DIR | Out-Null
$facts = (& $facter -j | Out-String)
[IO.File]::WriteAllText((Join-Path $env:OUT_DIR 'facts.json'), $facts, $utf8)
Write-Result 'gathered' ''
