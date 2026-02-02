# Observer ↔ PostgreSQL 연결 구조 검토

K8s base에서 Observer 앱과 PostgreSQL의 연결 관계 및 서비스 이름 검토 결과입니다.

## 1. 연결 관계 요약

```
[Observer Deployment]                    [PostgreSQL Deployment]
  - image: ghcr.io/tawbury/observer         - image: postgres:15-alpine
  - port: 8000                             - port: 5432
  - envFrom: observer-config               - envFrom: observer-secrets
            observer-secrets (optional)     - volume: observer-db-pvc
  - volume: observer-logs-pvc                    → /var/lib/postgresql/data
        ↓
  DB 접속 정보 (ConfigMap + Secret)
  - DB_HOST=postgres-svc
  - DB_PORT=5432
  - DB_NAME=observer
  - PGUSER/PGPASSWORD from observer-secrets
        ↓
[Service: postgres-svc]
  - ClusterIP, port 5432 → targetPort postgres (5432)
  - selector: app=postgres
        ↓
[PostgreSQL Pod]
```

- **Observer**는 DB 데이터 디렉터리를 마운트하지 않습니다. 네트워크로 **postgres-svc:5432**에 접속합니다.
- **observer-db-pvc**는 **PostgreSQL Pod**에만 연결되어 `/var/lib/postgresql/data`에 마운트됩니다.
- **observer-logs-pvc**는 Observer Pod의 `/app/logs`에만 사용됩니다.

## 2. Service 이름 및 DNS

| 리소스 | 이름 | 네임스페이스 (base) | 접근 방식 |
|--------|------|---------------------|-----------|
| PostgreSQL Service | **postgres-svc** | observer | 동일 네임스페이스: `postgres-svc` 또는 `postgres-svc:5432` |
| FQDN (동일 클러스터) | - | observer | `postgres-svc.observer.svc.cluster.local` |
| Observer ConfigMap | DB_HOST | - | `postgres-svc` (short name, overlay에서도 동일하게 동작) |

base의 namespace가 `observer`이고, overlay(production/staging)에서는 `observer-prod`, `observer-staging`으로 오버라이드됩니다.  
동일 네임스페이스 내에서는 **Service 이름만으로 접근**하므로 `DB_HOST=postgres-svc`로 두면 모든 overlay에서 정확히 동작합니다.

## 3. 검토 결과

- **PostgreSQL 전용 매니페스트**: `infra/k8s/base/deployments/postgres.yaml`, `services/postgres-svc.yaml` 생성 완료. observer-db-pvc는 Postgres의 `/var/lib/postgresql/data`에만 마운트됨.
- **Observer DB 접속**: ConfigMap `observer-config`의 `DB_HOST=postgres-svc`, `DB_PORT=5432`, `DB_NAME=observer`로 설정됨. Secret `observer-secrets`에서 `PGUSER`, `PGPASSWORD` 주입.
- **네임스페이스 일관성**: ghcr-secret, observer-secrets, observer-config, postgres, observer 모두 **동일 네임스페이스(observer 또는 overlay별 observer-prod/observer-staging)** 에서 관리되도록 가이드 반영.
- **마이그레이션 Job**: `ttlSecondsAfterFinished: 3600`으로 완료 1시간 후 자동 삭제. PGHOST 등은 observer-secrets에서 주입하며, 동일 네임스페이스의 postgres-svc에 접속.

## 4. 수정된 파일 구조 (관련 부분)

```
infra/k8s/base/
├── deployments/
│   ├── postgres.yaml      # Postgres 15, observer-db-pvc → /var/lib/postgresql/data
│   └── observer.yaml      # observer-logs-pvc만 사용, DB는 postgres-svc 접속
├── services/
│   ├── postgres-svc.yaml  # port 5432, selector app=postgres
│   └── observer-svc.yaml
├── configmaps/
│   └── observer-config.yaml  # DB_HOST=postgres-svc, DB_PORT, DB_NAME
├── pvc/
│   ├── observer-db-pvc.yaml   # Postgres 전용
│   └── observer-logs-pvc.yaml # Observer 로그 전용
└── kustomization.yaml        # postgres, postgres-svc 리소스 포함

infra/_shared/migrations/
└── job-template.yaml          # ttlSecondsAfterFinished: 3600

docs/
├── KUBECTL_AND_ARGOCD_SETUP.md   # observer 네임스페이스 ghcr-secret·observer-secrets 명령 추가
├── PERSISTENCE_AND_HOSTPATH.md  # observer-db-pvc = Postgres 전용 명시
└── OBSERVER_POSTGRES_CONNECTION.md  # 본 검토 문서
```

이 구성을 기준으로 배포 시 Observer ↔ PostgreSQL 연결이 정확히 동작합니다.
