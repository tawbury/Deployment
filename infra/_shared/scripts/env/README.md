# env – 환경 설정 스크립트

환경 변수·시크릿 설정용 공통 스크립트를 둡니다.

## 예정 스크립트

| 파일 | 설명 |
|------|------|
| **setup_env_secure.sh** | 예시에서 실제 env 파일 생성, 권한 설정(예: 600), 필수 변수 검증 등. `infra/_shared/secrets/` 경로 참조 |

## 사용 시점

- 최초 세팅 시 `.env.prod` 등 생성·검증
- CI/배포 파이프라인에서 env 파일 준비 단계

## 참조 경로

- 예시 파일: `infra/_shared/secrets/env.prod.example` (또는 `infra/oci_deploy/.env.prod.example`)
- 출력/검증 대상: `infra/_shared/secrets/.env.prod` 등

스크립트 추가 시 `infra/_shared/secrets/` 이하만 참조하고, 환경별 env는 인자 또는 환경변수로 구분하면 됩니다.
