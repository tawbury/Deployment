# build – 빌드 태그 생성

Docker 이미지 빌드 시 사용하는 타임스탬프 기반 태그(20YYMMDD-HHMMSS) 생성 스크립트입니다.

## 스크립트

| 파일 | 설명 |
|------|------|
| **generate_build_tag.ps1** | PowerShell: 태그 생성·검증·파일 저장. `-OutputFile` 옵션 지원 |
| **generate_build_tag.sh** | Bash: 태그 생성·검증·파일 저장. 인자로 출력 파일 경로 지정 가능 |

## 사용 시점

- 로컬 또는 CI에서 Docker 이미지 빌드 전 태그 생성
- GitHub Actions 등에서는 인라인으로 동일 형식 생성 가능

## 실행 예 (프로젝트 루트 기준)

```powershell
# PowerShell
.\infra\_shared\scripts\build\generate_build_tag.ps1
.\infra\_shared\scripts\build\generate_build_tag.ps1 -OutputFile "BUILD_TAG.txt"
```

```bash
# Bash
./infra/_shared/scripts/build/generate_build_tag.sh
./infra/_shared/scripts/build/generate_build_tag.sh BUILD_TAG.txt
```
