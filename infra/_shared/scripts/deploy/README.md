# deploy - 배포 스크립트

K3s/ArgoCD 마이그레이션 완료 후, 레거시 Docker 기반 배포 스크립트는 삭제되었습니다.

## 현재 배포 방식

- **ArgoCD + Helm**: `infra/helm/{app}/` 차트를 ArgoCD가 자동 sync
- **CI/CD**: GitHub Actions → GHCR 이미지 빌드 → Deployment repo values.yaml 자동 업데이트 → ArgoCD sync

## 남아있는 스크립트

| 파일 | 설명 |
|------|------|
| **k8s-deploy.sh** | kubectl 기반 수동 배포 (비상 시 사용) |

## 삭제된 스크립트 (2026-02)

레거시 Docker Compose 기반 배포 스크립트:
`deploy.sh`, `deploy.ps1`, `server_deploy.sh`, `set-image-tag.sh`, `rollback.sh`, `check_health.sh`
