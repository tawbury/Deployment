# App Docker Template Specification (Observer 기준)

**버전**: 1.0  
**기준 앱**: observer (리팩토링 완료 구조)  
**용도**: QTS 및 신규 앱이 따라야 할 공통 App Docker 템플릿 명세. 이 문서만으로 리팩토링·검증 가능해야 함.

---
### 본 템플릿은 Python 애플리케이션을 기준으로 작성되었다.
(Node.js 등 타 언어 앱은 본 문서를 구조/책임 기준으로만 참고하고, Dockerfile 세부 내용은 언어에 맞게 조정한다.)

## 1. App 디렉터리 표준 구조 명세

### 1.1 경로 규칙

- 앱 루트는 **반드시** `app/<app-name>/` 이다.
- `<app-name>` 예: `observer`, `qts`. 소문자·스네이크 권장.

### 1.2 필수 파일 (반드시 존재)

| 파일 | 책임 |
|------|------|
| `app/<app-name>/Dockerfile` | 해당 앱 전용 이미지 빌드 정의. 빌드 컨텍스트는 `app/<app-name>` 만 사용한다. |
| `app/<app-name>/.dockerignore` | 빌드 컨텍스트 루트 = `app/<app-name>` 기준으로 제외 규칙을 정의한다. |
| `app/<app-name>/requirements.txt` | Python 의존성 목록. Dockerfile에서 반드시 참조한다. |
| `app/<app-name>/__main__.py` | `python -m <app-name>` 실행 시 진입점. CMD에서 이 방식으로 기동하는 것을 전제로 한다. |

### 1.3 포함 권장 (이미지에 포함)

| 항목 | 설명 |
|------|------|
| `env.template` | 환경 변수 템플릿. 런타임 `.env`는 이미지에 넣지 않는다. |
| `src/` | 앱 소스 코드. 이미지 내부 경로는 Dockerfile에서 고정한다 (예: `/app/src`). |
| 앱별 설정 템플릿 | 예: `deployment_config.json` 등, 실행에 필요한 구조만. 런타임 생성 파일은 제외. |

### 1.4 이미지에 포함하지 않는 디렉터리 (런타임 마운트 전제)

다음은 **로컬/서버에만 존재**하고, 이미지에는 **빈 디렉터리만** 두거나 아예 COPY하지 않는다. `.dockerignore`로 제외하고, Dockerfile의 `RUN mkdir -p`로 빈 디렉터리만 생성한다.

| 디렉터리 | 용도 |
|----------|------|
| `data/` | 런타임 데이터. 마운트로 덮어쓴다. |
| `logs/` | 런타임 로그. 마운트로 덮어쓴다. |
| `config/` 하위 런타임 내용 | 런타임에 생성·갱신되는 설정 파일. 마운트로 덮어쓴다. |
| `secrets/` | `.env`, 토큰 캐시 등. **절대 이미지에 포함하지 않는다.** 런타임 마운트만 사용한다. |

### 1.5 금지 사항

- `app/<app-name>/` 밖의 경로를 Dockerfile에서 **COPY** 하면 안 된다.
- Dockerfile은 **반드시** `app/<app-name>/` 안에만 존재한다. `infra/docker/Dockerfile` 같은 앱 외부 Dockerfile은 사용하지 않는다.

---

## 2. Dockerfile 표준 책임 명세

### 2.1 반드시 책임져야 하는 것

| 항목 | 규칙 |
|------|------|
| **빌드 컨텍스트** | `app/<app-name>` 단일 경로. 상위 디렉터리(`app/` 밖) 참조 금지. |
| **COPY 경로** | 컨텍스트 루트 기준. 예: `COPY requirements.txt .`, `COPY . /app/`. `app/observer/` 같은 상대 경로는 사용하지 않는다 (컨텍스트가 이미 앱 루트이므로). |
| **WORKDIR** | 이미지 내 앱 루트를 하나로 고정한다. 예: `WORKDIR /app`. |
| **PYTHONPATH** | 실행 시 모듈 검색 경로를 Dockerfile에서 정의한다. 예: `ENV PYTHONPATH=/app/src:/app`. |
| **엔트리포인트** | `CMD`로 실행 방식을 고정한다. 예: `CMD ["python", "-m", "<app-name>"]`. exec 형 사용. |
| **앱 전용 ENV** | 데이터/로그/설정/시크릿 경로 등, 앱이 참조하는 환경 변수를 Dockerfile에서 기본값으로 정의한다. 런타임 마운트 경로와 일치시킨다. |
| **시간대** | 컨테이너 기본 시간대를 설정한다. 예: `ENV TZ=Asia/Seoul` 및 `RUN ln -snf ...`. |
| **빈 런타임 디렉터리** | `data/`, `logs/`, `config/` 하위, `secrets/` 등 런타임에 마운트될 디렉터리를 `RUN mkdir -p`로 생성한다. |
| **비 root 사용자** | 보안상 `USER`를 비 root로 설정한다. `groupadd`/`useradd` 후 `chown`으로 앱 디렉터리 소유권 부여. |

### 2.2 절대 책임지지 말아야 하는 것

| 항목 | 규칙 |
|------|------|
| **상위 디렉터리 COPY** | `COPY ../../something` 또는 프로젝트 루트 기준 `app/<other>/` 참조 금지. |
| **서버/호스트 경로** | 호스트 절대 경로, 서버명, 배포 디렉터리 구조를 Dockerfile에 하드코딩하지 않는다. |
| **docker-compose 전용 설정** | 네트워크, 다른 서비스, 볼륨 마운트 호스트 경로는 compose 책임. Dockerfile은 이미지 내부만 정의. |
| **비밀값 주입** | `.env` 내용, API 키, 비밀번호를 이미지에 포함하지 않는다. |
| **런타임 데이터 포함** | `data/`, `logs/`, `secrets/` 내용을 COPY하지 않는다. `.dockerignore`로 제외. |

### 2.3 ENV 정의 범위

- **Dockerfile에서 정의하는 ENV**: 앱이 사용하는 **경로·동작 모드**의 기본값. 예: `OBSERVER_DATA_DIR=/app/data`, `OBSERVER_STANDALONE=1`, `PYTHONPATH`, `TZ`.
- **Dockerfile에서 정의하지 않는 ENV**: 비밀값, DB 호스트/비밀번호, API 키 등. 이는 `env_file` 또는 compose `environment`로 런타임에 주입한다.

### 2.4 USER / 권한 정책

- **필수**: `RUN groupadd -r <app-user> && useradd -r -g <app-user> <app-user>` 후 `RUN chown -R <app-user>:<app-user> /app`, 마지막에 `USER <app-user>`.
- **금지**: `USER root`로 최종 실행하지 않는다 (보안). 단, `chown` 등 설정 단계에서만 root 사용 가능.

### 2.5 HEALTHCHECK

- **선택**이지만, HTTP/API를 제공하는 앱은 **권장**한다.
- 사용 시: `HEALTHCHECK --interval=... --timeout=... --start-period=... --retries=... CMD ["python", "-c", "..."]` 등 **exec 형**만 사용한다. 셸 의존 금지.
- 사용하지 않는 앱(배치만 등)은 HEALTHCHECK를 두지 않아도 된다. 명세에서는 **HTTP 서비스 앱은 HEALTHCHECK를 두는 것**을 기준으로 한다.
- HTTP 포트를 열지 않는 순수 배치/크론 앱은 HEALTHCHECK를 두지 않아도 된다.

### 2.6 EXPOSE

- 앱이 리스닝하는 포트를 `EXPOSE`로 명시한다. 예: `EXPOSE 8000`. 실제 바인딩은 compose/런타임 책임.

---

## 3. `.dockerignore` 표준 규칙

### 3.1 빌드 컨텍스트

- `.dockerignore`는 **반드시** `app/<app-name>/` 루트에 둔다.
- Docker는 **컨텍스트 루트**의 `.dockerignore`만 적용한다. 서브디렉터리의 `.dockerignore`는 사용하지 않는다.

### 3.2 반드시 제외해야 하는 항목

| 범주 | 패턴/디렉터리 |
|------|----------------|
| **Python** | `__pycache__/`, `*.pyc`, `*.pyo`, `*.pyd`, `.pytest_cache/`, `*.egg-info/`, `.eggs/`, `*.egg` |
| **런타임 디렉터리** | `logs/`, `data/`, `secrets/`. `config/` 하위 중 런타임 생성 디렉터리(예: `config/scalp/`, `config/swing/`, `config/universe/`, `config/symbols/`, `config/observer/`, `config/system/`, `config/backups/`) |
| **비밀·env** | `.env`, `.env.*` (단, `env.template`는 제외하지 않음. 파일명이 `env.template`이면 `.env.*`에 매칭되지 않음) |
| **문서·테스트** | `*.md`, `test/`, `tests/`, `.git/`, `.gitignore` |
| **개발 도구** | `.vscode/`, `.venv/`, `venv/`, `*.log`, `*.sqlite3`, `*.db`, `*.tar`, `*.tar.gz`, `*.tar.bak` |
| **OS** | `.DS_Store`, `Thumbs.db` |

### 3.3 “런타임 마운트 전제” 디렉터리 정의

- **이미지에 포함하지 않고**, 런타임에 호스트 볼륨으로 마운트해 덮어쓴다고 가정하는 디렉터리:
  - `data/`
  - `logs/`
  - `config/` 하위 중 앱이 런타임에 쓰는 모든 경로
  - `secrets/`
- 이들은 `.dockerignore`로 **전부 제외**하고, Dockerfile에서는 `RUN mkdir -p /app/data/...` 등으로 **빈 디렉터리만** 만든다.

### 3.4 보안상 절대 이미지에 포함되면 안 되는 항목

| 항목 | 규칙 |
|------|------|
| `.env` | 런타임 env 파일. **절대 COPY하지 않고 .dockerignore로 제외.** |
| `.env.*` | 환경별 env. 동일하게 제외. |
| `secrets/` | 토큰, API 키, 인증 캐시 등. **디렉터리 전체 제외.** |
| `*.key`, `*.pem`, `*.crt`, `*.p12`, `*.pfx` | 인증서·키 파일. 명세상 `.dockerignore`에 두는 것을 권장. |
| `**/credentials.json`, `api_keys.txt` 등 | 비밀 포함 가능 파일. 제외. |

---

## 4. infra / app / CI 책임 경계 명세

### 4.1 app (`app/<app-name>/`)

| 포함 | 모름(하지 않음) |
|------|------------------|
| 앱 소스 코드, 진입점(`__main__.py`), `requirements.txt` | 프로젝트 루트, 다른 앱 디렉터리 |
| `Dockerfile`, `.dockerignore` (앱 단독 빌드 가능) | docker-compose 파일 위치·내용 |
| 이미지 내부 경로(`/app`, `/app/data`, `/app/logs` 등) 및 해당 ENV | 호스트 절대 경로, 서버명, 배포 디렉터리 |
| `env.template` (구조만) | 실제 `.env` 값, 비밀값 |
| 빈 런타임 디렉터리 생성 | 볼륨 마운트 호스트 경로, 네트워크, 다른 서비스 |

- **원칙**: 앱은 “이미지 하나만 주어지면 `docker run`으로 실행 가능한 단위”까지 책임진다. **어디서, 어떤 compose로 돌릴지는 모른다.**

### 4.2 infra (배포·compose·스크립트)

| 관리 대상 | 책임 |
|-----------|------|
| **compose 파일** | `infra/_shared/compose/`, `infra/docker/compose/` 등. 서비스 정의, 네트워크, **볼륨 마운트 호스트 경로**, `env_file` 경로, `build.context`/`build.dockerfile`를 `app/<app-name>` 기준으로 지정. |
| **배포 스크립트** | 서버 디렉터리 생성, 이미지 pull, compose 실행, 헬스 체크. **앱 Dockerfile 내용은 수정하지 않음.** |
| **마이그레이션·모니터링** | DB 마이그레이션 SQL, Prometheus/Grafana 설정 등. 앱 이미지와 분리. |
| **금지** | 앱 소스 코드 수정, 앱 전용 Dockerfile을 앱 밖에 두는 것, 앱 `requirements.txt` 변경. |

- **원칙**: infra는 “어디서, 어떤 옵션으로 앱 이미지를 돌릴지”만 관리한다. **이미지 빌드 규칙은 앱이 정한다.**

### 4.3 CI (GitHub Actions)

| 담당 | 비담당 |
|------|--------|
| **이미지 빌드·푸시** | `context: app/<app-name>`, `file: app/<app-name>/Dockerfile` 로 빌드, GHCR 등에 푸시. | 앱 Dockerfile 내부 내용 변경, compose 수정. |
| **태그·캐시** | 태그 전략(build-YYYYMMDD-HHMMSS, latest), buildx 캐시. | 서버 배포, 볼륨 경로, env 파일 내용. |
| **트리거** | PR 머지, workflow_dispatch 등. | 앱별 비즈니스 로직, 테스트 코드 실행(별도 job이면 가능). |

- **원칙**: CI는 “앱 디렉터리를 주어진 대로 빌드해서 레지스트리에 올리는 것”만 담당한다. **빌드 컨텍스트는 반드시 `app/<app-name>`.**

---

## 5. 템플릿 준수 체크리스트

QTS 또는 신규 앱 리팩토링 시, **“이 앱이 템플릿을 준수했는지”** 기계적으로 확인할 때 사용한다. 모두 “예”여야 한다.

### 5.1 디렉터리·파일

- [ ] `app/<app-name>/Dockerfile` 이 존재한다.
- [ ] `app/<app-name>/.dockerignore` 이 존재한다.
- [ ] `app/<app-name>/requirements.txt` 가 존재한다.
- [ ] `app/<app-name>/__main__.py` 가 존재한다 (Python 앱인 경우).
- [ ] Dockerfile이 `app/<app-name>/` 밖의 경로를 COPY하지 않는다.

### 5.2 빌드

- [ ] 빌드 컨텍스트가 `app/<app-name>` 이다. (로컬: `docker build -f app/<app-name>/Dockerfile app/<app-name>`)
- [ ] compose 없이 `docker build -f app/<app-name>/Dockerfile app/<app-name>` 만으로 이미지 빌드가 성공한다.
- [ ] `.dockerignore`가 `app/<app-name>/` 루트에 있으며, `logs/`, `data/`, `secrets/`, `.env` 등이 제외되어 있다.

### 5.3 런타임·보안

- [ ] 런타임 디렉터리(`data/`, `logs/`, `config/` 런타임 하위, `secrets/`)가 이미지에 내용으로 포함되지 않는다 (빈 디렉터리만 있음).
- [ ] `.env`, `secrets/` 가 이미지에 포함되지 않는다.
- [ ] Dockerfile에서 최종 `USER`가 root가 아니다.

### 5.4 엔트리포인트·환경

- [ ] Dockerfile의 `CMD`가 exec 형이다. 예: `CMD ["python", "-m", "<app-name>"]`.
- [ ] `WORKDIR`와 `PYTHONPATH`가 Dockerfile에서 정의되어 있다.
- [ ] 앱이 사용하는 데이터/로그/설정/시크릿 경로의 ENV가 Dockerfile에 기본값으로 정의되어 있다.

### 5.5 다중 앱 대칭 (observer / qts 등)

- [ ] `app/observer/` 와 `app/qts/` (또는 다른 앱)이 동일한 규칙을 따른다: 각각 자신의 `Dockerfile`, `.dockerignore`, `requirements.txt`, `__main__.py` 를 가지며, 빌드 컨텍스트는 각각 `app/observer`, `app/qts` 이다.
- [ ] CI에서 앱별로 `context: app/<app-name>`, `file: app/<app-name>/Dockerfile` 로 빌드할 수 있다.

### 5.6 infra / CI 경계

- [ ] `infra/` 에 앱 전용 Dockerfile이 없다. (앱 Dockerfile은 `app/<app-name>/` 안에만 있다.)
- [ ] GitHub Actions 빌드 job의 `context`가 `app/<app-name>` 이고, `file`이 `app/<app-name>/Dockerfile` 이다.

---

## 6. 문서 사용 방법

- **QTS 리팩토링**: 이 문서의 1~3절에 맞춰 `app/qts/` 에 Dockerfile·.dockerignore를 두고, 5절 체크리스트로 검증한다.
- **신규 앱 추가**: 1절 구조를 따르고, 2~3절으로 Dockerfile·.dockerignore를 작성한 뒤 5절로 준수 여부를 확인한다.
- **검증**: “compose 없이 앱 디렉터리만으로 빌드 가능한가”, “이미지에 런타임/비밀 디렉터리가 포함되지 않았는가”를 5절 체크리스트로 점검한다.

이 명세는 **구현 기준으로 단정적**이며, 이후 단계에서 이 명세를 **전제로 수정 작업이 진행**된다.
