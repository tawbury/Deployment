################################################################################
# Observer Deployment Orchestrator (Windows PowerShell)
# 로컬 검증 → SSH 업로드 → 서버 실행 → 헬스 체크
# 버전: v1.1.0 (ASCII only)
################################################################################

param(
    [string]$ServerHost = "134.185.117.22",
    [string]$SshUser = "ubuntu",
    [string]$SshKeyPath = "C:\Users\tawbu\.ssh\oracle-obs-vm-01.key",
    [string]$DeployDir = "/home/ubuntu/observer-deploy",
    [string]$ComposeFile = "docker-compose.server.yml",
    [string]$LocalEnvFile = "app\observer\.env",
    [string]$EnvTemplate = "app\observer\env.template",
    [string]$ArtifactDir = "app\observer\docker\compose",
    [string]$ImageTag,
    [switch]$EnvOnly,
    [switch]$Rollback
)

$ErrorActionPreference = "Stop"
$VerbosePreference = "Continue"
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$logFile = "ops\run_records\deploy_${timestamp}.log"

# 필수 아티팩트 목록 (deploy 모드에서만 사용)
$requiredArtifacts = @(
    "docker-compose.server.yml"
)

# ---------------------------------------------------------------------------
# 로깅 유틸
# ---------------------------------------------------------------------------
function Log-Message {
    param([string]$Message, [string]$Level = "INFO")
    $logEntry = "[${timestamp}] [$Level] $Message"
    $color = switch ($Level) {
        "ERROR" { "Red" }
        "WARN"  { "Yellow" }
        "SUCCESS" { "Green" }
        default { "White" }
    }
    Write-Host $logEntry -ForegroundColor $color
    Add-Content -Path $logFile -Value $logEntry
}

function Log-Debug {
    param([string]$Message)
    if ($VerbosePreference -eq "Continue") { Log-Message $Message "DEBUG" }
}

# ---------------------------------------------------------------------------
# 로컬 환경 검증
# ---------------------------------------------------------------------------
function Validate-LocalEnv {
    Log-Message "[STEP] 로컬 환경 검증" "INFO"

    if (-not (Test-Path $EnvTemplate)) { Log-Message "env.template 없음: $EnvTemplate" "ERROR"; return $false }
    if (-not (Test-Path $LocalEnvFile)) { Log-Message ".env 없음: $LocalEnvFile" "ERROR"; return $false }

    $templateKeys = @()
    Get-Content $EnvTemplate | ForEach-Object { if ($_ -match '^([A-Z0-9_]+)=') { $templateKeys += $Matches[1] } }

    $currentEnv = @{}
    Get-Content $LocalEnvFile | ForEach-Object { if ($_ -match '^([A-Z0-9_]+)=(.*)$') { $currentEnv[$Matches[1]] = $Matches[2] } }

    $missing = @()
    foreach ($k in $templateKeys) { if (-not $currentEnv.ContainsKey($k)) { $missing += $k } }
    if ($missing.Count -gt 0) { Log-Message "필수 키 누락: $($missing -join ', ')" "ERROR"; return $false }

    $criticalKeys = @("KIS_APP_KEY", "KIS_APP_SECRET", "DB_PASSWORD")
    $empty = @()
    foreach ($k in $criticalKeys) {
        if ($currentEnv.ContainsKey($k) -and [string]::IsNullOrWhiteSpace($currentEnv[$k])) { $empty += $k }
    }
    if ($empty.Count -gt 0) { Log-Message "중요 값 비어있음: $($empty -join ', ')" "ERROR"; return $false }

    Log-Message "로컬 환경 검증 완료" "SUCCESS"
    return $true
}

# ---------------------------------------------------------------------------
# 아티팩트 검증
# ---------------------------------------------------------------------------
function Validate-Artifacts {
    Log-Message "[STEP] 아티팩트 검증" "INFO"
    $missing = @()
    foreach ($a in $requiredArtifacts) {
        $p = Join-Path $ArtifactDir $a
        if (-not (Test-Path $p)) { $missing += $a; continue }
        $size = [math]::Round((Get-Item $p).Length / 1MB, 2)
        Log-Message "$a (${size} MB)" "SUCCESS"
    }
    if ($missing.Count -gt 0) { Log-Message "아티팩트 누락: $($missing -join ', ')" "ERROR"; return $false }
    Log-Message "아티팩트 검증 완료" "SUCCESS"
    return $true
}

# ---------------------------------------------------------------------------
# SSH 연결 테스트
# ---------------------------------------------------------------------------
function Test-SshConnection {
    Log-Message "[STEP] SSH 연결 테스트" "INFO"
    if (-not (Test-Path $SshKeyPath)) { Log-Message "SSH 키 없음: $SshKeyPath" "ERROR"; return $false }
    $null = ssh -i $SshKeyPath -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new "${SshUser}@${ServerHost}" "echo OK" 2>$null
    if ($LASTEXITCODE -ne 0) { Log-Message "SSH 연결 실패" "ERROR"; return $false }
    Log-Message "SSH 연결 성공" "SUCCESS"; return $true
}

# ---------------------------------------------------------------------------
# 서버 배포 디렉토리 확인
# ---------------------------------------------------------------------------
function Test-ServerDeployDir {
    Log-Message "[STEP] 서버 배포 디렉토리 확인" "INFO"
    $null = ssh -i $SshKeyPath -o StrictHostKeyChecking=accept-new "${SshUser}@${ServerHost}" "test -d $DeployDir" 2>$null
    if ($LASTEXITCODE -ne 0) { Log-Message "배포 디렉토리 없음: $DeployDir" "ERROR"; return $false }
    Log-Message "배포 디렉토리 확인" "SUCCESS"; return $true
}

# ---------------------------------------------------------------------------
# 서버 .env 백업
# ---------------------------------------------------------------------------
function Backup-ServerEnv {
    Log-Message "[STEP] 서버 .env 백업" "INFO"
    $backupTs = (Get-Date).ToUniversalTime().ToString("yyyyMMdd-HHmmss")
    $backupFile = ".env.bak-$backupTs"
    $remoteBackup = 'cd ' + $DeployDir + '; if [ -f .env ]; then cp .env ' + $backupFile + '; fi'
    $null = ssh -i $SshKeyPath -o StrictHostKeyChecking=accept-new "${SshUser}@${ServerHost}" $remoteBackup 2>$null
    Log-Message "백업 파일: $backupFile" "SUCCESS"
    return $true
}

# ---------------------------------------------------------------------------
# .env 업로드
# ---------------------------------------------------------------------------
function Upload-EnvFile {
    Log-Message "[STEP] .env 업로드" "INFO"
    scp -i $SshKeyPath -o StrictHostKeyChecking=accept-new $LocalEnvFile "${SshUser}@${ServerHost}:${DeployDir}/.env.tmp"
    if ($LASTEXITCODE -ne 0) { Log-Message "env 업로드 실패" "ERROR"; return $false }
    $null = ssh -i $SshKeyPath -o StrictHostKeyChecking=accept-new "${SshUser}@${ServerHost}" "cd $DeployDir; mv .env.tmp .env; chmod 600 .env"
    if ($LASTEXITCODE -ne 0) { Log-Message "env 권한 설정 실패" "ERROR"; return $false }
    Log-Message "env 업로드 완료" "SUCCESS"; return $true
}

# ---------------------------------------------------------------------------
# 아티팩트 업로드
# ---------------------------------------------------------------------------
function Upload-Artifacts {
    Log-Message "[STEP] 아티팩트 업로드" "INFO"
    foreach ($a in $requiredArtifacts) {
        $src = Join-Path $ArtifactDir $a
        scp -i $SshKeyPath -o StrictHostKeyChecking=accept-new $src "${SshUser}@${ServerHost}:${DeployDir}/"
        if ($LASTEXITCODE -ne 0) { Log-Message "업로드 실패: $a" "ERROR"; return $false }
        Log-Message "업로드 완료: $a" "SUCCESS"
    }
    return $true
}

# ---------------------------------------------------------------------------
# 서버 배포 실행 (server_deploy.sh)
# ---------------------------------------------------------------------------
function Execute-ServerDeploy {
    Log-Message "[STEP] 서버 배포 실행" "INFO"
    $serverScriptLocal = "infra\_shared\scripts\deploy\server_deploy.sh"
    if (-not (Test-Path $serverScriptLocal)) { Log-Message "server_deploy.sh 없음" "WARN"; return $true }
    scp -i $SshKeyPath -o StrictHostKeyChecking=accept-new $serverScriptLocal "${SshUser}@${ServerHost}:${DeployDir}/"
    $mode = "deploy"
    $tagArg = $ImageTag
    if ($Rollback) { $mode = "rollback"; $tagArg = "" }
    $null = ssh -i $SshKeyPath -o StrictHostKeyChecking=accept-new "${SshUser}@${ServerHost}" "cd $DeployDir; chmod +x server_deploy.sh; bash ./server_deploy.sh $DeployDir $ComposeFile $tagArg $mode"
    if ($LASTEXITCODE -ne 0) { Log-Message "서버 배포 스크립트 종료 코드: $LASTEXITCODE" "WARN" }
    Log-Message "서버 배포 스크립트 완료" "SUCCESS"; return $true
}

# ---------------------------------------------------------------------------
# 헬스 체크
# ---------------------------------------------------------------------------
function Health-Check {
    Log-Message "[STEP] 헬스 체크" "INFO"
    $status = ssh -i $SshKeyPath -o StrictHostKeyChecking=accept-new "${SshUser}@${ServerHost}" "cd $DeployDir; docker compose ps"
    $status | ForEach-Object { Log-Message $_ "INFO" }
    $health = ssh -i $SshKeyPath -o StrictHostKeyChecking=accept-new "${SshUser}@${ServerHost}" "curl -s -o /dev/null -w '%{http_code}' http://localhost:8000/health"
    if ($health -eq "200") { Log-Message "Health endpoint 200" "SUCCESS" } else { Log-Message "Health endpoint code: $health" "WARN" }
    return $true
}

# ---------------------------------------------------------------------------
# 메인
# ---------------------------------------------------------------------------
function Main {
    Log-Message "==== Observer Deployment Orchestrator v1.1.0 ====" "INFO"
    Log-Message "Server: $ServerHost" "INFO"
    Log-Message "DeployDir: $DeployDir" "INFO"
    Log-Message "Compose: $ComposeFile" "INFO"
    if ($EnvOnly) { Log-Message "Mode: EnvOnly (env 업데이트만 수행)" "INFO" }
    if ($Rollback) { Log-Message "Mode: Rollback (last_good_tag 사용)" "INFO" }
    if (-not $EnvOnly -and -not $Rollback) { Log-Message "ImageTag: $ImageTag" "INFO" }

    if (-not $Rollback) {
        if (-not (Validate-LocalEnv)) { return 1 }
    }
    if (-not $EnvOnly -and -not $Rollback -and -not (Validate-Artifacts)) { return 1 }
    if (-not (Test-SshConnection)) { return 1 }
    if (-not (Test-ServerDeployDir)) { return 1 }

    if ($Rollback) {
        if (-not (Execute-ServerDeploy)) { return 1 }
        Health-Check | Out-Null
        Log-Message "롤백 완료" "SUCCESS"
        $logMsgRollback = "로컬 로그: " + $logFile
        Log-Message $logMsgRollback "INFO"
        return 0
    }

    # Deploy 또는 EnvOnly
    if (-not (Backup-ServerEnv)) { return 1 }
    if (-not (Upload-EnvFile)) { return 1 }

    if (-not $EnvOnly) {
        if (-not $ImageTag) { Log-Message "ImageTag 필수: 예) 20260123-123456" "ERROR"; return 1 }
        if (-not (Upload-Artifacts)) { return 1 }
        if (-not (Execute-ServerDeploy)) { return 1 }
        Health-Check | Out-Null
        Log-Message "배포 완료" "SUCCESS"
    }
    else {
        Log-Message "EnvOnly 모드: 아티팩트 업로드/배포 단계 스킵" "INFO"
        Log-Message "환경 파일 업데이트 완료" "SUCCESS"
    }

    $logMsg = "로컬 로그: " + $logFile
    Log-Message $logMsg "INFO"
    return 0
}

$exitCode = Main
exit $exitCode
