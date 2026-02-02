# Legacy (Docker Compose 기반)

이 디렉터리는 **Kubernetes(K3s) 배포로 전환하기 이전**의 Docker Compose 기반 설정을 보관합니다.

- **사용하지 마세요.** 신규 배포·자동화는 `infra/k8s/` 및 ArgoCD/kubectl 기준으로 진행하세요.
- AI·스크립트가 레거시와 현행(k8s) 매니페스트를 혼동하지 않도록 여기로만 한정해 두었습니다.

## 포함된 항목

| 폴더 | 설명 |
|------|------|
| `docker/` | 로컬/서버용 docker-compose 및 Dockerfile (k8s 미사용) |
| `monitoring/` | Prometheus/Grafana/Alertmanager docker-compose 스택 |
| `oci_deploy/` | OCI VM용 docker-compose.prod 및 구 마이그레이션/모니터링 복사본 |

## 현행 구조

- **K8s 매니페스트**: `infra/k8s/base`, `infra/k8s/overlays/`
- **공통 인프라**: `infra/_shared/` (마이그레이션 SQL, 스크립트, 모니터링 참고)
- **모니터링 (k8s)**: kube-prometheus-stack(Helm) 등은 `_shared/monitoring/` 또는 별도 레포에서 관리
