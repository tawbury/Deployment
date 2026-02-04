# SealedSecrets 사용 가이드

이 디렉토리는 Bitnami SealedSecrets를 사용하여 암호화된 Secret을 관리합니다.

## 개요

SealedSecrets는 Kubernetes Secret을 암호화하여 Git 레포지토리에 안전하게 저장할 수 있게 해주는 도구입니다.

## 사전 요구사항

### 1. SealedSecrets 컨트롤러 설치 (클러스터 관리자)

```bash
# Helm 사용
helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets
helm repo update
helm install sealed-secrets sealed-secrets/sealed-secrets \
  --namespace sealed-secrets \
  --create-namespace \
  --version 2.15.0

# 또는 kubectl 직접 적용
kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.26.0/controller.yaml
```

### 2. kubeseal CLI 설치 (개발자)

**Windows (PowerShell)**:
```powershell
# Chocolatey 사용
choco install kubeseal

# 또는 수동 다운로드
$url = "https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.26.0/kubeseal-0.26.0-windows-amd64.tar.gz"
Invoke-WebRequest -Uri $url -OutFile kubeseal.tar.gz
tar -xzf kubeseal.tar.gz
Move-Item kubeseal.exe C:\Windows\System32\
```

**Linux/macOS**:
```bash
# Homebrew 사용
brew install kubeseal

# 또는 직접 다운로드
wget https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.26.0/kubeseal-0.26.0-linux-amd64.tar.gz
tar -xzf kubeseal-0.26.0-linux-amd64.tar.gz
sudo install -m 755 kubeseal /usr/local/bin/kubeseal
```

## Secret 생성 및 암호화

### 방법 1: 새로운 Secret 생성

```bash
# 1. 평문 Secret YAML 생성 (Git에 커밋하지 않음!)
kubectl create secret generic observer-secrets \
  --from-literal=POSTGRES_USER=observer \
  --from-literal=POSTGRES_PASSWORD='<strong-password>' \
  --from-literal=DB_USER=observer \
  --from-literal=DB_PASSWORD='<strong-password>' \
  --from-literal=KIS_APP_KEY='<your-kis-app-key>' \
  --from-literal=KIS_APP_SECRET='<your-kis-app-secret>' \
  --from-literal=KIS_HTS_ID='<your-hts-id>' \
  --namespace observer-prod \
  --dry-run=client -o yaml > temp-secret.yaml

# 2. SealedSecret으로 암호화
kubeseal --format yaml \
  --controller-name sealed-secrets \
  --controller-namespace sealed-secrets \
  < temp-secret.yaml \
  > observer-sealed-secrets.yaml

# 3. 평문 Secret 삭제 (보안)
rm temp-secret.yaml

# 4. Git 커밋
git add observer-sealed-secrets.yaml
git commit -m "chore: update observer secrets"
git push origin master
```

### 방법 2: 기존 Secret 변환

```bash
# 클러스터에서 기존 Secret 추출
kubectl get secret observer-secrets -n observer-prod -o yaml > temp-secret.yaml

# SealedSecret으로 암호화
kubeseal --format yaml < temp-secret.yaml > observer-sealed-secrets.yaml

# 평문 Secret 삭제
rm temp-secret.yaml
```

### 방법 3: .env 파일 사용

```bash
# .env 파일 준비
cat > secrets.env <<EOF
POSTGRES_USER=observer
POSTGRES_PASSWORD=strong-password
DB_USER=observer
DB_PASSWORD=strong-password
KIS_APP_KEY=your-key
KIS_APP_SECRET=your-secret
KIS_HTS_ID=your-id
EOF

# Secret 생성 및 암호화
kubectl create secret generic observer-secrets \
  --from-env-file=secrets.env \
  --namespace observer-prod \
  --dry-run=client -o yaml | \
kubeseal --format yaml \
  --controller-name sealed-secrets \
  --controller-namespace sealed-secrets \
  > observer-sealed-secrets.yaml

# 평문 파일 삭제
rm secrets.env
```

## Secret 값 변경

```bash
# 1. 새 값으로 Secret 생성
kubectl create secret generic observer-secrets \
  --from-literal=NEW_KEY='new-value' \
  --namespace observer-prod \
  --dry-run=client -o yaml > temp-secret.yaml

# 2. 암호화
kubeseal --format yaml < temp-secret.yaml > observer-sealed-secrets.yaml

# 3. Git 커밋
git add observer-sealed-secrets.yaml
git commit -m "chore: update observer secrets"
git push origin master

# 4. 평문 파일 삭제
rm temp-secret.yaml
```

## 배포 프로세스

1. SealedSecret을 Git에 푸시
2. ArgoCD가 변경 감지
3. SealedSecrets 컨트롤러가 자동으로 복호화하여 일반 Secret 생성
4. Pod가 Secret을 마운트

## 백업 및 복구

### 공개 키 백업 (중요!)

SealedSecrets 컨트롤러의 비밀 키를 백업하지 않으면, 클러스터 재설치 시 기존 SealedSecret을 복호화할 수 없습니다.

```bash
# 비밀 키 백업
kubectl get secret -n sealed-secrets \
  -l sealedsecrets.bitnami.com/sealed-secrets-key=active \
  -o yaml > sealed-secrets-key-backup.yaml

# 안전한 곳에 저장 (예: 1Password, Vault)
```

### 복구

```bash
# 새 클러스터에 비밀 키 복원
kubectl apply -f sealed-secrets-key-backup.yaml

# 컨트롤러 재시작
kubectl delete pod -n sealed-secrets -l app.kubernetes.io/name=sealed-secrets
```

## 문제 해결

### SealedSecret이 복호화되지 않음

```bash
# 컨트롤러 로그 확인
kubectl logs -n sealed-secrets -l app.kubernetes.io/name=sealed-secrets

# SealedSecret 상태 확인
kubectl describe sealedsecret observer-secrets -n observer-prod
```

### Secret이 생성되지 않음

```bash
# 네임스페이스 확인 (SealedSecret과 Secret이 동일해야 함)
kubectl get sealedsecret -n observer-prod
kubectl get secret -n observer-prod
```

### 공개 키 가져오기

```bash
# 현재 공개 키 가져오기
kubeseal --fetch-cert \
  --controller-name sealed-secrets \
  --controller-namespace sealed-secrets \
  > pub-cert.pem

# 오프라인 암호화 시 사용
kubeseal --format yaml --cert pub-cert.pem < secret.yaml > sealed-secret.yaml
```

## 보안 주의사항

1. **평문 Secret을 절대 Git에 커밋하지 마세요**
2. `.gitignore`에 `*-secret.yaml` (SealedSecret 제외) 추가
3. 비밀 키 백업을 안전하게 보관
4. Secret 값 변경 시 히스토리에서 이전 값 제거 (git filter-repo)

## 참고 링크

- [SealedSecrets GitHub](https://github.com/bitnami-labs/sealed-secrets)
- [공식 문서](https://sealed-secrets.netlify.app/)
