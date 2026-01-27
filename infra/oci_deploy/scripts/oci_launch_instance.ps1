# Provision a new OCI compute instance with cloud-init for Docker
# Fill placeholders before running.
# Usage:
#   powershell -ExecutionPolicy Bypass -File infra/oci_deploy/scripts/oci_launch_instance.ps1 \
#     -CompartmentId ocid1.compartment.oc1..xxxx \
#     -SubnetId ocid1.subnet.oc1..yyyy \
#     -ImageId ocid1.image.oc1..zzzz \
#     -DisplayName observer-vm \
#     -Shape VM.Standard.A1.Flex \
#     -Ocpus 2 -MemoryInGBs 4

param(
  [Parameter(Mandatory=$true)] [string]$CompartmentId,
  [Parameter(Mandatory=$true)] [string]$SubnetId,
  [Parameter(Mandatory=$true)] [string]$ImageId,
  [string]$DisplayName = "observer-vm",
  [string]$Shape = "VM.Standard.A1.Flex",
  [int]$Ocpus = 2,
  [int]$MemoryInGBs = 4,
  [string]$AssignPublicIp = "true"
)

function Log($m) { Write-Host "[oci] $m" }

# Read cloud-init file and base64 encode (run from project root)
$cloudInitPath = Join-Path (Get-Location).Path "infra/oci_deploy/scripts/cloud-init-docker.yaml"
if (-not (Test-Path $cloudInitPath)) { throw "cloud-init file not found: $cloudInitPath" }
$cloudInitContent = Get-Content -Raw -Path $cloudInitPath
$cloudInitBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($cloudInitContent))

# Create JSON metadata
$metadata = @{ user_data = $cloudInitBase64 } | ConvertTo-Json -Compress

Log "Launching instance: $DisplayName"
$cmd = @(
  "oci","compute","instance","launch",
  "--compartment-id", $CompartmentId,
  "--subnet-id", $SubnetId,
  "--image-id", $ImageId,
  "--display-name", $DisplayName,
  "--shape", $Shape,
  "--shape-config", ("{\"ocpus\": $Ocpus, \"memoryInGBs\": $MemoryInGBs}"),
  "--metadata", $metadata,
  "--assign-public-ip", $AssignPublicIp,
  "--wait-for-state", "RUNNING"
)

$process = Start-Process -FilePath $cmd[0] -ArgumentList $cmd[1..($cmd.Length-1)] -NoNewWindow -PassThru -Wait
if ($process.ExitCode -ne 0) { throw "oci launch failed with exit code $($process.ExitCode)" }

Log "Instance launched. Fetch public IP"
$instancesJson = oci compute instance list --compartment-id $CompartmentId --lifecycle-state RUNNING | ConvertFrom-Json
$inst = $instancesJson.data | Where-Object { $_.displayName -eq $DisplayName } | Select-Object -First 1
if (-not $inst) { throw "Instance not found by display name: $DisplayName" }
$vnics = oci compute instance list-vnics --instance-id $inst.id | ConvertFrom-Json
$pubIp = $vnics.data | Select-Object -ExpandProperty publicIp -First 1
Log "Public IP: $pubIp"
