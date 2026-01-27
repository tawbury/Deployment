# Tests

테스트 코드 및 검증 스크립트를 둡니다.

## 📁 구조

```
tests/
├── unit/          # 단위 테스트 (앱/로직)
├── integration/   # 통합 테스트 (DB, API 등)
├── smoke/         # 스모크 테스트 (배포 직후 최소 동작 확인)
├── perf/           # 성능·부하 테스트
├── k8s/            # Kubernetes 관련 테스트
│   ├── e2e/        # E2E (kind, k3d 등)
│   ├── lint/       # 매니페스트·Helm chart 검증
│   └── manifests/  # 테스트용 매니페스트/샘플 리소스
└── README.md       # 이 파일
```

각 하위 폴더의 README에 용도와 실행 방법을 적어 두세요.
