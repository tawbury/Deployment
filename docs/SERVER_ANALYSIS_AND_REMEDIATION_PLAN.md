# 서버 현황 분석 및 수정 계획 리포트

**문서 버전**: 1.0
**작성일**: 2026-02-04
**작성자**: DevSecOps Engineering Team
**대상 시스템**: Observer (KIS 실시간 시세 수집 시스템)
**배포 환경**: OCI ARM K3s Cluster (oracle-obs-vm-01)

---

## 1. Executive Summary

### 1.1 서버 환경 현황

Observer 시스템은 한국투자증권(KIS) API를 활용하여 KOSPI/KOSDAQ 종목의 실시간 시세를 수집, 검증, 필터링 및 아카이빙하는 Python 기반 금융 데이터 분석 서비스입니다.

| 항목 | 현황 |
|------|------|
| **런타임 환경** | K3s (Lightweight Kubernetes) on OCI ARM64 |
| **오케스트레이션** | ArgoCD GitOps + Kustomize |
| **컨테이너 레지스트리** | GitHub Container Registry (ghcr.io) |
| **데이터베이스** | PostgreSQL 15 (Alpine) |
| **애플리케이션 포트** | 8000 (FastAPI/Uvicorn) |
| **현재 이미지 태그** | `build-20260204-101028` |

### 1.2 배포 자동화 구조

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   prj_obs       │───▶│     GHCR        │───▶│  deployment     │
│  (소스 레포)    │    │ (이미지 저장소)  │    │   (K8s 매니페스트) │
└─────────────────┘    └─────────────────┘    └────────┬────────┘
        │                                              │
        │ GitHub Actions                               │ ArgoCD Sync
        │ (ghcr-build-image.yml)                       │
        ▼                                              ▼
┌─────────────────┐                          ┌─────────────────┐
│  Docker Build   │                          │   K3s Cluster   │
│  (ARM64)        │                          │ (oracle-obs-vm) │
└─────────────────┘                          └─────────────────┘
```

### 1.3 핵심 위험 요소 요약

| 등급 | 위험 요소 | 영향도 |
|------|----------|--------|
| **CRITICAL** | JSONL 데이터 볼륨 마운트 미적용 | Pod 재시작 시 수집 데이터 전량 손실 |
| **CRITICAL** | readOnlyRootFilesystem 설정 + 쓰기 볼륨 누락 | 파일 생성 실패, 서비스 장애 |
| **HIGH** | 환경 변수 경로와 실제 마운트 경로 불일치 | 런타임 경로 오류 |

---

## 2. Security & Infrastructure Analysis

### 2.1 prj_obs/src 코드 기반 위험 요소

#### 2.1.1 파일 I/O 처리 로직 분석

소스 코드 전수 조사 결과, 다음 모듈에서 파일 시스템 쓰기 작업이 수행됩니다:

| 모듈 | 파일 | I/O 유형 | 생성 경로 |
|------|------|----------|----------|
| `observer/event_bus.py` | JSONL 이벤트 로그 | Append | `$OBSERVER_DATA_DIR/assets/` |
| `observer/log_rotation_manager.py` | 시간 윈도우 로그 | Create/Rotate | `$OBSERVER_LOG_DIR/{scalp,swing,system}/` |
| `backup/backup_manager.py` | 일일 백업 아카이브 | Create (tar.gz) | `$OBSERVER_DATA_DIR/backups/archives/` |
| `observer/analysis/persistence/dataset_writer.py` | Parquet 데이터셋 | Create | `$OBSERVER_DATA_DIR/datasets/` |
| `retention/cleaner.py` | 보관 정책 삭제 | Delete | 전체 데이터 디렉토리 |

**위험 분석**:
```python
# observer/event_bus.py (Line 127-130)
with open(self.file_path, "a", encoding="utf-8") as f:
    f.write(json.dumps(record.to_dict(), ensure_ascii=False) + "\n")
```
- **문제**: `readOnlyRootFilesystem: true` 설정 시, 볼륨 마운트가 없는 경로에서 `PermissionError` 발생
- **영향**: 이벤트 로깅 실패 → 데이터 수집 중단

#### 2.1.2 하드코딩된 경로 목록

`src/observer/paths.py`에서 관리되는 기본 경로:

```python
# paths.py 기본값 (환경 변수 미설정 시)
DEFAULT_DATA_DIR = "/opt/platform/runtime/observer/data"
DEFAULT_LOG_DIR = "/opt/platform/runtime/observer/logs"
DEFAULT_CONFIG_DIR = "/opt/platform/runtime/observer/config"
DEFAULT_SNAPSHOT_DIR = "/opt/platform/runtime/observer/universe"
```

**문제점**: Dockerfile의 기본 경로와 K8s ConfigMap 설정이 동일하나, 실제 volumeMounts와 불일치 가능성 존재

#### 2.1.3 환경 변수 의존성 매트릭스

| 환경 변수 | 소스 코드 사용처 | ConfigMap 정의 | Dockerfile 정의 | 정합성 |
|----------|----------------|---------------|-----------------|--------|
| `OBSERVER_DATA_DIR` | paths.py, event_bus.py | O | O | **주의** |
| `OBSERVER_LOG_DIR` | paths.py, log_rotation.py | O | O | **주의** |
| `OBSERVER_CONFIG_DIR` | paths.py, config_manager.py | X | O | **불일치** |
| `KIS_TOKEN_CACHE_DIR` | kis_auth.py | X | O | **미사용** |
| `DB_HOST` | realtime_writer.py | O | X | OK |
| `DB_PASSWORD` | realtime_writer.py | Secret | X | OK |

### 2.2 deployment 설정과 실제 인프라 간 불일치

#### 2.2.1 볼륨 마운트 미적용 항목

**현재 Deployment 설정** (`infra/k8s/base/deployments/observer.yaml`):

```yaml
volumeMounts:
  - name: observer-data
    mountPath: /opt/platform/runtime/observer/data
  - name: observer-logs
    mountPath: /opt/platform/runtime/observer/logs
  - name: tmp-config-universe
    mountPath: /opt/platform/runtime/observer/universe
  - name: observer-config
    mountPath: /opt/platform/runtime/observer/config

volumes:
  - name: observer-data
    hostPath:
      path: /opt/platform/runtime/observer/data
      type: DirectoryOrCreate
  # ... (모두 hostPath 사용)
```

**문제점 분석**:

| 항목 | 현재 상태 | 권장 상태 | 위험도 |
|------|----------|----------|--------|
| observer-data | hostPath | PVC (ReadWriteOnce) | CRITICAL |
| observer-logs | hostPath | PVC (ReadWriteOnce) | HIGH |
| observer-config | hostPath | ConfigMap + PVC | MEDIUM |
| tmp-config-universe | hostPath | emptyDir 또는 PVC | LOW |

**hostPath 사용의 문제점**:
1. **노드 바인딩**: Pod가 특정 노드에 고정됨 (스케줄링 유연성 상실)
2. **데이터 격리 실패**: 노드 장애 시 데이터 복구 불가
3. **보안 취약점**: 호스트 파일 시스템 직접 접근 (컨테이너 탈출 위험)

#### 2.2.2 ConfigMap vs 소스 코드 기본값 차이

**ConfigMap** (`infra/k8s/base/configmaps/observer-config.yaml`):
```yaml
data:
  OBSERVER_LOG_DIR: "/opt/platform/runtime/observer/logs"
  OBSERVER_DATA_DIR: "/opt/platform/runtime/observer/data"
```

**소스 코드 기본값** (`src/observer/paths.py`):
```python
path = Path("/opt/platform/runtime/observer/data")  # 동일
```

**결론**: 경로 자체는 일치하나, volumeMounts가 실제로 해당 경로에 마운트되어야 함

#### 2.2.3 Secret 관리 취약점

**현재 상태**:
- Secret 정의 파일은 템플릿만 제공 (`infra/k8s/base/secrets/observer-secrets.yaml`)
- 실제 Secret은 수동으로 `kubectl create secret` 명령 실행 필요
- CI/CD 파이프라인에 Secret 자동 생성 로직 부재

**위험 요소**:
1. 휴먼 에러로 인한 Secret 누락
2. Secret 버전 관리 불가
3. 환경 간 Secret 동기화 어려움

---

## 3. Volume Mapping Assessment

### 3.1 파일 생성 로직이 포함된 파일 리스트

#### 3.1.1 경로별 생성 파일 유형

```
/opt/platform/runtime/observer/
├── data/
│   ├── assets/                    # JSONL 이벤트 로그
│   │   ├── scalp_*.jsonl          # Track B (스캘핑) 데이터
│   │   ├── swing_*.jsonl          # Track A (스윙) 데이터
│   │   └── system_*.jsonl         # 시스템 이벤트
│   ├── backups/
│   │   ├── archives/              # 일일 백업 (tar.gz)
│   │   └── manifests/             # 백업 메타데이터 (JSON)
│   ├── cache/                     # KIS 토큰 캐시 (미사용)
│   └── datasets/                  # Parquet 분석 데이터셋
│
├── logs/
│   ├── scalp/                     # Track B 로그 (1분 윈도우)
│   ├── swing/                     # Track A 로그 (10분 윈도우)
│   ├── system/                    # 시스템 로그 (1시간 윈도우)
│   └── maintenance/               # 유지보수 로그
│
├── config/
│   ├── scalp/                     # 스캘핑 전략 설정
│   ├── swing/                     # 스윙 전략 설정
│   ├── symbols/                   # 심볼 매핑
│   └── universe/                  # 유니버스 정의
│
└── universe/                      # 스냅샷 데이터
```

#### 3.1.2 보관 기간 정책

| 데이터 유형 | 보관 기간 | 자동 삭제 | 담당 모듈 |
|------------|----------|----------|----------|
| decision_snapshot | 3일 | O | retention/cleaner.py |
| pattern_record | 7일 | O | retention/cleaner.py |
| raw_snapshot | 30일 | O | retention/cleaner.py |
| backup_archives | 30일 | O | backup/backup_manager.py |
| scalp_logs | 3일 | O | maintenance/cleanup_manager.py |
| swing_logs | 7일 | O | maintenance/cleanup_manager.py |
| system_logs | 30일 | O | maintenance/cleanup_manager.py |

### 3.2 현재 K8S Deployment 볼륨 매핑 평가

#### 3.2.1 hostPath vs PVC 비교

| 기준 | hostPath (현재) | PVC (권장) |
|------|----------------|------------|
| **데이터 영속성** | 노드 의존 | 스토리지 클래스 의존 |
| **노드 장애 복구** | 불가 | 가능 (동적 프로비저닝) |
| **스케줄링 유연성** | 고정 노드 | 자유 스케줄링 |
| **보안** | 호스트 접근 | 격리된 볼륨 |
| **백업/복원** | 수동 | 스냅샷 지원 |
| **K3s 호환성** | 우수 | local-path 스토리지 클래스 필요 |

#### 3.2.2 누락된 마운트 포인트

**PVC 정의 파일 분석** (`infra/k8s/base/pvc/`):

| PVC 파일 | 정의 여부 | kustomization.yaml 포함 | Deployment 마운트 |
|----------|----------|------------------------|------------------|
| observer-db-pvc.yaml | O | O | postgres.yaml에 마운트 |
| observer-logs-pvc.yaml | O | **주석 처리** | observer.yaml 미연결 |
| observer-data-pvc.yaml | O | **주석 처리** | observer.yaml 미연결 |

**결론**: PVC가 정의되어 있으나 kustomization.yaml에서 주석 처리되어 배포되지 않음

---

## 4. Action Plan (수정 계획)

### 4.1 High Priority

#### 4.1.1 observer-data-pvc 마운트 활성화

**작업 내용**: PVC 기반 볼륨 마운트로 전환

**수정 파일**: `infra/k8s/base/kustomization.yaml`

```yaml
# 변경 전
resources:
  - deployments/postgres.yaml
  - deployments/observer.yaml
  - services/postgres.yaml
  - services/observer-svc.yaml
  - configmaps/observer-config.yaml
  - pvc/observer-db-pvc.yaml
  # - pvc/observer-logs-pvc.yaml  # 주석 해제 필요
  # - pvc/observer-data-pvc.yaml  # 주석 해제 필요

# 변경 후
resources:
  - deployments/postgres.yaml
  - deployments/observer.yaml
  - services/postgres.yaml
  - services/observer-svc.yaml
  - configmaps/observer-config.yaml
  - pvc/observer-db-pvc.yaml
  - pvc/observer-logs-pvc.yaml
  - pvc/observer-data-pvc.yaml
```

**수정 파일**: `infra/k8s/base/deployments/observer.yaml`

```yaml
# 변경 전 (hostPath)
volumes:
  - name: observer-data
    hostPath:
      path: /opt/platform/runtime/observer/data
      type: DirectoryOrCreate

# 변경 후 (PVC)
volumes:
  - name: observer-data
    persistentVolumeClaim:
      claimName: observer-data-pvc
  - name: observer-logs
    persistentVolumeClaim:
      claimName: observer-logs-pvc
```

#### 4.1.2 경로 동기화 수정

**작업 내용**: ConfigMap에 누락된 환경 변수 추가

**수정 파일**: `infra/k8s/base/configmaps/observer-config.yaml`

```yaml
# 추가 항목
data:
  LOG_LEVEL: "INFO"
  LOG_FORMAT: "json"
  SERVICE_PORT: "8000"
  DB_HOST: "postgres"
  DB_PORT: "5432"
  DB_NAME: "observer"
  OBSERVER_LOG_DIR: "/opt/platform/runtime/observer/logs"
  OBSERVER_DATA_DIR: "/opt/platform/runtime/observer/data"
  # 추가 필요
  OBSERVER_CONFIG_DIR: "/opt/platform/runtime/observer/config"
  OBSERVER_SYSTEM_LOG_DIR: "/opt/platform/runtime/observer/logs/system"
  OBSERVER_MAINTENANCE_LOG_DIR: "/opt/platform/runtime/observer/logs/maintenance"
  KIS_TOKEN_CACHE_DIR: "/opt/platform/runtime/observer/data/cache"
```

### 4.2 Medium Priority

#### 4.2.1 Secret 자동 관리 도입

**옵션 A: SealedSecrets (권장)**

```bash
# SealedSecrets 컨트롤러 설치
kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.24.0/controller.yaml

# Secret을 SealedSecret으로 변환
kubeseal --format yaml < observer-secrets.yaml > observer-sealed-secrets.yaml
```

**SealedSecret 예시**:
```yaml
apiVersion: bitnami.com/v1alpha1
kind: SealedSecret
metadata:
  name: observer-secrets
  namespace: observer-prod
spec:
  encryptedData:
    POSTGRES_PASSWORD: AgBY3J9X8z...  # 암호화된 값
    DB_PASSWORD: AgBY3J9X8z...
```

**옵션 B: External Secrets Operator**

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: observer-secrets
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: vault-backend
    kind: ClusterSecretStore
  target:
    name: observer-secrets
  data:
    - secretKey: POSTGRES_PASSWORD
      remoteRef:
        key: observer/database
        property: password
```

#### 4.2.2 Postgres StatefulSet 전환 검토

**현재 문제점**:
- Deployment로 배포된 PostgreSQL은 Pod 재생성 시 호스트명 변경 가능
- 복제본 수 변경 시 데이터 불일치 위험

**권장 변경** (`infra/k8s/base/deployments/postgres.yaml` → `statefulsets/postgres.yaml`):

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres
spec:
  serviceName: postgres
  replicas: 1
  selector:
    matchLabels:
      app: postgres
  template:
    # ... (기존 Pod spec 유지)
  volumeClaimTemplates:
    - metadata:
        name: postgres-data
      spec:
        accessModes: ["ReadWriteOnce"]
        storageClassName: local-path
        resources:
          requests:
            storage: 10Gi
```

### 4.3 Low Priority

#### 4.3.1 KIS 토큰 캐싱 구현

**현재 상태**: `KIS_TOKEN_CACHE_DIR` 환경 변수는 정의되어 있으나, `kis_auth.py`에서 파일 캐싱 미구현

**권장 구현** (`src/provider/kis/kis_auth.py`):

```python
import json
from pathlib import Path

class KISAuth:
    def __init__(self):
        self.cache_dir = Path(os.getenv("KIS_TOKEN_CACHE_DIR", "/tmp/kis_cache"))
        self.cache_file = self.cache_dir / "token_cache.json"

    async def _load_cached_token(self) -> Optional[str]:
        if self.cache_file.exists():
            try:
                data = json.loads(self.cache_file.read_text())
                if datetime.fromisoformat(data["expires_at"]) > datetime.now():
                    return data["access_token"]
            except (json.JSONDecodeError, KeyError):
                pass
        return None

    async def _save_token_cache(self, token: str, expires_in: int):
        self.cache_dir.mkdir(parents=True, exist_ok=True)
        self.cache_file.write_text(json.dumps({
            "access_token": token,
            "expires_at": (datetime.now() + timedelta(seconds=expires_in)).isoformat()
        }))
```

#### 4.3.2 모니터링 강화

**Prometheus ServiceMonitor 추가** (`infra/k8s/base/monitoring/observer-servicemonitor.yaml`):

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: observer
  labels:
    app: observer
spec:
  selector:
    matchLabels:
      app: observer
  endpoints:
    - port: http
      path: /metrics
      interval: 30s
```

**Grafana Dashboard JSON** (ID 참조용):
- PostgreSQL Exporter: 9628
- Python Application: 6417

---

## 5. Conclusion

### 5.1 안정적인 운영을 위한 최종 제언

1. **즉시 조치 (CRITICAL)**
   - `observer-data-pvc`, `observer-logs-pvc` 마운트 활성화
   - hostPath에서 PVC 기반으로 전환
   - ConfigMap 환경 변수 완전성 확보

2. **단기 조치 (1주 내)**
   - SealedSecrets 도입으로 Secret 관리 자동화
   - Postgres StatefulSet 전환 검토

3. **중기 조치 (1개월 내)**
   - KIS 토큰 캐싱 구현으로 재인증 오버헤드 감소
   - Prometheus/Grafana 모니터링 대시보드 구축

### 5.2 구현 로드맵

```
Week 1: Critical Issues
├── Day 1-2: PVC 마운트 활성화 및 테스트
├── Day 3-4: ConfigMap 환경 변수 동기화
└── Day 5: 스테이징 환경 검증

Week 2: Medium Priority
├── Day 1-3: SealedSecrets 도입
└── Day 4-5: Postgres StatefulSet 전환

Week 3-4: Low Priority & Monitoring
├── KIS 토큰 캐싱 구현
└── 모니터링 대시보드 구축
```

### 5.3 검증 체크리스트

- [ ] `kubectl get pvc -n observer-prod` - PVC Bound 상태 확인
- [ ] `kubectl exec -it <pod> -- ls -la /opt/platform/runtime/observer/data` - 마운트 확인
- [ ] Pod 재시작 후 데이터 영속성 테스트
- [ ] ArgoCD Sync 상태 정상 확인
- [ ] `/health` 엔드포인트 응답 확인
- [ ] JSONL 파일 생성 테스트

---

**문서 끝**

*이 리포트는 deployment 및 prj_obs 레포지토리의 정밀 분석을 기반으로 작성되었습니다.*
