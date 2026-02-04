# Phase 3: Optimization & Monitoring

**우선순위**: MEDIUM
**예상 작업 시간**: 8-10시간
**작업자 역할**: Backend Developer / SRE (Site Reliability Engineer)
**선행 조건**: Phase 1, 2 완료, Prometheus/Grafana 스택 설치

---

## 목적 (Objective)

KIS API 토큰 캐싱으로 인증 오버헤드를 감소시키고, 관측성(Observability)을 확보하여 시스템 상태를 실시간으로 모니터링합니다.

### 해결할 문제
1. **반복 인증 오버헤드**: Pod 재시작마다 KIS API 토큰을 재발급받아야 함
2. **관측성 부족**: 시스템 메트릭, 로그, 트레이스 통합 모니터링 미흡
3. **장애 대응 지연**: 알림 체계 부재로 문제 감지 지연

---

## Target Files

### 수정 대상 파일 (소스 코드)
```
d:\development\prj_obs\src\provider\kis\
└── kis_auth.py                           # 토큰 캐싱 로직 추가
```

### 새로 생성할 파일 (K8s 매니페스트)
```
d:\development\deployment\infra\k8s\base\
├── monitoring\
│   ├── observer-servicemonitor.yaml      # Prometheus ServiceMonitor
│   ├── observer-prometheusrule.yaml      # 알림 규칙
│   └── grafana-dashboard.json            # Grafana 대시보드
└── kustomization.yaml                    # 모니터링 리소스 추가
```

---

## Part A: KIS 토큰 캐싱 구현

### Step A1: 토큰 캐싱 로직 설계

**목표**: 토큰을 파일로 저장하고, 유효 기간 내에는 재사용합니다.

**설계 요구사항**:
- 토큰 저장 경로: `$KIS_TOKEN_CACHE_DIR/token_cache.json`
- 만료 시간 확인: 토큰 발급 시간 + expires_in
- 스레드 세이프: 파일 lock 사용
- 에러 핸들링: 캐시 파일 손상 시 재인증

---

### Step A2: 소스 코드 수정

**파일**: `d:\development\prj_obs\src\provider\kis\kis_auth.py`

**추가할 코드**:

```python
import json
import fcntl  # Unix/Linux용 파일 lock
import os
from pathlib import Path
from datetime import datetime, timedelta
from typing import Optional, Dict

class KISAuth:
    def __init__(self):
        # 기존 코드...
        self.cache_dir = Path(os.getenv("KIS_TOKEN_CACHE_DIR", "/tmp/kis_cache"))
        self.cache_file = self.cache_dir / "token_cache.json"
        self._ensure_cache_dir()

    def _ensure_cache_dir(self):
        """캐시 디렉토리 생성"""
        try:
            self.cache_dir.mkdir(parents=True, exist_ok=True)
        except Exception as e:
            logger.warning(f"Failed to create cache directory: {e}")

    def _load_cached_token(self) -> Optional[Dict[str, str]]:
        """캐시된 토큰 로드"""
        if not self.cache_file.exists():
            logger.debug("Token cache file does not exist")
            return None

        try:
            with open(self.cache_file, 'r') as f:
                # 파일 lock (읽기)
                fcntl.flock(f.fileno(), fcntl.LOCK_SH)
                try:
                    data = json.load(f)
                finally:
                    fcntl.flock(f.fileno(), fcntl.LOCK_UN)

            # 만료 시간 확인
            expires_at = datetime.fromisoformat(data["expires_at"])
            if expires_at > datetime.now():
                logger.info(f"Using cached token (expires at {expires_at})")
                return data
            else:
                logger.info("Cached token expired")
                return None

        except (json.JSONDecodeError, KeyError, ValueError) as e:
            logger.warning(f"Failed to load token cache: {e}")
            # 손상된 캐시 파일 삭제
            self.cache_file.unlink(missing_ok=True)
            return None

    def _save_token_cache(self, token: str, expires_in: int):
        """토큰을 캐시에 저장"""
        try:
            expires_at = datetime.now() + timedelta(seconds=expires_in)
            data = {
                "access_token": token,
                "expires_at": expires_at.isoformat(),
                "issued_at": datetime.now().isoformat()
            }

            with open(self.cache_file, 'w') as f:
                # 파일 lock (쓰기)
                fcntl.flock(f.fileno(), fcntl.LOCK_EX)
                try:
                    json.dump(data, f, indent=2)
                finally:
                    fcntl.flock(f.fileno(), fcntl.LOCK_UN)

            logger.info(f"Token cached successfully (expires at {expires_at})")

        except Exception as e:
            logger.error(f"Failed to save token cache: {e}")

    async def get_token(self) -> str:
        """토큰 가져오기 (캐시 우선)"""
        # 1. 메모리 캐시 확인 (기존 로직)
        if self.access_token:
            return self.access_token

        # 2. 파일 캐시 확인 (신규 추가)
        cached = self._load_cached_token()
        if cached:
            self.access_token = cached["access_token"]
            return self.access_token

        # 3. 새 토큰 발급 (기존 로직)
        async with self._lock:
            # 다른 스레드가 이미 발급했는지 재확인
            cached = self._load_cached_token()
            if cached:
                self.access_token = cached["access_token"]
                return self.access_token

            # KIS API 호출
            token, expires_in = await self._request_new_token()
            self.access_token = token

            # 4. 캐시에 저장 (신규 추가)
            self._save_token_cache(token, expires_in)

            return token

    async def _request_new_token(self) -> tuple[str, int]:
        """KIS API에서 새 토큰 발급"""
        # 기존 API 호출 로직...
        # return (access_token, expires_in)
        pass
```

**Windows 호환성** (fcntl 대신 msvcrt 사용):
```python
import platform

if platform.system() == "Windows":
    import msvcrt
    def file_lock(f, mode):
        if mode == "shared":
            msvcrt.locking(f.fileno(), msvcrt.LK_LOCK, 1)
        else:  # exclusive
            msvcrt.locking(f.fileno(), msvcrt.LK_LOCK, 1)
    def file_unlock(f):
        msvcrt.locking(f.fileno(), msvcrt.LK_UNLCK, 1)
else:
    import fcntl
    def file_lock(f, mode):
        fcntl.flock(f.fileno(), fcntl.LOCK_SH if mode == "shared" else fcntl.LOCK_EX)
    def file_unlock(f):
        fcntl.flock(f.fileno(), fcntl.LOCK_UN)
```

---

### Step A3: 단위 테스트 작성

**파일**: `d:\development\prj_obs\tests\provider\kis\test_kis_auth.py`

**테스트 케이스**:
```python
import pytest
import tempfile
from pathlib import Path
from datetime import datetime, timedelta
from src.provider.kis.kis_auth import KISAuth

@pytest.fixture
def temp_cache_dir(monkeypatch):
    with tempfile.TemporaryDirectory() as tmpdir:
        monkeypatch.setenv("KIS_TOKEN_CACHE_DIR", tmpdir)
        yield Path(tmpdir)

def test_token_cache_save_and_load(temp_cache_dir):
    auth = KISAuth()
    token = "test-token-12345"
    expires_in = 3600  # 1시간

    # 저장
    auth._save_token_cache(token, expires_in)

    # 로드
    cached = auth._load_cached_token()
    assert cached is not None
    assert cached["access_token"] == token
    assert datetime.fromisoformat(cached["expires_at"]) > datetime.now()

def test_expired_token_not_loaded(temp_cache_dir):
    auth = KISAuth()
    cache_file = temp_cache_dir / "token_cache.json"

    # 만료된 토큰 저장
    expired_data = {
        "access_token": "expired-token",
        "expires_at": (datetime.now() - timedelta(hours=1)).isoformat()
    }
    cache_file.write_text(json.dumps(expired_data))

    # 로드 시도 (None 반환 예상)
    cached = auth._load_cached_token()
    assert cached is None

def test_corrupted_cache_file_handled(temp_cache_dir):
    auth = KISAuth()
    cache_file = temp_cache_dir / "token_cache.json"

    # 손상된 JSON 파일
    cache_file.write_text("invalid json {{{")

    # 로드 시도 (예외 발생하지 않고 None 반환)
    cached = auth._load_cached_token()
    assert cached is None

    # 손상된 파일이 자동 삭제되었는지 확인
    assert not cache_file.exists()
```

---

### Step A4: 로컬 테스트

**실행 명령**:
```bash
cd d:\development\prj_obs

# 가상환경 활성화 (필요 시)
# source venv/bin/activate  # Linux/Mac
# .\venv\Scripts\activate   # Windows

# 테스트 실행
pytest tests/provider/kis/test_kis_auth.py -v

# 커버리지 확인
pytest --cov=src.provider.kis.kis_auth tests/provider/kis/test_kis_auth.py
```

---

### Step A5: Docker 이미지 빌드 및 배포

**실행 명령**:
```bash
cd d:\development\prj_obs

# Git 커밋
git add src/provider/kis/kis_auth.py
git add tests/provider/kis/test_kis_auth.py
git commit -m "feat(kis): implement token caching to reduce API overhead

- Add file-based token cache with expiration check
- Implement thread-safe file locking
- Add unit tests for cache functionality

Reduces authentication overhead by ~50% on Pod restarts.

Refs: docs/SERVER_ANALYSIS_AND_REMEDIATION_PLAN.md Phase 3

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"

# observer 브랜치로 푸시 (GitHub Actions 트리거)
git push origin observer
```

**GitHub Actions가 자동으로**:
1. Docker 이미지 빌드 (ARM64)
2. GHCR에 푸시 (`build-YYYYMMDD-HHMMSS` 태그)
3. deployment 레포의 `kustomization.yaml` 업데이트
4. ArgoCD가 변경 감지하여 자동 배포

---

## Part B: Prometheus 모니터링 구축

### Step B1: FastAPI 메트릭 엔드포인트 추가

**파일**: `d:\development\prj_obs\src\observer\api_server.py`

**추가 의존성** (`requirements.txt`):
```
prometheus-client>=0.19.0
```

**코드 추가**:
```python
from prometheus_client import Counter, Histogram, Gauge, generate_latest, CONTENT_TYPE_LATEST
from fastapi import Response

# 메트릭 정의
http_requests_total = Counter(
    'observer_http_requests_total',
    'Total HTTP requests',
    ['method', 'endpoint', 'status']
)

http_request_duration_seconds = Histogram(
    'observer_http_request_duration_seconds',
    'HTTP request latency',
    ['method', 'endpoint']
)

active_connections = Gauge(
    'observer_active_connections',
    'Active WebSocket connections'
)

jsonl_files_written = Counter(
    'observer_jsonl_files_written_total',
    'Total JSONL files written',
    ['track']
)

# FastAPI 미들웨어
@app.middleware("http")
async def metrics_middleware(request: Request, call_next):
    start_time = time.time()
    response = await call_next(request)
    duration = time.time() - start_time

    http_requests_total.labels(
        method=request.method,
        endpoint=request.url.path,
        status=response.status_code
    ).inc()

    http_request_duration_seconds.labels(
        method=request.method,
        endpoint=request.url.path
    ).observe(duration)

    return response

# 메트릭 엔드포인트
@app.get("/metrics")
async def metrics():
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)
```

---

### Step B2: ServiceMonitor 생성

**파일**: `d:\development\deployment\infra\k8s\base\monitoring\observer-servicemonitor.yaml`

**내용**:
```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: observer
  labels:
    app: observer
    release: prometheus  # Prometheus Operator가 감지하는 레이블
spec:
  selector:
    matchLabels:
      app: observer
  endpoints:
    - port: http
      path: /metrics
      interval: 30s
      scrapeTimeout: 10s
  namespaceSelector:
    matchNames:
      - observer-prod
```

---

### Step B3: PrometheusRule 생성 (알림 규칙)

**파일**: `d:\development\deployment\infra\k8s\base\monitoring\observer-prometheusrule.yaml`

**내용**:
```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: observer-alerts
  labels:
    prometheus: kube-prometheus
    role: alert-rules
spec:
  groups:
    - name: observer
      interval: 30s
      rules:
        # Pod 재시작 알림
        - alert: ObserverPodRestarting
          expr: rate(kube_pod_container_status_restarts_total{namespace="observer-prod", pod=~"observer-.*"}[15m]) > 0
          for: 5m
          labels:
            severity: warning
          annotations:
            summary: "Observer Pod가 반복적으로 재시작됨"
            description: "Pod {{ $labels.pod }}가 최근 15분간 재시작되었습니다."

        # HTTP 에러율 알림
        - alert: ObserverHighErrorRate
          expr: |
            (
              sum(rate(observer_http_requests_total{status=~"5.."}[5m]))
              /
              sum(rate(observer_http_requests_total[5m]))
            ) > 0.05
          for: 5m
          labels:
            severity: critical
          annotations:
            summary: "HTTP 5xx 에러율이 5%를 초과함"
            description: "최근 5분간 에러율: {{ $value | humanizePercentage }}"

        # JSONL 파일 생성 중단 알림
        - alert: ObserverNoDataWritten
          expr: |
            increase(observer_jsonl_files_written_total[10m]) == 0
          for: 10m
          labels:
            severity: warning
          annotations:
            summary: "JSONL 파일이 10분간 생성되지 않음"
            description: "데이터 수집이 중단되었을 가능성이 있습니다."

        # PVC 용량 알림
        - alert: ObserverPVCAlmostFull
          expr: |
            (
              kubelet_volume_stats_used_bytes{namespace="observer-prod", persistentvolumeclaim=~"observer-.*"}
              /
              kubelet_volume_stats_capacity_bytes{namespace="observer-prod", persistentvolumeclaim=~"observer-.*"}
            ) > 0.85
          for: 5m
          labels:
            severity: warning
          annotations:
            summary: "PVC 사용량이 85%를 초과함"
            description: "{{ $labels.persistentvolumeclaim }}: {{ $value | humanizePercentage }} 사용 중"

        # DB 연결 실패 알림
        - alert: ObserverDatabaseDown
          expr: |
            up{job="postgres", namespace="observer-prod"} == 0
          for: 2m
          labels:
            severity: critical
          annotations:
            summary: "PostgreSQL 데이터베이스가 다운됨"
            description: "Observer가 DB에 연결할 수 없습니다."
```

---

### Step B4: Grafana 대시보드 생성

**파일**: `d:\development\deployment\infra\k8s\base\monitoring\grafana-dashboard.json`

**기본 패널 구성**:

1. **Overview 패널**
   - Pod Status (Running/Pending/Failed)
   - HTTP Request Rate
   - HTTP Error Rate
   - Active Connections

2. **Performance 패널**
   - HTTP Request Latency (P50, P95, P99)
   - JSONL Write Throughput
   - Memory Usage
   - CPU Usage

3. **Storage 패널**
   - PVC Usage (%)
   - JSONL File Count
   - Backup Archive Size

4. **Database 패널**
   - PostgreSQL Connections
   - Query Latency
   - Table Row Counts

**대시보드 JSON 템플릿** (간략 버전):
```json
{
  "dashboard": {
    "title": "Observer Production Monitoring",
    "panels": [
      {
        "id": 1,
        "title": "HTTP Request Rate",
        "targets": [
          {
            "expr": "sum(rate(observer_http_requests_total[5m]))"
          }
        ],
        "type": "graph"
      },
      {
        "id": 2,
        "title": "HTTP Error Rate",
        "targets": [
          {
            "expr": "sum(rate(observer_http_requests_total{status=~\"5..\"}[5m])) / sum(rate(observer_http_requests_total[5m]))"
          }
        ],
        "type": "graph"
      },
      {
        "id": 3,
        "title": "PVC Usage",
        "targets": [
          {
            "expr": "(kubelet_volume_stats_used_bytes{namespace=\"observer-prod\"} / kubelet_volume_stats_capacity_bytes{namespace=\"observer-prod\"}) * 100"
          }
        ],
        "type": "gauge"
      }
    ]
  }
}
```

**대시보드 임포트**:
```bash
# Grafana UI에서:
# 1. Dashboards → Import
# 2. JSON 파일 업로드
# 3. Prometheus 데이터소스 선택
```

---

### Step B5: kustomization.yaml 업데이트

**파일**: `d:\development\deployment\infra\k8s\base\kustomization.yaml`

**변경 내용**:
```yaml
# 추가 항목
resources:
  # ... (기존 리소스들)
  - monitoring/observer-servicemonitor.yaml
  - monitoring/observer-prometheusrule.yaml
```

---

### Step B6: Git 커밋 및 배포

**실행 명령**:
```bash
cd d:\development\deployment

git add infra/k8s/base/monitoring/
git add infra/k8s/base/kustomization.yaml
git commit -m "feat(monitoring): add Prometheus ServiceMonitor and alert rules

- Add ServiceMonitor for /metrics endpoint
- Define PrometheusRules for critical alerts
- Add Grafana dashboard template

Refs: docs/SERVER_ANALYSIS_AND_REMEDIATION_PLAN.md Phase 3

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"

git push origin master
```

---

## Verification (검증 체크리스트)

### 1. 토큰 캐싱 검증

```bash
# Pod 재시작 전 토큰 캐시 파일 확인
kubectl exec -it -n observer-prod <observer-pod-name> -- \
  ls -la /opt/platform/runtime/observer/data/cache/

# Pod 재시작
kubectl delete pod -n observer-prod <observer-pod-name>

# 새 Pod에서 캐시 파일 존재 확인 (PVC로 영속화됨)
kubectl exec -it -n observer-prod <new-pod-name> -- \
  cat /opt/platform/runtime/observer/data/cache/token_cache.json

# 로그에서 "Using cached token" 메시지 확인
kubectl logs -n observer-prod <new-pod-name> | grep "cached token"
```

**예상 결과**: Pod 재시작 후 토큰을 재발급받지 않고 캐시 사용

---

### 2. 메트릭 엔드포인트 확인

```bash
# /metrics 엔드포인트 접근
kubectl exec -it -n observer-prod <observer-pod-name> -- \
  curl -s http://localhost:8000/metrics | head -n 20

# 예상 출력:
# # HELP observer_http_requests_total Total HTTP requests
# # TYPE observer_http_requests_total counter
# observer_http_requests_total{endpoint="/health",method="GET",status="200"} 123.0
# ...
```

---

### 3. ServiceMonitor 상태 확인

```bash
# ServiceMonitor 리소스 확인
kubectl get servicemonitor -n observer-prod

# Prometheus가 타겟을 인식했는지 확인
kubectl port-forward -n monitoring svc/prometheus-operated 9090:9090

# 브라우저에서 http://localhost:9090/targets 접근
# observer 엔드포인트가 "UP" 상태인지 확인
```

---

### 4. PrometheusRule 등록 확인

```bash
# PrometheusRule 리소스 확인
kubectl get prometheusrule -n observer-prod

# Prometheus UI에서 알림 규칙 확인
# http://localhost:9090/alerts
```

---

### 5. Grafana 대시보드 확인

```bash
# Grafana 접속
kubectl port-forward -n monitoring svc/grafana 3000:3000

# 브라우저에서 http://localhost:3000 접근
# Dashboards → Observer Production Monitoring 선택
```

**확인 항목**:
- 모든 패널이 데이터를 표시하는지
- 그래프가 실시간 업데이트되는지
- 알림 상태 표시 확인

---

### 6. 알림 테스트

**시나리오 1: Pod 재시작 알림**
```bash
# Pod를 의도적으로 재시작
kubectl delete pod -n observer-prod <observer-pod-name>

# 5분 후 알림 발생 확인 (Alertmanager 또는 Slack)
```

**시나리오 2: PVC 용량 알림**
```bash
# 대용량 더미 파일 생성
kubectl exec -it -n observer-prod <observer-pod-name> -- \
  dd if=/dev/zero of=/opt/platform/runtime/observer/data/test.bin bs=1G count=18

# 알림 발생 확인 (85% 초과)
```

---

## Performance Benchmarking (성능 벤치마크)

### 토큰 캐싱 효과 측정

**측정 항목**:
- 캐싱 전: Pod 시작 후 첫 API 호출 시간
- 캐싱 후: Pod 시작 후 첫 API 호출 시간

**실행 명령**:
```bash
# 캐싱 전 (기존 코드)
time kubectl exec -it -n observer-prod <observer-pod-name> -- \
  python -c "import asyncio; from src.provider.kis.kis_auth import KISAuth; asyncio.run(KISAuth().get_token())"

# 캐싱 후 (Pod 재시작 후)
kubectl delete pod -n observer-prod <observer-pod-name>
# 새 Pod가 Running이 될 때까지 대기
time kubectl exec -it -n observer-prod <new-pod-name> -- \
  python -c "import asyncio; from src.provider.kis.kis_auth import KISAuth; asyncio.run(KISAuth().get_token())"
```

**예상 결과**:
- 캐싱 전: ~500ms (API 호출 포함)
- 캐싱 후: ~50ms (파일 읽기만)
- **성능 향상: ~90%**

---

## Troubleshooting (문제 해결)

### 문제 1: 토큰 캐시 파일이 생성되지 않음

**증상**: Pod 재시작 후에도 항상 새 토큰 발급

**원인**: PVC 마운트 문제 또는 파일 쓰기 권한 부족

**해결책**:
```bash
# PVC 마운트 확인
kubectl describe pod -n observer-prod <observer-pod-name> | grep -A 10 "Mounts:"

# 권한 확인
kubectl exec -it -n observer-prod <observer-pod-name> -- \
  ls -ld /opt/platform/runtime/observer/data/cache

# 디렉토리 권한이 없으면 fsGroup 확인
kubectl get deployment -n observer-prod observer -o yaml | grep fsGroup
```

---

### 문제 2: Prometheus가 메트릭을 수집하지 않음

**증상**: Prometheus 타겟 목록에 observer가 없음

**원인**: ServiceMonitor 레이블 불일치

**해결책**:
```bash
# ServiceMonitor 레이블 확인
kubectl get servicemonitor -n observer-prod observer -o yaml

# Prometheus가 감지하는 레이블 확인
kubectl get prometheus -n monitoring -o yaml | grep serviceMonitorSelector

# 레이블 추가
kubectl label servicemonitor observer -n observer-prod release=prometheus
```

---

### 문제 3: Grafana 대시보드가 "No Data" 표시

**증상**: 대시보드 패널이 비어있음

**원인**: 데이터소스 설정 오류 또는 PromQL 쿼리 오류

**해결책**:
```bash
# Prometheus에서 쿼리 직접 테스트
# http://localhost:9090/graph
# 쿼리: observer_http_requests_total

# 데이터가 있는지 확인
# 없으면 ServiceMonitor 설정 재확인
```

---

## Success Criteria (성공 기준)

다음 모든 항목이 충족되면 Phase 3 완료:

- [ ] `kis_auth.py`에 토큰 캐싱 로직이 구현됨
- [ ] 단위 테스트가 모두 통과함
- [ ] Pod 재시작 후 캐시된 토큰을 사용함
- [ ] `/metrics` 엔드포인트가 메트릭을 반환함
- [ ] Prometheus가 observer 타겟을 "UP"으로 인식함
- [ ] PrometheusRule이 등록되고 알림이 작동함
- [ ] Grafana 대시보드가 실시간 데이터를 표시함
- [ ] 성능 벤치마크에서 90% 이상 개선 확인

---

## Long-term Recommendations (장기 권장 사항)

### 1. 분산 추적 (Distributed Tracing)

**도구**: Jaeger 또는 Tempo
**목적**: 요청 흐름 추적, 병목 구간 식별

```python
# OpenTelemetry 통합
from opentelemetry import trace
from opentelemetry.exporter.jaeger import JaegerExporter

tracer = trace.get_tracer(__name__)

with tracer.start_as_current_span("kis_api_call"):
    token = await kis_auth.get_token()
```

---

### 2. 로그 집계 (Log Aggregation)

**도구**: Loki + Promtail
**목적**: 중앙화된 로그 관리, 검색 및 분석

```yaml
# Promtail DaemonSet
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: promtail
spec:
  template:
    spec:
      containers:
        - name: promtail
          image: grafana/promtail:2.9.0
          volumeMounts:
            - name: logs
              mountPath: /var/log/pods
              readOnly: true
```

---

### 3. 비용 최적화

**도구**: Kubecost
**목적**: 리소스 사용량 분석, 비용 최적화

```bash
# Kubecost 설치
helm install kubecost kubecost/cost-analyzer \
  --namespace kubecost --create-namespace
```

---

## Conclusion

Phase 3를 완료하면 Observer 시스템의 성능이 크게 향상되고, 실시간 모니터링 및 알림 체계가 구축됩니다.

**핵심 성과**:
- 토큰 재발급 오버헤드 90% 감소
- 시스템 장애 감지 시간 단축 (수동 → 자동)
- 관측성 확보로 빠른 문제 해결

---

**문서 작성일**: 2026-02-04
**최종 업데이트**: 2026-02-04
