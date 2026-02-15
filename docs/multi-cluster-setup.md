# 멀티 클러스터 설정 가이드

## 개요

QTS 플랫폼은 세 개의 서버에 걸쳐 운영됩니다:

| 서버 | 역할 | 클러스터 | 상태 |
|------|------|---------|------|
| OCI #1 | QTS + Observer + ArgoCD | K3s (ARM64) | 운영 중 |
| OCI #2 | n8n (모니터링/자동화) | K3s (ARM64) | 신규 예정 |
| GCP e2-micro | 헬스체크 백업 | K3s | 운영 중 (임시 스테이징) |

**핵심 원칙**: 감시자(n8n)와 감시 대상(QTS/Observer)은 반드시 별도 서버에서 운영합니다.

## ArgoCD 멀티 클러스터 등록

### 사전 준비

1. OCI #2에 K3s가 설치되어 있어야 합니다
2. OCI #1 → OCI #2 간 네트워크 통신이 가능해야 합니다 (6443 포트)
3. OCI #1에서 ArgoCD CLI가 인증된 상태여야 합니다

### 1단계: OCI #2 K3s kubeconfig 가져오기

OCI #2 서버에서:
```bash
# K3s kubeconfig 확인
sudo cat /etc/rancher/k3s/k3s.yaml

# 외부 접근용 kubeconfig 생성 (server 주소를 외부 IP로 변경)
sudo k3s kubectl config view --raw | \
  sed "s/127.0.0.1/<OCI_2_EXTERNAL_IP>/g" > /tmp/oci2-kubeconfig.yaml
```

### 2단계: OCI #1에서 OCI #2 컨텍스트 추가

OCI #1 서버에서:
```bash
# OCI #2 kubeconfig를 로컬로 복사
scp <OCI2_USER>@<OCI2_HOST>:/tmp/oci2-kubeconfig.yaml /tmp/

# kubeconfig 병합
export KUBECONFIG=~/.kube/config:/tmp/oci2-kubeconfig.yaml
kubectl config view --merge --flatten > /tmp/merged-config.yaml
cp ~/.kube/config ~/.kube/config.bak
mv /tmp/merged-config.yaml ~/.kube/config

# 컨텍스트 확인
kubectl config get-contexts
```

### 3단계: ArgoCD에 클러스터 등록

```bash
# ArgoCD CLI 로그인 (이미 인증되어 있다면 생략)
argocd login <ARGOCD_SERVER> --grpc-web

# OCI #2 클러스터 등록
# <CONTEXT_NAME>은 kubectl config get-contexts에서 확인한 OCI #2 컨텍스트 이름
argocd cluster add <CONTEXT_NAME> --name oci-2

# 등록 확인
argocd cluster list
```

### 4단계: ArgoCD Application 업데이트

`infra/argocd/applications/oci-2-n8n.yaml`에서 `destination.server`를
실제 OCI #2 API 서버 주소로 변경합니다:

```yaml
spec:
  destination:
    server: https://<OCI_2_K3S_API_주소>:6443  # ← 실제 주소로 변경
    namespace: n8n
```

## 방화벽 설정

### OCI #2 서버

```bash
# K3s API 서버 포트 (OCI #1에서만 접근 허용)
sudo iptables -A INPUT -p tcp --dport 6443 -s <OCI_1_IP> -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 6443 -j DROP

# n8n 웹 포트 (필요 시)
sudo iptables -A INPUT -p tcp --dport 443 -j ACCEPT
```

### OCI Security List (OCI 콘솔)

OCI #2 서브넷의 Security List에 다음 Ingress 규칙 추가:

| 프로토콜 | 소스 | 포트 | 설명 |
|---------|------|------|------|
| TCP | OCI #1 IP/32 | 6443 | K3s API (ArgoCD 연결) |
| TCP | 0.0.0.0/0 | 443 | HTTPS (n8n 웹 접근) |

## 클러스터별 배포 확인

### OCI #1 (QTS/Observer)

```bash
# ArgoCD 대시보드에서 확인
argocd app list

# kubectl로 직접 확인
kubectl get pods -n observer-prod
kubectl get pods -n argocd
```

### OCI #2 (n8n)

```bash
# ArgoCD에서 원격 클러스터 앱 확인
argocd app get n8n

# OCI #2에 직접 접속하여 확인
kubectl --context <OCI_2_CONTEXT> get pods -n n8n

# 또는 OCI #2 서버에서 직접
kubectl get pods -n n8n
helm status n8n -n n8n
```

## 트러블슈팅

### 연결 실패: ArgoCD → OCI #2

**증상**: ArgoCD에서 n8n 앱이 `Unknown` 상태
```
Error: Cluster connection failed: dial tcp <IP>:6443: connect: connection refused
```

**해결 방법**:
1. OCI #2에서 K3s가 실행 중인지 확인:
   ```bash
   sudo systemctl status k3s
   ```
2. 방화벽에서 6443 포트가 열려 있는지 확인:
   ```bash
   # OCI #1에서 테스트
   nc -zv <OCI_2_IP> 6443
   ```
3. ArgoCD 클러스터 등록 상태 확인:
   ```bash
   argocd cluster list
   argocd cluster get oci-2
   ```

### 인증 오류

**증상**: `Unauthorized` 또는 인증서 오류
```
Error: the server has asked for the client to provide credentials
```

**해결 방법**:
1. OCI #2의 K3s 토큰이 변경되었을 수 있음:
   ```bash
   # OCI #2에서 토큰 확인
   sudo cat /var/lib/rancher/k3s/server/token
   ```
2. ArgoCD 클러스터를 재등록:
   ```bash
   argocd cluster rm oci-2
   argocd cluster add <CONTEXT_NAME> --name oci-2
   ```

### 인증서 만료

**증상**: TLS 핸드셰이크 실패

**해결 방법**:
```bash
# OCI #2에서 K3s 인증서 갱신
sudo k3s certificate rotate
sudo systemctl restart k3s

# ArgoCD 클러스터 재등록
argocd cluster rm oci-2
argocd cluster add <CONTEXT_NAME> --name oci-2
```

### n8n Pod CrashLoopBackOff

**확인 순서**:
1. Pod 로그 확인:
   ```bash
   kubectl logs -n n8n -l app.kubernetes.io/name=n8n --tail=50
   ```
2. Secret 주입 확인 (N8N_ENCRYPTION_KEY):
   ```bash
   kubectl get secret -n n8n
   ```
3. PVC 바인딩 확인:
   ```bash
   kubectl get pvc -n n8n
   ```
