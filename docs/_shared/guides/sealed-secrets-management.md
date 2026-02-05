# Sealed Secrets 관리 가이드: 초보자도 쉬운 완결판 (IT Communicator Edition)

어려워 보이지만 하나씩 따라 하면 무조건 성공합니다! 이 가이드는 **1인 관리자**가 클라우드 서버와 내 컴퓨터를 오가며 안전하게 비밀번호(시크릿)를 관리하는 방법을 설명합니다.

### 💡 핵심 개념 비유로 이해하기
*   **동네 (Namespace)**: 서버 안의 가상의 동네입니다. 우리 프로젝트는 `qts`라는 동네에서 작동합니다.
*   **암호화된 봉투 (Sealed Secret)**: 겉에서 내용을 볼 수 없게 꽁꽁 싸맨 봉투입니다. Git에 올려도 안전합니다.
*   **집사 (Controller)**: 서버에 살고 있는 똑똑한 관리자입니다. 암호화된 봉투를 받으면 열어서 실제 비밀번호로 바꿔줍니다.

---

## 📋 [준비물]
*   **SSH 키**: `C:\Users\tawbu\.ssh\oracle-obs-vm-01.key` (서버 문을 여는 열쇠)
*   **컴퓨터 도구**: 내 컴퓨터에 `kubectl`과 `kubeseal`이 설치되어 있어야 합니다.

---

## Step 0. 우리 서버 상태 파악하기 ☁️ [서버에서 하세요]

먼저 서버에 접속해서 우리 집사가 어디 있는지, 열쇠(인증서)는 무엇인지 확인합니다.

```bash
# 1. 서버 접속 (내 컴퓨터 터미널에서 실행)
ssh -i "C:\Users\tawbu\.ssh\oracle-obs-vm-01.key" ubuntu@oracle-obs-vm-01

# 2. 우리 동네(qts)가 있는지 확인
kubectl get ns  # qts 라는 이름이 목록에 있는지 봅니다.

# 3. 집사(Controller) 찾기
kubectl get pods -A | grep sealed  # 'sealed-secrets-controller'가 작동 중인지 확인합니다.

# 4. 암호화 열쇠(Cert) 추출
kubeseal --fetch-cert \
  --controller-name sealed-secrets \
  --controller-namespace sealed-secrets \
  > pub-cert.pem  # 현재 위치에 열쇠 파일을 만듭니다.

# 5. [중요] 파일이 진짜 있는지 확인!
ls -l pub-cert.pem  # 파일 크기가 0이 아닌지 확인하세요.
```

---

## Step 1. 암호화 열쇠 내 컴퓨터로 가져오기 🔑 [내 컴퓨터에서 하세요]

서버에서 만든 열쇠(`pub-cert.pem`)를 내 컴퓨터로 가져와야 합니다.

### 방법 A: SCP로 자동 가져오기
```bash
# 내 컴퓨터 터미널에서 실행 (서버 x)
scp -i "C:\Users\tawbu\.ssh\oracle-obs-vm-01.key" ubuntu@oracle-obs-vm-01:~/pub-cert.pem ./
```

> [!CAUTION]
> **"No such file or directory" 에러가 나나요?**
> 서버에서 `pub-cert.pem`을 만들 때 경로가 달랐을 수 있습니다. 서버에서 `pwd` 명령어로 현재 위치를 확인한 후, 그 경로를 `scp` 명령어의 `~/` 대신 넣어보세요. (예: `/home/ubuntu/pub-cert.pem`)

### 방법 B: 수동으로 복사하기 (안전한 대안)
전송이 자꾸 실패한다면 그냥 텍스트를 복사해서 새로 만드세요.
1. **(서버)** `cat pub-cert.pem` 실행 -> 화면에 나오는 글자들을 모두 드래그해서 복사.
2. **(내 컴퓨터)** 메모장을 켜고 붙여넣기 -> 파일을 `pub-cert.pem`이라는 이름으로 저장.

---

## Step 2. 안전하게 암호화 봉투 만들기 ✉️ [내 컴퓨터에서 하세요]

**보안 주의**: 비밀번호는 절대 서버에서 직접 치지 마세요! 내 컴퓨터에서 봉투를 만든 후 봉투만 서버로 보낼 겁니다.

### 실전 예시: DB 비밀번호 봉투 만들기
```bash
# 1. 내 컴퓨터 터미널에서 실행
kubectl create secret generic qts-db-secret \
  --from-literal=POSTGRES_USER=myuser \
  --from-literal=POSTGRES_PASSWORD=mypassword \
  --namespace qts \
  --dry-run=client -o json | \
kubeseal --format yaml --cert pub-cert.pem > qts-db-sealed-secret.yaml
# qts 동네용 DB 비밀번호를 암호화하여 봉투(.yaml)를 만들었습니다.

kubectl create secret generic obs-db-secret --from-literal=POSTGRES_USER=observer --from-literal=POSTGRES_PASSWORD=5938 --namespace observer-prod --dry-run=client -o json | kubeseal --format yaml --cert pub-cert.pem > obs-db-sealed-secret.yaml
```

```bash
# qts용 sealed secret 생성방법
# DB sealed secret
kubectl create secret generic qtss-db-secret --from-literal=POSTGRES_USER=qts --from-literal=POSTGRES_PASSWORD=**** --namespace [namespace] --dry-run=client -o json | kubeseal --format yaml --cert pub-cert.pem > qts-db-sealed-secret.yaml

# kis api key sealed secret
kubectl create secret generic qts-kis-secret --from-literal=KIS_APP_KEY=[key]--from-literal=KIS_APP_SECRET=[key] --namespace [namespace] --dry-run=client -o json | kubeseal --format yaml --cert pub-cert.pem > qts-kis-sealed-secret.yaml

# kiwoom api key sealed secret
kubectl create secret generic qts-kiwoom-secret --from-literal=KIWOOM_APP_KEY=[key]--from-literal=KIWOOM_APP_SECRET=[key] --namespace [namespace] --dry-run=client -o json | kubeseal --format yaml --cert pub-cert.pem > qts-kiwoom-sealed-secret.yaml
```

---

## Step 3. 집사에게 배달시키기 🚚 [내 컴퓨터/서버]

1.  **파일 이동**: 만든 `.yaml` 파일을 프로젝트의 `infra/k8s/base/sealed-secrets/` 폴더에 넣습니다.
2.  **Git 업로드**: `git add .`, `git commit`, `git push`를 통해 코드를 올립니다.
3.  **집사의 서빙 확인**: 서버에서 집사가 봉투를 제대로 열었는지 확인합니다.

```bash
# [서버에서 확인]
kubectl get secret -n qts  # qts-db-secret 이라는 이름이 생겼는지 확인합니다.
```

---

## 🛠️ 해결사 섹션: "안돼요! 도와주세요!"

### 에러 메시지 해석 (Bubble Commentary)
`kubectl describe sealedsecret qts-db-secret -n qts` 명령어를 쳤을 때:

*   **"cleartext secret already exists"**:
    💬 집사가 말합니다: "주인님, 이미 그 이름의 일반 비밀번호가 동네에 있어요! 제가 새 봉투를 열어서 바꿔치기할 수가 없네요."
    👉 **해결법**: 기존 시크릿을 한 번 지워주세요: `kubectl delete secret qts-db-secret -n qts`

*   **"decryption failed"**:
    💬 집사가 말합니다: "이 봉투는 제가 가진 열쇠로 열 수가 없어요. 다른 열쇠로 잠근 것 같아요."
    👉 **해결법**: Step 0부터 다시 시작해서 서버의 최신 열쇠(`pub-cert.pem`)를 다시 받아오세요.

---

> [!TIP]
> **성공 체크리스트**
> 1. 서버 열쇠를 내 컴퓨터로 가져왔나? (Step 1)
> 2. 암호화할 때 `--namespace qts`를 넣었나? (Step 2)
> 3. Git에 올린 후 집사가 일을 마쳤나? (Step 3)
