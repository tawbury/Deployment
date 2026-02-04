# Observer Monitoring Stack

이 디렉토리는 Observer 애플리케이션의 Prometheus + Grafana 기반 모니터링 설정을 포함합니다.

## 구성 요소

### 1. ServiceMonitor
**파일**: `observer-servicemonitor.yaml`

Prometheus Operator가 자동으로 메트릭을 수집하도록 설정합니다.

- **엔드포인트**: `/metrics`
- **수집 간격**: 30초
- **타임아웃**: 10초

### 2. PrometheusRule
**파일**: `observer-prometheusrule.yaml`

8가지 알림 규칙이 정의되어 있습니다:

| 알림 | 조건 | 심각도 |
|------|------|--------|
| ObserverPodRestarting | Pod 15분간 재시작 | Warning |
| ObserverHighErrorRate | HTTP 5xx > 5% | Critical |
| ObserverNoDataWritten | JSONL 파일 10분간 미생성 | Warning |
| ObserverPVCAlmostFull | PVC 사용량 > 85% | Warning |
| ObserverDatabaseDown | PostgreSQL 다운 (2분) | Critical |
| ObserverHighMemoryUsage | 메모리 > 90% | Warning |
| ObserverHighLatency | P95 지연 > 5초 | Warning |
| ObserverNoActiveConnections | WebSocket 연결 0 | Warning |

### 3. Grafana Dashboard
**파일**: `grafana-dashboard-observer.json`

8개 패널로 구성된 대시보드:

1. **HTTP Request Rate**: 초당 요청 수
2. **HTTP Error Rate**: 5xx 에러율
3. **PVC Usage**: 볼륨 사용량 (%)
4. **Active WebSocket Connections**: 실시간 연결 수
5. **Memory Usage**: Pod 메모리 사용량
6. **HTTP Request Latency (P95)**: 95% 지연시간
7. **JSONL Files Written**: 생성된 파일 수
8. **Pod Status**: Pod 상태 테이블

## 사전 요구사항

### Prometheus Operator 설치

```bash
# Helm으로 kube-prometheus-stack 설치
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false
```

## 배포

### 1. ServiceMonitor 및 PrometheusRule 배포

kustomization.yaml에 포함하여 ArgoCD로 자동 배포:

```yaml
resources:
  - monitoring/observer-servicemonitor.yaml
  - monitoring/observer-prometheusrule.yaml
```

또는 수동 배포:

```bash
kubectl apply -f observer-servicemonitor.yaml -n observer-prod
kubectl apply -f observer-prometheusrule.yaml -n observer-prod
```

### 2. Grafana 대시보드 임포트

#### 방법 A: Grafana UI
1. Grafana에 로그인
2. **Dashboards** → **Import**
3. `grafana-dashboard-observer.json` 업로드
4. Prometheus 데이터소스 선택

#### 방법 B: ConfigMap으로 자동 임포트

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: observer-dashboard
  namespace: monitoring
  labels:
    grafana_dashboard: "1"
data:
  observer-dashboard.json: |
    # grafana-dashboard-observer.json 내용 붙여넣기
```

## 검증

### Prometheus 타겟 확인

```bash
# Prometheus 포트포워딩
kubectl port-forward -n monitoring svc/prometheus-operated 9090:9090

# 브라우저에서 확인
# http://localhost:9090/targets
# observer 엔드포인트가 "UP" 상태인지 확인
```

### 알림 규칙 확인

```bash
# Prometheus UI에서 Alerts 확인
# http://localhost:9090/alerts
```

### Grafana 대시보드 확인

```bash
# Grafana 포트포워딩
kubectl port-forward -n monitoring svc/grafana 3000:3000

# 브라우저에서 확인
# http://localhost:3000
# 기본 로그인: admin / prom-operator
```

## FastAPI 메트릭 엔드포인트

Observer 애플리케이션에 다음 메트릭이 노출되어야 합니다:

```python
# src/observer/api_server.py에 추가 필요
from prometheus_client import Counter, Histogram, Gauge, generate_latest

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

@app.get("/metrics")
async def metrics():
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)
```

## Alertmanager 연동 (선택)

Slack, Email 등으로 알림을 받으려면 Alertmanager 설정 필요:

```yaml
# alertmanager-config.yaml
apiVersion: v1
kind: Secret
metadata:
  name: alertmanager-config
  namespace: monitoring
stringData:
  alertmanager.yaml: |
    global:
      resolve_timeout: 5m

    route:
      group_by: ['alertname', 'severity']
      group_wait: 10s
      group_interval: 10s
      repeat_interval: 12h
      receiver: 'slack'

    receivers:
      - name: 'slack'
        slack_configs:
          - api_url: '<slack-webhook-url>'
            channel: '#observer-alerts'
            title: '{{ range .Alerts }}{{ .Annotations.summary }}{{ end }}'
            text: '{{ range .Alerts }}{{ .Annotations.description }}{{ end }}'
```

## 문제 해결

### ServiceMonitor가 타겟을 인식하지 못함

```bash
# ServiceMonitor 레이블 확인
kubectl get servicemonitor -n observer-prod observer -o yaml

# Prometheus가 감지하는 레이블 확인
kubectl get prometheus -n monitoring -o yaml | grep serviceMonitorSelector

# 레이블 추가
kubectl label servicemonitor observer -n observer-prod release=prometheus
```

### 메트릭이 수집되지 않음

```bash
# Service의 포트 이름 확인 (http 포트가 있어야 함)
kubectl get svc observer-svc -n observer-prod -o yaml

# Pod의 /metrics 엔드포인트 확인
kubectl exec -it -n observer-prod <observer-pod> -- curl http://localhost:8000/metrics
```

### 대시보드에 데이터가 없음

```bash
# Prometheus에서 직접 쿼리 테스트
# http://localhost:9090/graph
# 쿼리: observer_http_requests_total

# 데이터소스 설정 확인
# Grafana → Configuration → Data Sources → Prometheus
```

## 참고 링크

- [Prometheus Operator](https://prometheus-operator.dev/)
- [Grafana Dashboards](https://grafana.com/grafana/dashboards/)
- [PromQL 가이드](https://prometheus.io/docs/prometheus/latest/querying/basics/)
