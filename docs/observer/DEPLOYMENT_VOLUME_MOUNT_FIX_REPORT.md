# k3s 배포 환경 볼륨 마운트 미연결 문제 분석 및 수정 가이드

**작성일**: 2026-02-03  
**최종 검증**: 2026-02-03 (서버 oracle-obs-vm-01 SSH 점검 반영)  
**대상 서버**: oracle-obs-vm-01  
**런타임**: **k3s + ArgoCD** (Docker Compose 미사용)  
**목적**: JSONL 파일 및 로그 파일이 서버(호스트)에 보이지 않는 원인 분석 및 배포 레포 수정 가이드

---

## 1. 요약

| 항목 | 내용 |
|------|------|
| **증상** | JSONL 파일과 로그 파일이 서버 상에서 보이지 않음(또는 찾기 어려움) |
| **근본 원인** | `/app/data`가 **PVC에 마운트되지 않음** → JSONL은 파드 임시 파일시스템에만 존재 |
| **로그(.log)** | `/app/logs`는 PVC 마운트됨 → 서버 k3s 스토리지 경로에 존재 (접근 경로 비직관적) |
| **수정 담당** | **배포 레포(Deployment Repo)** — observer Deployment에 `observer-data-pvc` 추가 |
| **Observer 레포** | 코드 수정 불필요 (경로는 이미 표준화됨) |

---

## 2. 서버 실제 현황 (2026-02-03 점검)

### 2.1 환경

| 항목 | 값 |
|------|-----|
| **런타임** | k3s (local-path-provisioner, Traefik, ArgoCD) |
| **네임스페이스** | `observer-prod` |
| **Observer 파드** | 2개 (replicas: 2), 이미지: `ghcr.io/tawbury/observer:build-20260203-032529` |
| **Postgres** | 1개 (observer-db-pvc 마운트) |
| **배포 관리** | ArgoCD (kustomize) |

### 2.2 현재 Deployment 볼륨 마운트

```text
Mounts:
  /app/logs  ← observer-logs-pvc (5Gi, local-path) ✅ 마운트됨
```

**미마운트 경로**:
- `/app/data` — **PVC 없음** → JSONL이 파드 임시 파일시스템에만 존재
- `/app/config` — 컨테이너 이미지/ConfigMap 기반 (PVC 아님)
- `/app/secrets` — Secret/ConfigMap 기반 (PVC 아님)

### 2.3 PVC 현황

| PVC 이름 | 용량 | 바인딩 | 마운트 경로 |
|----------|------|--------|-------------|
| observer-db-pvc | 10Gi | Bound | postgres: `/var/lib/postgresql/data` |
| observer-logs-pvc | 5Gi | Bound | observer: `/app/logs` |
| **observer-data-pvc** | — | **없음** | — |

### 2.4 로그(.log) 파일 — 서버상 위치

로그는 **실제로 서버에 존재**합니다. k3s local-path PVC에 저장되며, 호스트 경로는:

```text
/var/lib/rancher/k3s/storage/pvc-3a60a238-a7b1-45b5-9d1d-cfd3a23701da_observer-prod_observer-logs-pvc/
├── scalp/    # 20260203_02.log, 20260203_03.log, 20260203_09.log 등
├── swing/    # 20260203.log
└── system/
```

**확인 방법** (SSH 후):
```bash
sudo ls -la /var/lib/rancher/k3s/storage/pvc-*/observer-prod_observer-logs-pvc/scalp/
```

`~/observer` 디렉터리는 **존재하지 않습니다.** 이전 Docker Compose 구조와 다름.

### 2.5 JSONL 파일 — 파드 내부에만 존재

| 경로 | 상태 |
|------|------|
| `/app/data/assets/scalp/20260203_09.jsonl` | 파드 내부에만 있음, **PVC 없음** |
| `/app/data/assets/swing/20260203.jsonl` | 파드 내부에만 있음, **PVC 없음** |

파드 재시작 시 **모두 삭제**됩니다. 서버 호스트에서는 접근 불가.

### 2.6 참고: 서버 내 보고서

서버 `~/CONTAINER_DATA_CHECK_REPORT.md`에 동일 결론이 기록되어 있음 (2026-02-03 작성).

---

## 3. 원인 분석

### 3.1 동작 원리

Observer 앱은 컨테이너 내부의 다음 경로에 파일을 씁니다:

- `/app/data` — JSONL 데이터 (scalp, swing, observer 이벤트) → **현재 PVC 미마운트**
- `/app/logs` — 로그 파일 (.log, system JSONL) → **observer-logs-pvc 마운트됨**
- `/app/config` — 설정 파일 (ConfigMap/이미지)
- `/app/secrets` — .env, KIS 토큰 캐시 (Secret)

### 3.2 기존 점검 결과 (참고)

`docs/deployment/SERVER_VOLUME_CHECK_20260202.md` — **Docker Compose** 환경 점검:

- docker inspect 시 Mounts 빈 배열
- docker-compose.server.yml에 볼륨 정의 있으나 적용 안 됨

**현재 oracle-obs-vm-01은 Docker Compose가 아닌 k3s**를 사용하므로, 해당 문서는 과거 구조 참고용.

---

## 4. Observer 앱이 사용하는 컨테이너 경로 (참조용)

배포 레포에서 **반드시** 아래 경로들을 영속 스토리지와 연결해야 합니다.

### 4.1 데이터 (JSONL)

| 용도 | 컨테이너 경로 | 파일 예시 |
|------|----------------|-----------|
| Track B (스켈프) | `/app/data/assets/scalp/` | `20260203_09.jsonl`, `20260203_10.jsonl` |
| Track A (스윙) | `/app/data/assets/swing/` | `20260203.jsonl` |
| 이벤트 버스 | `/app/data/` | `observer.jsonl` |
| 갭 로그 | `/app/logs/system/` | `gap_20260203.jsonl` |
| 오버플로우 로그 | `/app/logs/system/` | `overflow_20260203.jsonl` |

### 4.2 로그 (.log)

| 용도 | 컨테이너 경로 | 파일 예시 |
|------|----------------|-----------|
| 시스템 로그 | `/app/logs/` | `20260203_09.log`, `20260203_10.log` |
| 스켈프 로그 | `/app/logs/scalp/` | `20260203.log` |
| 스윙 로그 | `/app/logs/swing/` | `20260203.log` |
| 유지보수 로그 | `/app/logs/maintenance/` | — |

### 4.3 설정 및 시크릿

| 용도 | 컨테이너 경로 |
|------|----------------|
| 설정 | `/app/config` (scalp, swing, symbols, universe) |
| 시크릿 | `/app/secrets` (.env, .kis_cache) |

### 4.4 환경 변수 (Dockerfile 기준)

```
OBSERVER_DATA_DIR=/app/data
OBSERVER_LOG_DIR=/app/logs
OBSERVER_CONFIG_DIR=/app/config
KIS_TOKEN_CACHE_DIR=/app/secrets/.kis_cache
OBSERVER_ENV_FILE=/app/secrets/.env
```

---

## 5. 배포 레포 수정 가이드

### 5.1 핵심 수정 사항 (oracle-obs-vm-01 기준)

**이미 적용된 것**: `observer-logs-pvc` → `/app/logs` (로그 .log 파일 영속화)

**추가 필요**:
1. `observer-data-pvc` 생성
2. Deployment에 `/app/data` volumeMount 추가

`/app/config`, `/app/secrets`는 ConfigMap/Secret으로 주입되므로 PVC 필수는 아님. JSONL 영속화가 목표라면 **`/app/data` 마운트만 추가**하면 됨.

### 5.2 k3s 환경 — observer-data-pvc 추가

#### 5.2.1 PVC 정의 (신규 추가)

`k8s/base/pvc/observer-data-pvc.yaml` (또는 기존 pvc 디렉터리):

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: observer-data-pvc
  namespace: observer-prod
  labels:
    app: observer
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 20Gi
  storageClassName: local-path   # k3s 기본
```

**참고**: observer가 2레플리카인 경우 `ReadWriteOnce`는 단일 노드에서만 마운트 가능. 현재 oracle-obs-vm-01은 단일 노드(obs-prod-arm)이므로 두 파드 모두 동일 PVC를 마운트 가능. 슬롯별로 scalp/swing 파일을 나누어 쓰므로 단일 PVC 공유로 무방.

#### 5.2.2 Deployment 수정 (volumeMounts 추가)

**현재**:
```yaml
volumeMounts:
  - name: observer-logs
    mountPath: /app/logs
volumes:
  - name: observer-logs
    persistentVolumeClaim:
      claimName: observer-logs-pvc
```

**수정 후**:
```yaml
volumeMounts:
  - name: observer-logs
    mountPath: /app/logs
  - name: observer-data
    mountPath: /app/data
volumes:
  - name: observer-logs
    persistentVolumeClaim:
      claimName: observer-logs-pvc
  - name: observer-data
    persistentVolumeClaim:
      claimName: observer-data-pvc
```

#### 5.2.3 hostPath 대안 (사용자 친화적 경로)

`~/observer/data`에서 직접 확인하고 싶다면:

```yaml
volumes:
  - name: observer-data
    hostPath:
      path: /home/ubuntu/observer/data
      type: DirectoryOrCreate
```

배포 전 `mkdir -p /home/ubuntu/observer/data && chown 999:999 /home/ubuntu/observer/data` 필요.

### 5.4 Docker Compose 환경 (참고 — 현재 oracle-obs-vm-01 미사용)

과거 Docker Compose 배포 시:

```yaml
volumes:
  - ../observer/data:/app/data
  - ../observer/logs:/app/logs
  - ../observer/config:/app/config
  - ../observer/secrets:/app/secrets
```

볼륨 변경 후 `docker compose up -d --force-recreate observer` 필요.

---

## 6. 검증 방법

### 6.1 k3s — 마운트 확인

```bash
# SSH 후
sudo kubectl describe deployment observer -n observer-prod | grep -A 15 "Mounts:"
```

`/app/data`가 목록에 있어야 함.

### 6.2 k3s — JSONL 서버 확인 (수정 적용 후)

```bash
# PVC 경로 확인
sudo kubectl get pv | grep observer-data
sudo kubectl get pv <pv-name> -o jsonpath='{.spec.local.path}'

# 해당 경로에서 JSONL 확인 (예: local-path)
sudo ls -la /var/lib/rancher/k3s/storage/pvc-*_observer-prod_observer-data-pvc/assets/scalp/
```

### 6.3 로그(.log) 서버 경로 (이미 적용됨)

```bash
sudo ls -la /var/lib/rancher/k3s/storage/pvc-3a60a238-a7b1-45b5-9d1d-cfd3a23701da_observer-prod_observer-logs-pvc/scalp/
```

### 6.4 권한 (hostPath 사용 시)

컨테이너 사용자: `uid=999(observer)`, `gid=999(observer)`

```bash
sudo chown -R 999:999 /home/ubuntu/observer/data
```

---

## 7. Observer 레포(로컬) 수정 필요 여부

| 항목 | 상태 | 비고 |
|------|------|------|
| 경로 정의 | ✅ 수정 불필요 | `paths.py`, 환경 변수 일관됨 |
| Dockerfile | ✅ 수정 불필요 | `/app/data`, `/app/logs` 등 이미 정의 |
| JSONL/로그 경로 | ✅ 수정 불필요 | `data/assets/scalp`, `data/assets/swing`, `logs/system` 표준화됨 |

**결론**: Observer 앱 레포에서는 **코드 변경이 필요하지 않습니다.**  
볼륨 마운트 미적용은 **배포 레포의 k8s manifests 또는 docker-compose 설정** 문제입니다.

---

## 8. 체크리스트 (배포 레포용)

배포 레포 수정 시:

- [ ] `observer-data-pvc` PVC 리소스 추가 (storageClassName: local-path)
- [ ] Deployment에 `observer-data` volume 및 `/app/data` volumeMount 추가
- [ ] kustomization.yaml에 새 PVC 리소스 포함
- [ ] ArgoCD sync 또는 `kubectl apply` 후 PVC `Bound` 확인
- [ ] `sudo kubectl describe deployment observer -n observer-prod`로 Mounts 검증
- [ ] 장중 1시간 경과 후 `sudo ls`로 JSONL 파일 서버 존재 확인

---

## 9. 참고 문서

- **서버**: `~/CONTAINER_DATA_CHECK_REPORT.md` (oracle-obs-vm-01) — 2026-02-03 점검 결과
- `docs/deployment/SERVER_VOLUME_CHECK_20260202.md` — 이전 Docker Compose 점검 (과거 구조)
- `docs/deployment/SCALP_DATA_ISSUE_ANALYSIS_20260202.md` — 스켈프 데이터 부족 원인 분석
- `docs/dev/deployment/k8s_sub_architecture.md` — k3s PVC 구조
- `src/observer/paths.py` — Observer 경로 정의

---

**작성**: 2026-02-03  
**서버 점검 반영**: 2026-02-03  
**대상**: 배포 레포 담당자
