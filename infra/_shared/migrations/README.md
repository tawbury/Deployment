# DB 마이그레이션

Observer/QTS 등 앱에서 사용하는 DB 스키마 마이그레이션 SQL과 K8s Job 템플릿입니다.

## 실행 순서

1. **ConfigMap 생성** (SQL 파일을 클러스터에 올림)
   ```bash
   kubectl create configmap observer-migrations \
     --from-file=001_create_scalp_tables.sql=001_create_scalp_tables.sql \
     --from-file=002_create_swing_tables.sql=002_create_swing_tables.sql \
     --from-file=003_create_portfolio_tables.sql=003_create_portfolio_tables.sql \
     --from-file=004_create_analysis_tables.sql=004_create_analysis_tables.sql \
     --from-file=005_create_trading_tables.sql=005_create_trading_tables.sql \
     -n observer
   ```
   (위는 `infra/_shared/migrations/` 디렉터리에서 실행)

2. **Secret에 DB 접속 정보 설정**
   - `observer-secrets`에 `PGHOST`, `PGPORT`, `PGDATABASE`, `PGUSER`, `PGPASSWORD` 포함

3. **Job 실행** (앱 배포 전 1회)
   - `job-template.yaml`의 `namespace`를 overlay에 맞게 수정 후 적용
   - `kubectl apply -f job-template.yaml`
   - 완료 확인: `kubectl wait --for=condition=complete job/observer-migrate -n observer --timeout=300s`

## ArgoCD Pre-Sync Hook

앱 배포 전에 자동으로 마이그레이션을 실행하려면 `job-template.yaml`의 주석을 해제:

```yaml
metadata:
  annotations:
    argocd.argoproj.io/hook: PreSync
    argocd.argoproj.io/hook-delete-policy: BeforeHookCreation
```

마이그레이션 Job을 Application에 포함하거나, 별도 Application으로 관리하세요.
