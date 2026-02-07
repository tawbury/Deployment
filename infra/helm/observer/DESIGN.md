# Observer Helm Chart 설계 문서

**버전**: 1.0  
**작성일**: 2026-02-07  
**대상**: Observer Application Helm Chart  

---

## 1. 개요

이 문서는 Observer 애플리케이션의 Helm Chart 설계 원칙과 구조를 정의합니다.

### 1.1 설계 목표

- **ConfigMap을 Source of Truth로 확정**: 모든 비밀이 아닌 설정은 ConfigMap에서 관리
- **values.yaml → ConfigMap → Pod 단방향 흐름**: 설정 변경 시 추적 가능한 단일 경로
- **Probes와 ConfigMap의 의존 관계 명시**: ConfigMap 없이 Probes는 의미 없음

---

## 2. ConfigMap 책임 범위

### 2.1 포함 항목

| 카테고리 | 환경 변수 | 설명 |
|----------|-----------|------|
| **실행 환경** | `APP_ENV`, `LOG_LEVEL`, `LOG_FORMAT`, `TZ` | 애플리케이션 런타임 모드 |
| **서비스** | `SERVICE_PORT`, `OBSERVER_STANDALONE` | 서비스 설정 |
| **데이터베이스** | `DB_HOST`, `DB_PORT`, `DB_NAME` | 연결 정보 (비밀번호 제외) |
| **런타임 경로** | `OBSERVER_*_DIR`, `KIS_TOKEN_CACHE_DIR` | 파일 시스템 경로 |
| **Observer 설정** | `OBSERVER_MARKET`, `OBSERVER_MIN_PRICE` 등 | 수집기 파라미터 |

### 2.2 제외 항목 (Secret으로 위임)

| Secret 이름 | 포함 키 | 필수 여부 |
|------------|--------|----------|
| `obs-db-secret` | `DB_USER`, `DB_PASSWORD`, `POSTGRES_*` | **필수** |
| `obs-kis-secret` | `KIS_APP_KEY`, `KIS_APP_SECRET`, `KIS_HTS_ID` | **필수** |
| `obs-kiwoom-secret` | `KIWOOM_APP_KEY`, `KIWOOM_APP_SECRET` | 선택 |

---

## 3. Secret과의 경계

```
┌─────────────────────────────────────────────────────────────┐
│                    values.yaml (Source of Truth)            │
└─────────────────────────────────────────────────────────────┘
                              │
              ┌───────────────┴───────────────┐
              ▼                               ▼
┌─────────────────────────┐     ┌─────────────────────────┐
│       ConfigMap         │     │    SealedSecret         │
│  (Non-sensitive data)   │     │   (Sensitive data)      │
├─────────────────────────┤     ├─────────────────────────┤
│ • APP_ENV               │     │ • DB_USER               │
│ • LOG_LEVEL             │     │ • DB_PASSWORD           │
│ • DB_HOST               │     │ • KIS_APP_KEY           │
│ • DB_PORT               │     │ • KIS_APP_SECRET        │
│ • OBSERVER_*_DIR        │     │ • KIS_HTS_ID            │
│ • OBSERVER_MARKET       │     └─────────────────────────┘
└─────────────────────────┘
              │                               │
              └───────────────┬───────────────┘
                              ▼
                    ┌─────────────────┐
                    │   Pod (envFrom) │
                    └─────────────────┘
```

### 3.1 분리 원칙

1. **ConfigMap**: Git에 커밋 가능, 코드 리뷰 대상
2. **Secret**: SealedSecret으로 암호화, Git에는 암호화된 형태로만 저장
3. **혼합 금지**: 하나의 리소스에 민감/비민감 데이터 혼합 금지

---

## 4. Probes 설계 이유

### 4.1 의존 관계

```
ConfigMap 정의 완료
        │
        ▼
┌─────────────────────────────────────────┐
│ Pod 시작                                 │
│   ├─ 환경 변수 주입 (envFrom)           │
│   ├─ paths.py 초기화                    │
│   └─ validate_execution_contract()      │
└─────────────────────────────────────────┘
        │
        ▼
┌─────────────────────────────────────────┐
│ Startup Probe (/health)                 │
│   • ConfigMap 기반 설정 로딩 완료       │
│   • 마운트 포인트 존재 및 쓰기 가능     │
│   • 최대 150초 대기 (30 × 5s)           │
└─────────────────────────────────────────┘
        │
        ▼
┌─────────────────────────────────────────┐
│ Readiness Probe (/ready)                │
│   • DB 연결 완료                        │
│   • Symbol/Universe 초기화 완료         │
│   • 트래픽 수신 준비 완료               │
└─────────────────────────────────────────┘
        │
        ▼
┌─────────────────────────────────────────┐
│ Liveness Probe (/health)                │
│   • 메인 루프 생존 확인                 │
│   • 응답 없음 → Pod 재시작              │
└─────────────────────────────────────────┘
```

### 4.2 Probe 역할 정의

| Probe | 엔드포인트 | 역할 | 실패 시 동작 |
|-------|-----------|------|-------------|
| **Startup** | `/health` | 부트스트래핑 완료 대기 | 계속 재시도 (failureThreshold까지) |
| **Liveness** | `/health` | 메인 루프 생존 확인 | Pod 재시작 |
| **Readiness** | `/ready` | 트래픽 수신 준비 | Endpoints에서 제외 |

### 4.3 Probes 없이 ConfigMap만 있을 때의 문제

- 앱 Crash 감지 불가 → Zombie Pod
- 부트스트래핑 중 트래픽 수신 → 오류 응답
- 외부 의존성 장애 시 트래픽 계속 수신 → 연쇄 장애

---

## 5. 파일 구조

```
infra/helm/observer/
├── Chart.yaml
├── values.yaml              # Source of Truth
├── values-dev.yaml          # 개발 환경 override
├── values-prod.yaml         # 운영 환경 override
└── templates/
    ├── _helpers.tpl         # 템플릿 헬퍼 함수
    ├── configmap.yaml       # ConfigMap (비밀 제외 설정)
    ├── deployment.yaml      # Deployment + Probes
    ├── service.yaml         # Service
    ├── pvc.yaml             # PersistentVolumeClaim
    └── notes.txt            # 설치 후 안내
```

---

## 6. 사용법

### 6.1 개발 환경 배포

```bash
helm install observer ./infra/helm/observer \
  -f ./infra/helm/observer/values.yaml \
  -f ./infra/helm/observer/values-dev.yaml \
  -n observer
```

### 6.2 운영 환경 배포

```bash
helm install observer ./infra/helm/observer \
  -f ./infra/helm/observer/values.yaml \
  -f ./infra/helm/observer/values-prod.yaml \
  -n observer
```

### 6.3 설정 변경 후 재배포

```bash
helm upgrade observer ./infra/helm/observer \
  -f ./infra/helm/observer/values.yaml \
  -f ./infra/helm/observer/values-prod.yaml \
  -n observer
```

---

## 7. 체크리스트

### 7.1 배포 전 확인 사항

- [ ] `obs-db-secret` SealedSecret 적용됨
- [ ] `obs-kis-secret` SealedSecret 적용됨
- [ ] PVC (`observer-data-pvc`, `observer-logs-pvc`) 생성됨
- [ ] `ghcr-secret` (ImagePullSecret) 생성됨
- [ ] hostPath `/opt/platform/runtime/observer/config` 존재함

### 7.2 배포 후 확인 사항

- [ ] Pod STATUS = Running
- [ ] `kubectl logs` 에서 "Execution contract validated" 확인
- [ ] `curl <pod-ip>:8000/health` → 200 OK
- [ ] `curl <pod-ip>:8000/ready` → 200 OK

---

## 8. 문서 이력

| 버전 | 일자 | 변경 내용 |
|------|------|-----------|
| 1.0 | 2026-02-07 | 초안 작성 |
