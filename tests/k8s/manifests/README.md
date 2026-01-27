# k8s/manifests – 매니페스트 테스트 리소스

Kubernetes 매니페스트 검증·테스트에 쓰는 예시/테스트용 리소스를 둡니다.

- **내용**: e2e/lint용 샘플 매니페스트, 테스트 전용 Deployment/Service 등
- **용도**: `tests/k8s/lint` 검증 대상, `tests/k8s/e2e` 배포 대상으로 사용

실제 서비스 매니페스트는 `infra/k8s/` 등에 두고, 여기에는 검증/테스트용만 둡니다.
