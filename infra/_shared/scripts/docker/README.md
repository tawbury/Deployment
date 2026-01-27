# docker – Docker/Compose 헬퍼 스크립트

Docker Compose 기동·중지·로그 등 공통 헬퍼 스크립트를 둡니다.

## 예정 스크립트

| 파일 | 설명 |
|------|------|
| **compose-up.sh** | Compose 스택 기동. compose 파일·env 파일 경로를 인자로 받거나 기본값 사용 |
| **compose-down.sh** | Compose 스택 중지 |
| **compose-logs.sh** | 로그 tail (서비스명/옵션 지정 가능) |

## 사용 시점

- 모니터링만 띄울 때: `infra/_shared/monitoring/docker-compose.yml` 기준
- 전체 스택(DB·앱·모니터링) 띄울 때: `infra/oci_deploy/docker-compose.prod.yml` + `infra/_shared/secrets/.env.prod` 기준

스크립트는 **프로젝트 루트** 또는 **infra/oci_deploy**에서 호출하는 것을 전제로, 상대 경로로 compose/env를 지정하면 됩니다.
