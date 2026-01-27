# deploy – 배포 스크립트

배포 관련 공통 스크립트를 둡니다.

## 스크립트

| 파일 | 설명 |
|------|------|
| **deploy.ps1** | 로컬에서 실행하는 수동 배포 (env 검증/업로드, 아티팩트 업로드, server_deploy.sh 호출, 헬스체크). `-EnvOnly`로 env만 갱신 가능 |
| **server_deploy.sh** | 서버에서 실행. 이미지 pull, Compose 기동, 헬스체크, 백업 등 |

실행 경로: **프로젝트 루트**에서 `infra\_shared\scripts\deploy\deploy.ps1` 또는 `./infra/_shared/scripts/deploy/deploy.ps1` (PowerShell), 서버에는 `server_deploy.sh`를 업로드 후 `./server_deploy.sh ...` 로 실행.

## 사용 시점

- GitHub Actions 외에 **로컬에서 수동 배포**할 때
- 배포 디렉토리·Compose 파일·env 파일 경로를 프로젝트에 맞게 지정해서 실행

## 경로 관례

- Compose 파일: `infra/oci_deploy/docker-compose.prod.yml` 등, 아티팩트: `infra/docker/compose/`
- env 파일: `infra/_shared/secrets/.env.prod`
- 실행은 **프로젝트 루트** 또는 **infra/oci_deploy**에서 호출하는 것을 전제로 상대 경로 작성
