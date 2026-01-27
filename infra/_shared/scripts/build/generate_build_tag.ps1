# Observer Build Tag Generator (PowerShell)
# Purpose: Generate timestamp-based Docker build tags
# Format: YYMMDD-HHMMSS (e.g., 20260126-155945)
# Version: v1.0.0

param(
    [string]$OutputFile = ""
)

function Log-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Green
}

function Log-Warn {
    param([string]$Message)
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

function Log-Error {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

# Tag generation function
function New-BuildTag {
    # Generate timestamp (KST)
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    
    # Convert to YYMMDD-HHMMSS format (20YYMMDD-HHMMSS)
    $tag = "20$($timestamp.Substring(2,6))-$($timestamp.Substring(9,6))"
    
    return $tag
}

# Tag validation function
function Test-BuildTag {
    param([string]$Tag)
    
    # Regex validation: 20YYMMDD-HHMMSS
    if ($Tag -notmatch '^20[0-9]{6}-[0-9]{6}$') {
        Log-Error "Invalid tag format: $Tag"
        Log-Error "Expected format: 20YYMMDD-HHMMSS (e.g., 20260126-155945)"
        return $false
    }
    
    # Date/time validation
    $datePart = $Tag.Substring(0, 8)
    $timePart = $Tag.Substring(9, 6)
    
    try {
        # Date validation (YYYYMMDD)
        $year = [int]$datePart.Substring(0, 4)
        $month = [int]$datePart.Substring(4, 2)
        $day = [int]$datePart.Substring(6, 2)
        
        $dateObj = Get-Date -Year $year -Month $month -Day $day -ErrorAction Stop
        
        # Time validation (HHMMSS)
        $hour = [int]$timePart.Substring(0, 2)
        $minute = [int]$timePart.Substring(2, 2)
        $second = [int]$timePart.Substring(4, 2)
        
        if ($hour -gt 23 -or $minute -gt 59 -or $second -gt 59) {
            Log-Error "Invalid time: $timePart"
            return $false
        }
        
        return $true
    }
    catch {
        Log-Error "Invalid date/time: $Tag"
        Log-Error "Error: $($_.Exception.Message)"
        return $false
    }
}

# Main function
function Main {
    Log-Info "=== Observer Build Tag Generator ==="
    
    # Generate tag
    $tag = New-BuildTag
    Log-Info "Generated tag: $tag"
    
    # Validate tag
    if (-not (Test-BuildTag -Tag $tag)) {
        Log-Error "Tag validation failed"
        exit 1
    }
    
    Log-Info "Tag validation passed: $tag"
    
    # Save to file if OutputFile is specified
    if ($OutputFile -ne "") {
        $dir = Split-Path $OutputFile -Parent
        if ($dir -and -not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
        $tag | Out-File -FilePath $OutputFile -Encoding UTF8 -NoNewline
        Log-Info "Tag saved to: $OutputFile"
    }
    
    # Output tag to stdout (for use in other scripts)
    Write-Output $tag
    
    Log-Info "=== Tag Generation Complete ==="
}

# Execute script
Main
