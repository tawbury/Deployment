# Helper scripts for OCI instance management

function Get-OciInstanceByName {
  param(
    [Parameter(Mandatory=$true)] [string]$CompartmentId,
    [Parameter(Mandatory=$true)] [string]$DisplayName
  )
  $instances = oci compute instance list --compartment-id $CompartmentId --lifecycle-state RUNNING | ConvertFrom-Json
  return ($instances.data | Where-Object { $_.displayName -eq $DisplayName } | Select-Object -First 1)
}

function Remove-OciInstanceByName {
  param(
    [Parameter(Mandatory=$true)] [string]$CompartmentId,
    [Parameter(Mandatory=$true)] [string]$DisplayName,
    [switch]$Force
  )
  $inst = Get-OciInstanceByName -CompartmentId $CompartmentId -DisplayName $DisplayName
  if (-not $inst) { throw "Instance not found: $DisplayName" }
  if (-not $Force) { throw "Use -Force to confirm termination of $DisplayName ($($inst.id))" }
  oci compute instance terminate --instance-id $inst.id --preserve-boot-volume false --wait-for-state TERMINATED
}
