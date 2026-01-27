# migrate – DB 마이그레이션 스크립트

DB 마이그레이션 실행용 공통 스크립트를 둡니다.

## 예정 스크립트

| 파일 | 설명 |
|------|------|
| **migrate.sh** | `infra/_shared/migrations/` 아래 SQL을 대상 DB에 순서대로 실행. psql 사용 |

## 사용 예시

```bash
# 프로젝트 루트에서
./infra/_shared/scripts/migrate/migrate.sh \
  --host "${DB_HOST}" \
  --port "${DB_PORT}" \
  --database "${DB_NAME}" \
  --user "${DB_USER}"
```

스크립트 내부에서는 마이그레이션 파일 경로를 `infra/_shared/migrations/`로 고정하거나, `--migrations-dir` 등으로 오버라이드 가능하게 구현하면 됩니다.

## 마이그레이션 파일 위치

- `infra/_shared/migrations/001_create_scalp_tables.sql`
- `infra/_shared/migrations/002_create_swing_tables.sql`
- `infra/_shared/migrations/003_create_portfolio_tables.sql`

migrate.sh는 이 순서대로 실행하는 식으로 구현하면 됩니다.
