# k8s/e2e – E2E / Smoke 테스트

로컬 Kubernetes(kind, k3d 등)에서 배포 후 동작을 검증하는 테스트를 둡니다.

- **내용**: 배포 → 헬스체크 → 핵심 API/UI 호출 등
- **실행**: `make test-e2e` 또는 `./tests/k8s/e2e/run.sh` 등 (프로젝트에서 정의)

스크립트·테스트 케이스를 이 폴더에 추가하세요.
