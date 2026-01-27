param(
    [string]$ComposeFile = "$PSScriptRoot/../../../docker/compose/docker-compose.yml",
    [string]$Service = "observer",
    [switch]$Build,
    [int]$MaxDriftSeconds = 5
)

function Get-HostEpoch {
    return [int64](Get-Date -UFormat %s)
}

function Get-ContainerEpoch {
    param([string]$Name)
    try {
        $out = docker exec $Name date +%s 2>$null
        if (-not $out) { return $null }
        return [int64]$out.Trim()
    } catch { return $null }
}

if (-not (Test-Path $ComposeFile)) {
    Write-Error "Compose file not found: $ComposeFile"
    exit 1
}

$startArgs = "compose", "-f", $ComposeFile, "up", "-d"
if ($Build) { $startArgs += "--build" }
$startArgs += $Service

# Ensure service is running (and optionally rebuild)
$containerEpoch = Get-ContainerEpoch -Name $Service
if (-not $containerEpoch) {
    Write-Host "Starting $Service (Build=$Build)..."
    & docker @startArgs
    Start-Sleep -Seconds 5
    $containerEpoch = Get-ContainerEpoch -Name $Service
}

$hostEpoch = Get-HostEpoch
if (-not $containerEpoch) {
    Write-Warning "Failed to read container time. Check if service '$Service' is running."
    exit 1
}

$drift = [math]::Abs($hostEpoch - $containerEpoch)
Write-Host "Host epoch: $hostEpoch"
Write-Host "Container epoch: $containerEpoch"
Write-Host "Drift: $drift sec"

if ($drift -gt $MaxDriftSeconds) {
    Write-Warning "Time drift exceeds $MaxDriftSeconds sec. Restarted with current host clock; verify host/WSL clock if drift persists."
    exit 2
}

Write-Host "Time in sync (<= $MaxDriftSeconds sec drift)."
