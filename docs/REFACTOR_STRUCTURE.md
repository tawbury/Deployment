# 리팩토링 후 폴더 구조 (K8s / Observer 중심)

배포 레포의 **infra** 및 **docs** 기준 구조입니다. 레거시는 `infra/_legacy`로 이동했습니다.

## infra/

```
infra/
├── _legacy/                    # Docker Compose 기반 레거시 (참고용, 사용 금지)
│   ├── README.md
│   ├── docker/
│   │   ├── .dockerignore
│   │   ├── compose/
│   │   │   ├── docker-compose.server.yml
│   │   │   └── docker-compose.yml
│   │   └── docker/
│   │       └── Dockerfile
│   ├── monitoring/
│   │   ├── alertmanager.yml
│   │   ├── docker-compose.yml
│   │   ├── grafana_dashboard.json
│   │   ├── prometheus_alerting_rules.yaml
│   │   └── prometheus.yml
│   └── oci_deploy/
│       ├── docker-compose.prod.yml
│       ├── migrations/
│       ├── monitoring/
│       └── README_APP_LEGACY.md
│
├── k8s/                        # [현행] Kubernetes(K3s) 매니페스트
│   ├── README.md
│   ├── base/                   # Observer 전용 base
│   │   ├── kustomization.yaml
│   │   ├── namespaces/
│   │   │   └── observer.yaml
│   │   ├── deployments/
│   │   │   └── observer.yaml
│   │   ├── services/
│   │   │   └── observer-svc.yaml
│   │   ├── configmaps/
│   │   │   └── observer-config.yaml
│   │   ├── secrets/
│   │   │   └── observer-secrets.yaml   # 가이드만 (값 없음)
│   │   ├── pvc/
│   │   │   ├── observer-db-pvc.yaml
│   │   │   └── observer-logs-pvc.yaml
│   │   └── ingress/
│   │       └── observer-ingress.yaml
│   └── overlays/
│       ├── production/
│       │   ├── kustomization.yaml
│       │   └── patches/
│       │       ├── replicas.yaml
│       │       └── resources.yaml
│       └── staging/
│           ├── kustomization.yaml
│           └── patches/
│               ├── replicas.yaml
│               └── resources.yaml
│
└── _shared/
    ├── deploy/
    │   └── observer.yaml       # VM용 선언 스펙 (기존)
    ├── migrations/
    │   ├── README.md
    │   ├── job-template.yaml   # DB 마이그레이션 Job (Pre-Sync Hook 가능)
    │   ├── 001_create_scalp_tables.sql
    │   ├── 002_create_swing_tables.sql
    │   ├── 003_create_portfolio_tables.sql
    │   └── 004_create_analysis_tables.sql
    ├── monitoring/             # 참고용 (k8s는 kube-prometheus-stack 등 별도)
    │   └── ...
    └── scripts/
        ├── build/
        │   ├── generate_build_tag.ps1
        │   ├── generate_build_tag.sh   # YYYYMMDD-HHMMSS 태그 생성
        │   └── README.md
        ├── deploy/
        │   ├── k8s-deploy.sh          # kustomize 배포 (Observer)
        │   ├── set-image-tag.sh        # overlay 이미지 태그 설정
        │   ├── deploy.sh
        │   ├── rollback.sh
        │   └── ...
        ├── k3s/
        ├── migrate/
        └── ...
```

## docs/

```
docs/
├── _shared/
│   ├── arch/
│   │   ├── k8s_architecture.md
│   │   ├── k8s_app_architecture.md
│   │   └── k8s_sub_architecture.md
│   └── APP_DOCKER_TEMPLATE_SPECIFICATION.md
├── observer/
│   └── OCI_SERVER_INFO.md
├── PERSISTENCE_AND_HOSTPATH.md   # DB/로그 호스트 매핑 (PVC·HostPath)
├── KUBECTL_AND_ARGOCD_SETUP.md   # kubectl·ArgoCD 설정 가이드
└── REFACTOR_STRUCTURE.md        # 본 문서
```

## 요약

- **현행 배포**: `infra/k8s/base` + `overlays/production|staging` (Observer, Port 8000, /health)
- **레거시**: `infra/_legacy` (docker, monitoring, oci_deploy) – AI/스크립트 혼동 방지용 분리
- **영속성·설정**: [PERSISTENCE_AND_HOSTPATH.md](PERSISTENCE_AND_HOSTPATH.md), [KUBECTL_AND_ARGOCD_SETUP.md](KUBECTL_AND_ARGOCD_SETUP.md)
