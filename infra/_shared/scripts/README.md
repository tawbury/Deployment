# 공통 스크립트 (Shared Scripts)

이 디렉토리는 **모든 환경**에서 공통으로 사용하는 인프라/배포 스크립트를 담습니다.

## 📁 디렉토리 구조

```
infra/_shared/scripts/
├── deploy/           # 배포 (deploy.ps1, server_deploy.sh)
├── build/            # 빌드 태그 생성 (generate_build_tag.ps1, generate_build_tag.sh)
├── docker/           # Docker/Compose 헬퍼 (sync_container_time.ps1 등)
├── env/               # 환경 설정 (setup_env_secure.sh)
├── migrate/           # DB/앱 마이그레이션 (migrate.sh)
├── docs/              # QUICKSTART, IMPLEMENTATION_REPORT 등 상위 문서
└── README.md          # 이 파일
```

## 📋 역할별 설명

| 폴더 | 역할 | 스크립트 |
|------|------|-----------|
| **deploy/** | 배포 (로컬→서버, Compose 기동 등) | deploy.ps1, server_deploy.sh |
| **build/** | 빌드 태그 생성 (20YYMMDD-HHMMSS) | generate_build_tag.ps1, generate_build_tag.sh |
| **docker/** | Docker/Compose 헬퍼 | sync_container_time.ps1 (컨테이너·호스트 시간 drift 검사) |
| **env/** | 환경 변수·시크릿 설정 | setup_env_secure.sh |
| **migrate/** | DB/앱 마이그레이션 | migrate.sh (Phase 13 JSONL→DB 등) |

## 🔗 _shared 리소스 참조

스크립트 내부에서는 상대 경로로 공통 리소스를 참조합니다.

- **마이그레이션**: `../../migrations/`
- **시크릿/환경변수**: `../../secrets/.env.prod` 등
- **모니터링 설정**: `../../monitoring/`

실행 시 작업 디렉토리는 **프로젝트 루트** 또는 **infra/oci_deploy** 등 호출 위치에 맞춰 상대 경로를 해석합니다.

## 🚫 환경 전용 스크립트

OCI·K8s 등 **특정 환경만** 쓰는 스크립트는 여기 두지 않습니다.

- OCI 전용: `infra/oci_deploy/scripts/`
- Kubernetes 전용: `infra/k8s/scripts/` (향후)

공통으로 쓰는 로직만 `_shared/scripts/`에 두고, 환경별 래퍼나 옵션은 각 환경 폴더에서 관리합니다.

## 📚 하위 폴더별 가이드

- [deploy/README.md](deploy/README.md) – 배포 스크립트 사용법
- [build/README.md](build/README.md) – 빌드 태그 생성 (generate_build_tag.ps1, generate_build_tag.sh)
- [migrate/README.md](migrate/README.md) – 마이그레이션 스크립트 사용법
- [docker/README.md](docker/README.md) – Docker/Compose 스크립트 사용법
- [env/README.md](env/README.md) – 환경 설정 스크립트 사용법
- [docs/](docs/) – QUICKSTART, IMPLEMENTATION_REPORT 등 상위 문서

---

**마지막 업데이트**: 2026-01-27
