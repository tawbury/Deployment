# Kubernetes & Helm 기반 실행 계약 리팩토링 전체 로드맵

**문서 버전**: 1.0
**작성일**: 2026-02-05
**대상 시스템**: Observer (KIS 실시간 시세 수집 시스템)
**배포 환경**: OCI ARM K3s Cluster

---

## 1. 로드맵의 목적과 철학

### 1.1 왜 지금 리팩토링이 필요한가

현재 Observer 시스템의 상태:

| 실행 환경 | 상태 | 문제점 |
|----------|------|--------|
| Local | 정상 | - |
| Docker | 부분 동작 | 경로 매핑 불일치, 환경 변수 누락 |
| K8s | 불안정 | 볼륨 마운트 오류, Secret 수동 관리, 재현성 부족 |

**핵심 원인**: 실행 환경 간 "계약(Contract)"이 명시적으로 정의되지 않았다.

- 앱 코드(`prj_obs`)는 `/opt/platform/runtime/observer/*` 경로를 기대한다
- Dockerfile은 해당 경로를 환경 변수로 정의한다
- K8s Deployment는 해당 경로를 볼륨으로 마운트한다
- **이 세 계층의 "경로 계약"이 암묵적이며, 통합 검증 절차가 없다**

### 1.2 Helm/K8s 고도화의 목적

| 목적 | 설명 |
|------|------|
| 실행 계약 고정 | 앱이 기대하는 경로, 포트, 환경 변수를 Helm values.yaml에 명시적으로 선언 |
| 재현 가능한 배포 | 동일한 values.yaml + 동일한 이미지 = 동일한 결과 |
| 계층별 책임 분리 | 앱 레포는 "무엇을", Deploy 레포는 "어디서/어떻게"를 담당 |
| 롤백 가능성 확보 | 이미지 태그 변경만으로 이전 상태 복원 가능 |

### 1.3 핵심 관점

**"K8s는 단순화 도구가 아니라 복잡성 계층화 도구"**

K8s가 제공하는 것:
- 복잡성의 제거가 아닌, **복잡성의 분리와 명명**
- 각 리소스(Deployment, Service, PVC, Secret)는 단일 책임을 가진다
- 문제 발생 시 "어느 계층의 문제인지" 식별 가능

K8s가 제공하지 않는 것:
- 자동으로 작동하는 마법
- 잘못된 설계의 자동 수정
- "로컬에서 작동하면 서버에서도 작동한다"는 보장

**결론**: K8s/Helm 도입은 "설정의 명시화"와 "계층 간 계약 정의"를 강제하는 것이 목적이다. 복잡성이 증가하는 것이 아니라, **암묵적 복잡성이 명시적으로 드러나는 것**이다.

---

## 2. 전체 Phase 구조 (High-level)

```
Phase 0: 기반 안정화 (Foundation Stabilization)
    │
    ▼
Phase 1: 실행 계약 정의 (Execution Contract Definition)
    │
    ▼
Phase 2: Helm Chart 표준화 (Helm Chart Standardization)
    │
    ▼
Phase 3: GitOps 파이프라인 고도화 (GitOps Pipeline Enhancement)
    │
    ▼
Phase 4: 운영 성숙도 확보 (Operational Maturity)
```

### Phase 0: 기반 안정화

| 항목 | 내용 |
|------|------|
| **목적** | **Observer 단독** PVC 기반 24시간 안정 운영 확보 |
| **해결하려는 문제** | PVC Bound 상태 확보, SealedSecret 적용 완료, 필수 환경 변수 누락 제거 |
| **원칙적 금지 사항** | 앱 코드 변경, Dockerfile 변경, 경로 구조 변경, Helm 템플릿 작성 |
| **예외 허용** | 긴급 보안 패치, 데이터 손실 방지를 위한 조치 |
| **다음 Phase 진입 조건** | Pod Running 24시간+ (RESTARTS=0) / Pod 재시작 후 데이터 보존 / `/health` 200 OK / JSONL 생성 확인 |

**Phase 0 범위 명확화**:
- 수정 가능: K8s 리소스(PVC, SealedSecret, ConfigMap)
- 수정 금지: 앱 코드, Dockerfile, 경로 구조, 실행 방식
- 목표: “현재 구조 그대로” 안정화 여부 검증

### Phase 1: 실행 계약 정의

| 항목 | 내용 |
|------|------|
| **목적** | Execution Contract 5개 항목 명시 + Local 검증 자동화 |
| **해결하려는 문제** | 계층 간 불일치 발생 시 수정 대상 파일을 즉시 특정 불가 |
| **허용 변경 범위** | 앱 코드(경로 해석), Dockerfile(서버 기준 경로 보장), 문서 |
| **금지 사항** | Helm 템플릿 작성, CI/CD 자동화 도입, K8s 리소스 구조 변경 |
| **자동화 범위** | **Local pytest 검증만 자동화** |
| **다음 Phase 진입 조건** | Execution Contract 5개 항목 문서화 + 계약 위반 시 실패하는 Local 테스트 존재 |

**명시적 제한**:
- Docker/K8s 자동 검증 스크립트 → Phase 3 이후
- Helm 기반 배포 → Phase 2에서 최초 도입

### Phase 2: Helm Chart 표준화

| 항목 | 내용 |
|------|------|
| **목적** | Kustomize 직접 YAML에서 Helm Chart 기반으로 전환 |
| **해결하려는 문제** | 환경별 설정 산재, 값 중복, 롤백 복잡성 |
| **절대 하지 말아야 할 것** | 기존 Kustomize 완전 삭제, 한 번에 전체 전환 |
| **다음 Phase 진입 조건** | Helm으로 staging 배포 성공 / values-{env}.yaml 분리 / helm diff 예측 가능 |

### Phase 3: GitOps 파이프라인 고도화

| 항목 | 내용 |
|------|------|
| **목적** | ArgoCD를 통한 완전 자동화된 배포 사이클 구축 |
| **해결하려는 문제** | 수동 배포 개입, 배포 이력 추적 어려움 |
| **절대 하지 말아야 할 것** | kubectl 직접 적용, 이미지 태그 수동 변경 |
| **다음 Phase 진입 조건** | Git push만으로 배포 완료 / Sync 상태 자동 알림 / Git revert로 롤백 가능 |

### Phase 4: 운영 성숙도 확보

| 항목 | 내용 |
|------|------|
| **목적** | 모니터링, 알림, 백업/복구 자동화 |
| **해결하려는 문제** | 장애 감지 지연, 수동 개입 필요 상황 |
| **절대 하지 말아야 할 것** | 알림 없는 운영, 백업 없는 데이터 관리 |
| **다음 Phase 진입 조건** | Prometheus 메트릭 정상 / Critical 알림 10분 내 감지 / 일일 백업 자동 실행 |

---

## 3. 실행 환경 3단계 모델

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│     Local       │────▶│     Docker      │────▶│   Server(K8s)   │
│  (개발 환경)     │     │  (컨테이너화)    │     │  (프로덕션)      │
└─────────────────┘     └─────────────────┘     └─────────────────┘
        │                       │                       │
   앱 로직 검증            컨테이너 계약 검증        인프라 계약 검증
```

### 3.1 Local 단계

**검증 대상**: 앱 비즈니스 로직

| 검증 항목 | 방법 | 실패 의미 |
|----------|------|----------|
| 앱 비즈니스 로직 | pytest, 로컬 실행 | 코드 버그 |
| 환경 변수 로딩 | .env 파일 테스트 | 설정 로직 오류 |
| 경로 해석 로직 | paths.py 단위 테스트 | 경로 결정 로직 오류 |
| API 엔드포인트 | curl localhost:8000/health | 서버 시작 실패 |

**실패 시 조치**: 앱 코드 수정 (prj_obs 레포)

**다음 단계 진입 조건**:
- [ ] pytest 전체 통과
- [ ] `python -m observer` 로컬 실행 성공
- [ ] /health 엔드포인트 200 OK

### 3.2 Docker 단계

**검증 대상**: 컨테이너 계약 (Dockerfile, 환경 변수, 경로)

| 검증 항목 | 방법 | 실패 의미 |
|----------|------|----------|
| Dockerfile 빌드 | `docker build` | 빌드 설정 오류 |
| 컨테이너 내 경로 | `docker exec ls` | 경로 매핑 오류 |
| 환경 변수 주입 | `docker exec env` | ENV 설정 오류 |
| 비루트 사용자 권한 | 파일 생성 테스트 | 권한 설정 오류 |
| 볼륨 마운트 | `-v` 옵션 마운트 | 마운트 경로 불일치 |

**실패 시 조치**: Dockerfile 수정, 환경 변수 스키마 검토

**다음 단계 진입 조건**:
- [ ] `docker build` 성공
- [ ] `docker run` 컨테이너 정상 시작
- [ ] 컨테이너 내부 경로 존재 확인
- [ ] 볼륨 마운트 후 파일 쓰기 성공
- [ ] /health 엔드포인트 200 OK

### 3.3 Server(K8s) 단계

**검증 대상**: 인프라 계약 (PVC, Secret, Service, Ingress)

| 검증 항목 | 방법 | 실패 의미 |
|----------|------|----------|
| K8s 리소스 적용 | `kubectl apply` | YAML 문법/스키마 오류 |
| PVC Binding | `kubectl get pvc` | 스토리지 프로비저닝 오류 |
| Secret 복호화 | SealedSecret 상태 | Secret 관리 오류 |
| Pod 스케줄링 | `kubectl get pods` | 리소스/노드 문제 |
| 서비스 연결 | `kubectl port-forward` | 네트워크 설정 오류 |
| 데이터 영속성 | Pod 재시작 후 확인 | 볼륨 마운트 오류 |

**실패 시 조치**: K8s manifests 수정 (deployment 레포)

**운영 진입 조건**:
- [ ] 모든 PVC STATUS = Bound
- [ ] 모든 Pod STATUS = Running, READY = 1/1
- [ ] Pod 재시작 후 데이터 보존 확인
- [ ] 24시간 무중단 운영 확인

---

## 4. 이미지 & 배포 흐름 개요

### 4.1 전체 흐름도

```
[prj_obs 레포]                         [deployment 레포]
     │                                        │
     │ 1. 코드 변경                             │
     │ 2. 로컬 테스트                           │
     │ 3. Git push                            │
     ▼                                        │
[GitHub Actions]                              │
     │                                        │
     │ 4. docker build (ARM64)                │
     │ 5. docker push to GHCR                 │
     ▼                                        │
[GHCR]                                        │
  ghcr.io/tawbury/observer:build-YYYYMMDD-HHMMSS
     │                                        │
     │                           6. kustomization.yaml 이미지 태그 업데이트
     │                           7. Git push (deployment 레포)
     │                                        ▼
     │                                  [ArgoCD]
     │                                        │
     │                           8. Sync 감지 → kubectl apply
     │                                        ▼
     └────────────────────────────────  [K3s Cluster]
                    9. 이미지 Pull
```

### 4.2 타임스탬프 기반 이미지 태그의 역할

| 태그 형식 | 예시 | 용도 |
|----------|------|------|
| `build-YYYYMMDD-HHMMSS` | `build-20260204-220645` | 프로덕션/스테이징 배포 |
| `sha-{commit}` | `sha-3523d81` | 디버깅, 특정 커밋 추적 |
| `latest` | **사용 금지** | 재현성 없음 |

**타임스탬프 태그의 장점**:
1. 불변성 보장 (한 번 푸시된 태그는 변경 불가)
2. 배포 시점 명확 (태그 자체가 빌드 시간 정보)
3. 롤백 용이 (이전 태그로 교체만 하면 됨)
4. 디버깅 편의 (언제 빌드된 이미지인지 즉시 파악)

### 4.3 Helm/ArgoCD가 이미지를 소비하는 방식

**현재 (Kustomize 기반)**:
```yaml
# infra/k8s/overlays/production/kustomization.yaml
images:
  - name: ghcr.io/tawbury/observer
    newTag: build-20260204-220645
```

**목표 (Helm 기반)**:
```yaml
# infra/helm/observer/values-production.yaml
image:
  repository: ghcr.io/tawbury/observer
  tag: build-20260204-220645
```

### 4.4 재현 가능한 배포/롤백

**재현 가능한 배포의 조건**:
```
동일한 이미지 태그 + 동일한 values.yaml = 동일한 결과
```

**롤백 절차**:
1. Git에서 이전 커밋 확인
2. 이전 이미지 태그 확인
3. `git revert` 또는 이미지 태그 수동 변경
4. Git push
5. ArgoCD 자동 Sync
6. 롤백 완료

---

## 5. 레포지토리 책임 분리 원칙

### 5.1 책임 매트릭스

| 영역 | App Repo (prj_obs) | Helm Chart | GitOps Repo | Server Node |
|------|:------------------:|:----------:|:-----------:|:-----------:|
| 소스 코드 | O | - | - | - |
| Dockerfile | O | - | - | - |
| 환경 변수 스키마 | O | - | - | - |
| 환경 변수 값 | - | O | - | - |
| K8s 리소스 정의 | - | O | - | - |
| 이미지 태그 선택 | - | - | O | - |
| 배포 실행 | - | - | O | - |
| PVC 프로비저닝 | - | - | - | O |
| 네트워크 구성 | - | - | - | O |

### 5.2 App Repository (prj_obs)

**소유하는 것**:
- 애플리케이션 소스 코드 (`src/`)
- Dockerfile (`docker/Dockerfile`)
- 환경 변수 스키마 (`.env.example`)
- 경로 해석 로직 (`paths.py`)
- 테스트 코드 (`tests/`)

**소유하지 않는 것**:

| 금지 항목 | 이유 |
|----------|------|
| K8s manifests | 배포 영역의 책임 |
| 환경 변수 실제 값 | 보안 위험, 환경별 분기 필요 |
| 서버 IP/도메인 | 인프라 종속성 생성 |
| PVC 정의 | 스토리지 관리는 배포 영역 |

### 5.3 Helm Chart (infra/helm/)

**소유하는 것**:
- 템플릿 정의 (`templates/`)
- 기본값 정의 (`values.yaml`)
- 환경별 값 오버라이드 (`values-{env}.yaml`)

**소유하지 않는 것**:

| 금지 항목 | 이유 |
|----------|------|
| 애플리케이션 코드 | App 레포 책임 |
| 빌드 로직 | App 레포 책임 |
| 실제 Secret 값 | SealedSecrets로 관리 |

### 5.4 GitOps Repository (infra/k8s/, ArgoCD)

**소유하는 것**:
- 환경별 오버레이 (`overlays/`)
- 이미지 태그 선택 (kustomization.yaml)
- ArgoCD Application 정의
- SealedSecrets

**소유하지 않는 것**:

| 금지 항목 | 이유 |
|----------|------|
| 애플리케이션 코드 | App 레포 책임 |
| 평문 Secret | 보안 위험 |

### 5.5 Server Node

**소유하는 것**:
- K3s 클러스터 운영
- 노드 리소스 관리
- 스토리지 프로비저닝 (local-path)
- SealedSecrets 컨트롤러

**소유하지 않는 것**:

| 금지 항목 | 이유 |
|----------|------|
| 애플리케이션 설정 | GitOps로 관리 |
| 수동 kubectl 적용 | 재현성 상실 |

---

## 6. 디버깅과 판단 기준

### 6.1 문제 발생 시 원인 판별 순서

```
                    문제 발생
                        │
                        ▼
┌─────────────────────────────────────────────────────────────┐
│ Step 1: 로컬에서 재현되는가?                                 │
│         python -m observer (로컬 실행)                      │
├─────────────────────────────────────────────────────────────┤
│ Yes → 앱 문제 (prj_obs 수정)                                │
│ No  → Step 2로                                              │
└─────────────────────────────────────────────────────────────┘
                        │ No
                        ▼
┌─────────────────────────────────────────────────────────────┐
│ Step 2: Docker에서 재현되는가?                               │
│         docker run -e ... -v ... 실행                       │
├─────────────────────────────────────────────────────────────┤
│ Yes → 컨테이너 문제 (Dockerfile, 환경 변수, 경로)            │
│ No  → Step 3으로                                            │
└─────────────────────────────────────────────────────────────┘
                        │ No
                        ▼
┌─────────────────────────────────────────────────────────────┐
│ Step 3: Helm template 렌더링 결과가 예상과 일치하는가?       │
│         helm template . --debug                             │
├─────────────────────────────────────────────────────────────┤
│ No  → Helm 문제 (templates, values.yaml)                    │
│ Yes → Step 4로                                              │
└─────────────────────────────────────────────────────────────┘
                        │ Yes
                        ▼
┌─────────────────────────────────────────────────────────────┐
│ Step 4: K8s/인프라 문제                                      │
│         kubectl describe pod / kubectl logs / kubectl events │
├─────────────────────────────────────────────────────────────┤
│ - PVC Pending → StorageClass, 노드 스토리지                  │
│ - ImagePullBackOff → GHCR 인증, 이미지 태그                  │
│ - CrashLoopBackOff → 컨테이너 시작 실패 (로그 확인)          │
│ - 권한 오류 → fsGroup, runAsUser 설정                        │
└─────────────────────────────────────────────────────────────┘
```

### 6.2 계층별 디버깅 체크리스트

#### 앱 문제 판별

| 확인 항목 | 명령어/방법 | 정상 결과 |
|----------|-----------|----------|
| 코드 문법 | `python -m py_compile src/observer/__main__.py` | 오류 없음 |
| 의존성 | `pip install -r requirements.txt` | 설치 성공 |
| 단위 테스트 | `pytest tests/` | 전체 통과 |
| 로컬 실행 | `python -m observer` | 서버 시작 |
| 헬스체크 | `curl localhost:8000/health` | 200 OK |

#### 컨테이너 문제 판별

| 확인 항목 | 명령어/방법 | 정상 결과 |
|----------|-----------|----------|
| 이미지 빌드 | `docker build -f docker/Dockerfile .` | 빌드 성공 |
| 컨테이너 시작 | `docker run --rm -it <image> /bin/bash` | 쉘 진입 |
| 환경 변수 | `docker exec <c> env \| grep OBSERVER` | 모든 변수 존재 |
| 경로 존재 | `docker exec <c> ls -la /opt/platform/runtime/observer/` | 디렉토리 존재 |
| 쓰기 권한 | `docker exec <c> touch /opt/.../data/test` | 파일 생성 성공 |
| 사용자 확인 | `docker exec <c> id` | uid=1000(observer) |

#### K8s/인프라 문제 판별

| 확인 항목 | 명령어/방법 | 정상 결과 |
|----------|-----------|----------|
| Pod 상태 | `kubectl get pods -n observer-prod` | Running, Ready 1/1 |
| Pod 이벤트 | `kubectl describe pod <pod>` | 오류 이벤트 없음 |
| 컨테이너 로그 | `kubectl logs <pod>` | 앱 로그 정상 |
| PVC 상태 | `kubectl get pvc` | Bound |
| Secret 상태 | `kubectl get secrets` | 존재 |
| Service 상태 | `kubectl get svc` | 포트 매핑 정상 |

---

## 7. 로드맵 이후 작업 흐름

### 7.1 Phase 세부 분할 방법

각 Phase는 다음 구조로 세부 Task 문서로 분할한다:

```
Phase N/
├── PHASE_N_OVERVIEW.md          # Phase 전체 개요, 목표, 완료 조건
├── TASK_N_1_<name>.md           # 개별 Task 1
├── TASK_N_2_<name>.md           # 개별 Task 2
└── TASK_N_CHECKLIST.md          # Phase 완료 체크리스트
```

**Task 문서 표준 구조**:
1. 목적 (Objective)
2. 선행 조건 (Prerequisites)
3. 대상 파일 (Target Files)
4. 실행 단계 (Action Steps)
5. 검증 (Verification)
6. 롤백 계획 (Rollback Plan)
7. 트러블슈팅 (Troubleshooting)
8. 완료 기준 (Success Criteria)

### 7.2 반복 구조

```
┌────────────────┐
│   1. 문서 작성  │
│   (Task 정의)  │
└───────┬────────┘
        │
        ▼
┌────────────────┐
│   2. 실행      │
│   (Task 수행)  │
└───────┬────────┘
        │
        ▼
┌────────────────┐
│   3. 검증      │◀─────┐
│   (체크리스트)  │       │
└───────┬────────┘       │
        │                │
        ▼                │
┌────────────────┐       │
│ 4. 완료 여부?  │───No──┘
└───────┬────────┘
        │ Yes
        ▼
┌────────────────┐
│ 5. 다음 Phase  │
└────────────────┘
```

**규칙**:
1. Task 실행 전 반드시 Task 문서를 작성한다
2. 검증 체크리스트의 모든 항목이 통과해야 완료로 간주한다
3. 실패 시 문서에 트러블슈팅 내용을 추가한다
4. Phase 완료 시 다음 Phase 문서를 작성한 후에만 진행한다

### 7.3 현재 상태 → Phase 0 진입 조건

현재 `git status` 기준:

| 파일 | 상태 | 조치 |
|------|------|------|
| `kustomization.yaml` | Modified | PVC 활성화 완료 확인 |
| `observer-sealed-secrets.yaml` | Deleted | 3개 분리된 SealedSecret으로 대체 |
| `infra/helm/` | New | Helm Chart 준비 중 (Phase 2) |
| `obs-*-sealed-secret.yaml` | New | 3개 분리된 SealedSecret 적용 필요 |

**Phase 0 시작 전 확인**:
- [ ] 현재 변경 사항 커밋/푸시
- [ ] ArgoCD Sync 완료
- [ ] Pod Running 상태 확인
- [ ] PVC Bound 상태 확인
- [ ] Pod 재시작 후 파일 보존 테스트

---

## 부록: 핵심 파일 경로

| 파일 | 역할 |
|------|------|
| `prj_obs/src/observer/paths.py` | 앱 경로 해석 로직 (경로 계약의 앱 측) |
| `prj_obs/docker/Dockerfile` | 컨테이너 이미지 정의 (컨테이너 계약) |
| `deployment/infra/k8s/base/deployments/observer.yaml` | K8s Deployment (인프라 계약) |
| `deployment/infra/k8s/base/configmaps/observer-config.yaml` | 환경 변수 정의 |
| `deployment/infra/helm/observer/values.yaml` | Helm 기본값 (Phase 2) |

---

## 부록 B: Phase 0~1 수정 지침 (최종 확정)

### B.1 핵심 결정 문장 (필수 반영)

1. **Dockerfile은 서버(K8s) 컨테이너 실행을 기준으로 작성하며, 로컬 Docker 실행은 bind mount로 해결한다**

2. **환경 변수의 최종 권한은 ConfigMap/Secret이 가지며, Dockerfile ENV는 기본값/폴백 용도다**

3. **Phase 1에서 자동화하는 것은 Local pytest 검증뿐이며, Docker/K8s 자동화는 Phase 3 이후 영역이다**

4. **앱 코드는 절대 mkdir()를 호출하지 않으며, 경로 해석만 담당한다**

5. **QTS와 Observer는 Execution Contract 스펙을 공유하되, 각자 독립된 구현과 PVC를 유지한다**

6. **Phase 0~1 금지 사항은 원칙적 기준이며, 긴급 보안 패치와 데이터 손실 방지는 예외로 허용한다**

7. **3단계 검증에서 실패한 계층만 수정하며, 여러 계층을 동시에 수정하면 원인 파악이 불가능하다**

---

### B.2 Execution Contract 5개 항목 (Phase 1 문서화 대상)

| 계약 항목 | App Repo | Dockerfile | ConfigMap | Deployment | 최종 권한 | 검증 방법 |
|----------|----------|------------|-----------|------------|----------|----------|
| **1. 경로** | paths.py (해석) | ENV (기본값) | OBSERVER_RUNTIME_ROOT (운영값) | volumeMounts | **ConfigMap** | 3단계 검증 |
| **2. 환경 변수** | .env.example (스키마) | ENV (기본값) | ConfigMap data (운영값) | envFrom | **ConfigMap/Secret** | `docker exec env` |
| **3. 포트** | uvicorn 설정 | EXPOSE (문서용) | SERVICE_PORT | containerPort | **앱 코드** | `curl :8000/health` |
| **4. 볼륨** | - | 서버 기준 경로 존재 전제 | - | volumes + volumeMounts | **Deployment** | `kubectl get pvc` |
| **5. 권한** | - | USER 1000 | - | securityContext | **Deployment** | `docker exec id` |

※ 보충 설명 (중요)
- Dockerfile의 디렉토리 생성(RUN mkdir)은 **서버(K8s) 실행 기준을 만족시키기 위한 구현**
- 해당 Dockerfile 수정은 **Phase 1에서만 허용**
- Phase 0에서는 Dockerfile 변경 없이, 기존 구조의 안정성만 검증한다


**환경 변수 우선순위**:
1. ConfigMap/Secret (K8s 운영) - **최종 권한**
2. `docker run -e` (로컬 개발)
3. Dockerfile ENV (기본값/폴백)

---

### B.3 디렉토리 생성 책임 (수정)

**변경 전**:
```
- 앱: mkdir 금지
- Dockerfile: RUN mkdir -p /runtime/observer/{...}
- K8s: PVC 마운트 시 자동 생성
```

**변경 후**:
```
- 앱: mkdir 금지 (경로 해석만 담당, 디렉토리 생성 시도하지 않음)
- Dockerfile: 서버(K8s) 기준 경로만 보장
  RUN mkdir -p /opt/platform/runtime/observer/{data,logs,config,universe}
- docker run (로컬): bind mount로 ./runtime/observer 매핑 (개발자 책임)
- K8s: PVC 마운트 시 자동 생성 (인프라 책임)
```

---

### B.4 3단계 검증 자동화 범위 (수정)

**Phase 1에서 자동화**:
- Local: pytest 기반 경로 해석 테스트 자동화

**Phase 3 이후 자동화**:
- Docker: 컨테이너 빌드/실행 검증 스크립트
- K8s: manifest 적용/검증 CI/CD 파이프라인

**Phase 1 완료 기준**:
- [ ] Local pytest 자동화 완료
- [ ] Docker/K8s는 명령어 기반 검증 절차 문서 완료
- [ ] 계약 위반 시 실패하는 테스트 존재

---

### B.5 Phase 0~1 범위 재확정

**Phase 0 범위**:
- K8s 리소스(PVC, SealedSecret, ConfigMap)만 수정
- Observer 단독 안정 운영 확보
- 앱 코드, Dockerfile, 경로 구조 변경 금지
- 예외: 긴급 보안 패치, 데이터 손실 방지
- 완료 기준: 24시간 무중단 운영 + 데이터 영속성 확인

**Phase 1 범위**:
- Execution Contract 5개 항목 문서화
- Local pytest 기반 검증 자동화
- Docker/K8s는 명령어 기반 절차 정의
- QTS 앱을 위한 계약 재사용 가이드 작성
- 완료 기준: 3단계 검증 절차 문서 + Local 자동화 테스트 존재

**핵심 원칙**:
- Local 실패 → 앱 코드만 수정
- Docker 실패 → Dockerfile만 수정
- K8s 실패 → manifest만 수정
- 여러 계층 동시 수정 금지 (원인 파악 불가)
- Helm 템플릿 작성은 Phase 2 이전 절대 금지

---

**문서 끝**
