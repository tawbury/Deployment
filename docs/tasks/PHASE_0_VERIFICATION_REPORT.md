# Phase 0: Foundation Stabilization 검증 보고서

**문서 버전**: 1.0
**작성일**: 2026-02-06
**대상 시스템**: Observer (KIS 실시간 시세 수집 시스템)
**배포 환경**: OCI ARM K3s Cluster / Namespace: observer-prod
**작업 순서**: deployment(GitOps) → server(K3s) → prj_obs(App)

---

## 목적

현재 Observer 시스템이 **"우연히 돌아가는" 상태가 아니라, 실행 계약을 명시적으로 만족하며 돌아가는 상태**인지 검증한다.
Phase 1 진입 시 깨질 수 있는 구조적 위험 요소를 제거하고, 암묵적 의존성을 명시화한다.

**절대 금지**: Helm Chart 작성, CI/CD 변경, 서버 재설치, 앱 비즈니스 로직 변경, Dockerfile 구조 변경, 여러 계층 동시 수정

---

## Critical Findings 요약

| ID | 심각도 | 내용 | 영역 |
|----|--------|------|------|
| CF-1 | CRITICAL | SealedSecret → Secret 이름 불일치: 3개 SealedSecret이 생성하는 Secret(`obs-db-secret`, `obs-kis-secret`, `obs-kiwoom-secret`)과 Deployment가 참조하는 Secret(`observer-secrets`)이 다름 | deployment |
| CF-1 주석 | - | **Phase 0 범위 제한**: `observer-secrets`의 존재 여부와 키 완전성만 확인. 생성 방식(수동 vs SealedSecret 통합 vs External Secrets)은 Phase 1에서 결정. Phase 0에서는 현재 수동 생성 방식이 동작하는지만 검증한다. | - |
| CF-2 | HIGH | `observer-secrets` 수동 생성 가이드에 KIS_APP_KEY, KIS_APP_SECRET, KIS_HTS_ID 누락 | deployment |
| CF-3 | HIGH | 평문 Secret(`observer-prod-plain.yaml`)과 kubeconfig(`obs-prod.yaml`)가 Git에 커밋됨 | deployment |
| CF-4 | MEDIUM | observer-config 볼륨이 PVC가 아닌 hostPath 사용 (DirectoryOrCreate) | deployment |
| CF-5 | LOW | `paths.py`의 mkdir() 호출이 로드맵의 "앱: mkdir 금지" 원칙과 불일치 (실질적 문제 없음) | prj_obs |
| CF-6 | MEDIUM | `PERSISTENCE_AND_HOSTPATH.md` 경로가 현재 Deployment과 불일치 (`/app/logs` vs `/opt/platform/runtime/observer/logs`) | deployment |
| CF-7 | LOW | Production RWO PVC + 2 replicas 조합이 암묵적으로 단일 노드를 전제 | deployment |

---

## 1. deployment (GitOps 레포)

### 1-1. 리소스 인벤토리

#### 활성 리소스 (kustomization.yaml에서 참조)

| 파일 | Kind | 이름 | 역할 |
|------|------|------|------|
| `base/statefulsets/postgres.yaml` | StatefulSet + Headless Service | postgres, postgres-headless | PostgreSQL 15 DB + Headless DNS |
| `base/deployments/observer.yaml` | Deployment | observer | Observer 앱 (Port 8000, /health) |
| `base/services/postgres.yaml` | Service (ClusterIP) | postgres | PostgreSQL 내부 노출 (5432) |
| `base/services/observer-svc.yaml` | Service (ClusterIP) | observer | Observer 내부 노출 (8000) |
| `base/configmaps/observer-config.yaml` | ConfigMap | observer-config | 비밀 아닌 환경 변수 14개 |
| `base/sealed-secrets/obs-db-sealed-secret.yaml` | SealedSecret | obs-db-secret | DB 인증정보 (암호화) |
| `base/sealed-secrets/obs-kis-sealed-secret.yaml` | SealedSecret | obs-kis-secret | KIS API 인증정보 (암호화) |
| `base/sealed-secrets/obs-kiwoom-sealed-secret.yaml` | SealedSecret | obs-kiwoom-secret | Kiwoom API 인증정보 (암호화) |
| `base/pvc/observer-db-pvc.yaml` | PVC | observer-db-pvc | PostgreSQL 데이터 (10Gi, RWO) |
| `base/pvc/observer-data-pvc.yaml` | PVC | observer-data-pvc | JSONL 데이터 (20Gi, RWO) |
| `base/pvc/observer-logs-pvc.yaml` | PVC | observer-logs-pvc | 로그 (5Gi, RWO) |
| `base/pvc/observer-universe-pvc.yaml` | PVC | observer-universe-pvc | Universe 스냅샷 (1Gi, RWO) |

#### 비활성 리소스 (주석 처리됨)

| 파일 | Kind | 비활성 이유 |
|------|------|------------|
| `base/namespaces/observer.yaml` | Namespace | overlay에서 namespace 지정 |
| `base/deployments/postgres.yaml` | Deployment (레거시) | StatefulSet으로 전환됨 |
| `base/monitoring/observer-servicemonitor.yaml` | ServiceMonitor | Phase 3 대상 |
| `base/monitoring/observer-prometheusrule.yaml` | PrometheusRule | Phase 3 대상 |
| `base/ingress/observer-ingress.yaml` | Ingress | 외부 노출 비활성 |

#### Production Overlay

| 항목 | 값 |
|------|------|
| namespace | `observer-prod` |
| image tag | `build-20260205-142425` |
| replicas | 2 (HA) |
| memory limit | 2Gi |
| CPU limit | 1000m |
| commonLabels | `environment: production` |

### 1-2. Phase 0 확인 체크리스트

#### PVC 정의 검증

| PVC | 용량 | AccessMode | StorageClass | 소비자 | 마운트 경로 | 상태 |
|-----|------|-----------|--------------|--------|------------|------|
| observer-db-pvc | 10Gi | RWO | default (local-path) | StatefulSet postgres | `/var/lib/postgresql/data` | [ ] Bound |
| observer-data-pvc | 20Gi | RWO | default (local-path) | Deployment observer | `/opt/platform/runtime/observer/data` | [ ] Bound |
| observer-logs-pvc | 5Gi | RWO | default (local-path) | Deployment observer | `/opt/platform/runtime/observer/logs` | [ ] Bound |
| observer-universe-pvc | 1Gi | RWO | default (local-path) | Deployment observer | `/opt/platform/runtime/observer/universe` | [ ] Bound |

#### volumeMount ↔ 소스 매핑 검증

| Volume Name | Source Type | Source Name/Path | mountPath | ConfigMap 환경 변수 | 일치 |
|-------------|-----------|-----------------|-----------|-------------------|------|
| observer-data | PVC | observer-data-pvc | `/opt/platform/runtime/observer/data` | `OBSERVER_DATA_DIR` | [x] |
| observer-logs | PVC | observer-logs-pvc | `/opt/platform/runtime/observer/logs` | `OBSERVER_LOG_DIR` | [x] |
| observer-universe | PVC | observer-universe-pvc | `/opt/platform/runtime/observer/universe` | `OBSERVER_SNAPSHOT_DIR` | [x] |
| observer-config | **hostPath** | `/opt/platform/runtime/observer/config` (DirectoryOrCreate) | `/opt/platform/runtime/observer/config` | `OBSERVER_CONFIG_DIR` | [x] |
| postgres-data | PVC | observer-db-pvc | `/var/lib/postgresql/data` | N/A | [x] |

#### SealedSecret → Secret 검증 [CRITICAL]

```
SealedSecret 적용 결과:
  obs-db-sealed-secret.yaml    → Secret "obs-db-secret"    (ns: observer-prod)
  obs-kis-sealed-secret.yaml   → Secret "obs-kis-secret"   (ns: observer-prod)
  obs-kiwoom-sealed-secret.yaml→ Secret "obs-kiwoom-secret" (ns: observer-prod)

Deployment/StatefulSet 참조:
  observer.yaml:52-53  → secretRef: name: observer-secrets (optional: false)
  postgres.yaml:56-57  → secretRef: name: observer-secrets

결론: SealedSecret이 생성하는 Secret 이름과 워크로드가 참조하는 이름이 다름.
      "observer-secrets"는 별도 수동 생성 또는 다른 메커니즘으로 존재해야 함.
```

- [ ] SealedSecret controller가 sealed-secrets 네임스페이스에서 동작 중
- [ ] obs-db-secret 생성 확인
- [ ] obs-kis-secret 생성 확인
- [ ] obs-kiwoom-secret 생성 확인
- [ ] **CRITICAL**: `observer-secrets` Secret이 observer-prod에 존재
- [ ] `observer-secrets`에 필수 키 포함:
  - DB: `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB`, `DB_USER`, `DB_PASSWORD`
  - PG (마이그레이션 호환): `PGHOST`, `PGPORT`, `PGDATABASE`, `PGUSER`, `PGPASSWORD`
  - API: `KIS_APP_KEY`, `KIS_APP_SECRET`, `KIS_HTS_ID`
- [ ] `ghcr-secret` docker-registry Secret 존재 (imagePullSecrets 참조)

#### 환경 변수 존재 검증 (값 해석 없음)

**ConfigMap (observer-config) - 14개 키:**

| 키 | 정의됨 |
|----|--------|
| `LOG_LEVEL` | [x] |
| `LOG_FORMAT` | [x] |
| `SERVICE_PORT` | [x] |
| `DB_HOST` | [x] |
| `DB_PORT` | [x] |
| `DB_NAME` | [x] |
| `OBSERVER_LOG_DIR` | [x] |
| `OBSERVER_DATA_DIR` | [x] |
| `OBSERVER_CONFIG_DIR` | [x] |
| `OBSERVER_SYSTEM_LOG_DIR` | [x] |
| `OBSERVER_MAINTENANCE_LOG_DIR` | [x] |
| `OBSERVER_SNAPSHOT_DIR` | [x] |
| `KIS_TOKEN_CACHE_DIR` | [x] |
| `OBSERVER_STANDALONE` | [x] |
| `PYTHONUNBUFFERED` | [x] |

**Deployment env spec - 4개:**

| 키 | 소스 | 정의됨 |
|----|------|--------|
| `POD_NAME` | fieldRef: metadata.name | [x] |
| `POD_NAMESPACE` | fieldRef: metadata.namespace | [x] |
| `TZ` | 직접 값: "Asia/Seoul" | [x] |
| `PYTHONUNBUFFERED` | 직접 값: "1" | [x] |

#### securityContext 검증

**Observer Deployment:**

| 레벨 | 항목 | 값 | 존재 |
|------|------|------|------|
| Pod | fsGroup | 1000 | [x] |
| Container | runAsUser | 1000 | [x] |
| Container | runAsGroup | 1000 | [x] |
| Container | runAsNonRoot | true | [x] |
| Container | readOnlyRootFilesystem | true | [x] |
| Container | allowPrivilegeEscalation | false | [x] |
| Container | capabilities.drop | ALL | [x] |

**PostgreSQL StatefulSet:**

| 레벨 | 항목 | 값 | 존재 |
|------|------|------|------|
| Pod | fsGroup | 999 | [x] |
| Container | (없음) | - | 미설정 |

### 1-3. 수정 파일 목록

| 파일 | 수정 내용 |
|------|----------|
| `.gitignore` | 평문 Secret 파일 경로 명시 추가 |
| `infra/k8s/base/secrets/observer-prod-plain.yaml` | `git rm --cached`로 추적 해제 |
| `infra/k8s/base/secrets/obs-prod.yaml` | `git rm --cached`로 추적 해제 |
| `docs/PERSISTENCE_AND_HOSTPATH.md` | 경로 `/app/logs` → 현재 실제 경로로 수정 |

### 1-4. 수정 이유 (실행 계약 관점)

| 수정 대상 | 이유 |
|-----------|------|
| 평문 Secret .gitignore 등록 | KIS_APP_KEY, KIS_APP_SECRET, DB_PASSWORD가 평문으로 Git에 노출. 보안 계약 위반. 향후 커밋 방지를 위한 최소 조치 |
| kubeconfig .gitignore 등록 | K3s client certificate + private key가 Git에 노출. 클러스터 접근 권한 유출 위험 |
| PERSISTENCE_AND_HOSTPATH.md 경로 수정 | 문서의 경로(`/app/logs`)가 현재 Deployment의 실제 경로(`/opt/platform/runtime/observer/logs`)와 불일치. 이 문서를 참고하여 HostPath를 설정하면 잘못된 경로에 마운트됨 |

> **보안 조치 한계 (Phase 0 범위)**
>
> `.gitignore` 등록은 **향후 커밋 방지를 위한 최소 조치**이며, 완전한 보안 대응이 아님.
>
> - Git 히스토리에 이미 커밋된 평문 Secret/kubeconfig는 `.gitignore`로 제거되지 않음.
> - 완전 제거를 위해서는 `git filter-branch` 또는 BFG Repo-Cleaner가 필요하나, 이는 Git 히스토리 재작성을 수반하므로 Phase 1 변경 후보로 분류.
> - Phase 0에서는 현재 파일이 Git 추적 대상이 아님을 확인하고, 추가 커밋이 발생하지 않도록 `.gitignore`에 명시하는 것까지만 수행.

### 1-5. Phase 1 변경 후보

| 후보 | 설명 |
|------|------|
| SealedSecret 통합 | 3개 SealedSecret을 단일 `observer-secrets` SealedSecret으로 통합하거나, Deployment의 `secretRef`를 3개로 분리하여 이름 일치 |
| hostPath → PVC 전환 | `observer-config` 볼륨의 hostPath를 PVC 또는 ConfigMap 기반으로 전환 |
| 평문 Secret Git 이력 제거 | `git filter-branch` 또는 BFG Repo-Cleaner로 Git 히스토리에서 완전 제거 |
| RWO + replicas 명시화 | RWO PVC + 2 replicas 조합의 단일 노드 전제를 nodeSelector/taint로 명시 |
| Secret 생성 가이드 보완 | KUBECTL_AND_ARGOCD_SETUP.md에 KIS API 키 포함하도록 가이드 갱신 |

### 1-6. Phase 0 완료 판단

| 조건 | 상태 |
|------|------|
| kustomization.yaml의 모든 resource 참조가 실제 파일과 일치 | [ ] |
| observer-prod에 `observer-secrets` Secret이 모든 필수 키와 함께 존재 | [ ] |
| `ghcr-secret` docker-registry Secret 존재 | [ ] |
| 4개 PVC 모두 STATUS=Bound | [ ] |
| volumeMount 경로가 ConfigMap 환경 변수 값과 일치 | [x] 코드 분석 확인 완료 |
| 평문 Secret 파일 .gitignore 등록 완료 | [ ] |

---

## 2. server (K3s 노드)

### 2-1. Phase 0 확인 체크리스트

| 확인 항목 | 확인 방법 | 기대 상태 | 상태 |
|-----------|----------|----------|------|
| K3s 클러스터 정상 | `kubectl get nodes -o wide` | STATUS=Ready, K3s 버전 확인 | [ ] |
| local-path StorageClass 존재 | `kubectl get sc` | `local-path (default)` | [ ] |
| local-path-provisioner Pod 동작 | `kubectl get pods -n kube-system -l app=local-path-provisioner` | Running | [ ] |
| sealed-secrets controller 동작 | `kubectl get pods -n sealed-secrets` | Running | [ ] |
| PVC 실제 저장 위치 | `ls /var/lib/rancher/k3s/storage/` | PVC별 디렉토리 존재 | [ ] |
| hostPath config 경로 존재 | `ls -la /opt/platform/runtime/observer/config` | 디렉토리 존재 | [ ] |
| hostPath config 경로 권한 | `stat /opt/platform/runtime/observer/config` | 755 이하, owner 1000:1000 | [ ] |
| 노드 디스크 여유 | `df -h /var/lib/rancher/k3s/storage/` | 36Gi 이상 여유 | [ ] |
| observer-prod namespace | `kubectl get ns observer-prod` | Active | [ ] |

### 2-2. 수정 파일 목록

**수정 없음.** Phase 0에서 서버 설정 변경 금지. 서버 상태 확인 결과는 이 문서에 기록만 함.

### 2-3. 수정 이유

해당 없음.

### 2-4. Phase 1 변경 후보

| 후보 | 설명 |
|------|------|
| hostPath → 명시적 PV | `/opt/platform/runtime/observer/config`을 명시적 PersistentVolume으로 정의하여 관리 명확화 |
| HostPath PV 도입 | `/home/ubuntu/data/observer/` 기반 HostPath PV 구성 (PERSISTENCE_AND_HOSTPATH.md 참조) |
| nodeSelector 명시 | 단일 노드 전제를 nodeSelector/taint로 명시하여 멀티 노드 전환 시 안전장치 확보 |

### 2-5. Phase 0 완료 판단

| 조건 | 상태 |
|------|------|
| K3s 클러스터 Ready | [ ] |
| local-path-provisioner 정상 동작 | [ ] |
| sealed-secrets controller 정상 동작 | [ ] |
| PVC 실제 저장 경로 확인 및 디스크 여유 확보 | [ ] |
| hostPath config 디렉토리 존재 + 올바른 권한 | [ ] |

---

## 3. prj_obs (Observer App 레포)

### 3-1. Phase 0 확인 체크리스트

#### 경로 계약 검증 (paths.py 기본값 vs K8s 설정)

| 항목 | paths.py 기본값 | ConfigMap 값 | Deployment volumeMount | 일치 |
|------|----------------|-------------|----------------------|------|
| data | `/opt/platform/runtime/observer/data` | `OBSERVER_DATA_DIR` | mountPath 동일 | [x] |
| logs | `/opt/platform/runtime/observer/logs` | `OBSERVER_LOG_DIR` | mountPath 동일 | [x] |
| config | `/opt/platform/runtime/observer/config` | `OBSERVER_CONFIG_DIR` | mountPath 동일 | [x] |
| universe | `/opt/platform/runtime/observer/universe` | `OBSERVER_SNAPSHOT_DIR` | mountPath 동일 | [x] |
| system_log | `{log_dir}/system` | `OBSERVER_SYSTEM_LOG_DIR` | logs PVC 하위 | [x] |
| maintenance_log | `{log_dir}/maintenance` | `OBSERVER_MAINTENANCE_LOG_DIR` | logs PVC 하위 | [x] |
| token_cache | `{data_dir}/cache` | `KIS_TOKEN_CACHE_DIR` | data PVC 하위 | [x] |

**결론**: 3계층(App / ConfigMap / Deployment) 간 경로 계약 **일치 확인됨**.

#### DB 연결 계약 검증

| 항목 | App 기본값 (realtime_writer.py) | ConfigMap 값 | K8s Service | 일치 |
|------|-------------------------------|-------------|------------|------|
| host | `postgres` | `DB_HOST: postgres` | Service name: postgres | [x] |
| port | `5432` | `DB_PORT: 5432` | Service port: 5432 | [x] |

#### 런타임 호환성 검증

| 확인 항목 | 대상 | 결과 |
|-----------|------|------|
| Health endpoint | `api_server.py` GET /health | 존재 [x] |
| Readiness endpoint | `api_server.py` GET /ready | 존재 [x] |
| OBSERVER_STANDALONE 기본값 | `__init__.py` | "1" [x] |
| mkdir() + readOnlyRootFilesystem 호환 | `paths.py` 전체 | try/except로 graceful 처리 [x] |
| deployment_paths.py 위임 구조 | `deployment_paths.py` | paths.py에 위임, 독립 경로 없음 [x] |
| 필수 환경 변수 | `observer_runner.py` | KIS_APP_KEY, KIS_APP_SECRET 필수 [x] |

### 3-2. 수정 파일 목록

**수정 없음.** Phase 0에서 앱 코드 수정 금지. 암묵적 전제를 확인하고 이 문서에 기록만 함.

### 3-3. 수정 이유

해당 없음.

### 3-4. Phase 1 변경 후보

| 후보 | 설명 |
|------|------|
| paths.py mkdir() 제거 | mkdir() 호출을 "확인만, 생성 안 함" 패턴으로 변경. 로드맵 "앱: mkdir 금지" 준수 |
| 환경 변수 스키마 명시 | `.env.example` 또는 config 스키마 문서에 K8s 필수 환경 변수 목록 명시 |
| 미사용 함수 제거 | `deployment_paths.py`의 `runtime_socket_dir()`, `temp_dir()`이 mkdir 호출 → 사용되지 않으면 제거 |
| Execution Contract 테스트 | 5개 항목(경로, 환경 변수, 포트, 볼륨, 권한)을 pytest로 검증하는 테스트 추가 |

### 3-5. Phase 0 완료 판단

| 조건 | 상태 |
|------|------|
| paths.py 기본값 = K8s volumeMount 경로 | [x] 코드 분석 확인 완료 |
| paths.py 기본값 = ConfigMap 환경 변수 값 | [x] 코드 분석 확인 완료 |
| DB 연결 기본값 = K8s Service 이름 | [x] 코드 분석 확인 완료 |
| readOnlyRootFilesystem에서 mkdir() graceful 처리 | [x] 코드 분석 확인 완료 |
| 앱 필수 환경 변수 전체가 ConfigMap + Secret에 정의됨 | [x] 코드 분석 확인 완료 |

---

## Phase 0 검증 실행 주체

| 영역 | 검증 방식 | 실행 주체 | 비고 |
|------|----------|----------|------|
| deployment (GitOps) | YAML/코드 정적 분석 | 개발자 (로컬 코드 리뷰) | 클러스터 접근 불필요 |
| server (K3s) | `kubectl` 명령어 실행 | 운영자 (클러스터 접근 권한 보유자) | `PHASE_0_CLUSTER_STATUS_GUIDE.md` 절차 따름 |
| prj_obs (App) | Python 소스 정적 분석 | 개발자 (로컬 코드 리뷰) | 클러스터 접근 불필요 |

- **deployment / prj_obs 영역**: 본 보고서의 체크리스트 중 `[x]` 표시 항목은 코드 정적 분석으로 확인 완료. `[ ]` 표시 항목은 클러스터 실행 환경에서 확인 필요.
- **server 영역**: 모든 항목이 `[ ]`이며, 클러스터 접근 권한을 가진 운영자가 `PHASE_0_CLUSTER_STATUS_GUIDE.md`의 Step 0~9를 순서대로 실행하여 확인.
- **체크리스트 완성 시점**: server 영역 검증이 완료되면, 그 결과를 본 보고서의 `[ ]` 항목에 반영하여 Phase 0 완료 여부를 최종 판단.

---

## Phase 0 전체 결론

### 경로 계약: YES (안정)

3계층(App paths.py / ConfigMap / Deployment volumeMount) 간 경로 계약이 모두 일치.

### Secret 관리: 클러스터 확인 필요

`observer-secrets` Secret의 존재 여부와 키 완전성은 실제 클러스터에서 확인 필요.
SealedSecret 3개는 `observer-secrets`와 별개로 생성되므로, 수동 생성된 Secret이 반드시 존재해야 함.

### 보안: 조치 필요

평문 Secret과 kubeconfig가 Git에 커밋됨. .gitignore 등록 + git rm --cached로 최소 조치 수행.

### 문서 정합성: 수정 필요

PERSISTENCE_AND_HOSTPATH.md의 경로가 현재 구조와 불일치. 현행화 필요.

---

## Phase 0에서 확정된 불변 실행 계약

Phase 0 검증을 통해 아래 4개 계약이 **현재 일치함을 확인**했다. 이 계약은 Phase 1 이후 구조 변경 시에도 반드시 유지되어야 하며, 위반 시 시스템이 정상 동작하지 않는다.

| # | 계약 | 검증 결과 | 위반 시 영향 |
|---|------|----------|-------------|
| 1 | **경로 계약**: paths.py 기본값 = ConfigMap 환경 변수 = Deployment volumeMount 경로 (7개 항목 일치) | 일치 확인 (섹션 3-1) | Pod 내부에서 파일 읽기/쓰기 실패, 데이터 손실 |
| 2 | **DB 연결 계약**: App 기본값(`postgres:5432`) = ConfigMap(`DB_HOST`, `DB_PORT`) = K8s Service name/port | 일치 확인 (섹션 3-1) | DB 연결 실패, CrashLoopBackOff |
| 3 | **Secret 이름 계약**: Deployment/StatefulSet의 `secretRef: observer-secrets` + `imagePullSecrets: ghcr-secret`이 실제 존재하는 Secret과 일치 | 클러스터 확인 필요 | Pod 시작 불가 (optional: false) |
| 4 | **보안 컨텍스트 계약**: Observer는 `readOnlyRootFilesystem: true`, `runAsUser: 1000`, `fsGroup: 1000`으로 실행. 쓰기는 volumeMount 경로에서만 가능 | 일치 확인 (섹션 1-2) | 권한 오류, 파일 쓰기 실패 |

> **Phase 1 작업 시 준수 사항**: 위 4개 계약을 변경하는 경우, 반드시 3계층(App / ConfigMap / Deployment) 전체를 동시에 갱신하고, 본 보고서의 교차표를 재검증해야 한다.

---

**다음 단계**: `PHASE_0_CLUSTER_STATUS_GUIDE.md`의 kubectl 명령어로 클러스터 상태를 실제 확인한 후, 이 보고서의 체크리스트를 완성한다.
