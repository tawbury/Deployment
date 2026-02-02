# k3s 클러스터 관리 스크립트

k3s(경량 Kubernetes) 클러스터 설치, 관리, 백업을 위한 스크립트입니다.

## 스크립트 목록

| 스크립트 | 용도 |
|---------|------|
| `install.sh` | k3s 서버 노드 설치 |
| `join-agent.sh` | 워커 노드 추가 |
| `backup.sh` | etcd 스냅샷 백업 |

## 사용법

### 1. 서버 노드 설치

```bash
# 단일 노드 클러스터
sudo ./install.sh

# HA 클러스터 첫 번째 노드 (내장 etcd)
sudo ./install.sh --cluster-init
```

설치 후 확인:
```bash
kubectl get nodes
kubectl get pods -A
```

### 2. 워커 노드 추가

서버에서 토큰 확인:
```bash
sudo cat /var/lib/rancher/k3s/server/node-token
```

워커 노드에서 실행:
```bash
sudo ./join-agent.sh <서버IP> <토큰>
```

### 3. 백업

```bash
# 로컬 백업
sudo ./backup.sh

# S3 백업
export AWS_ACCESS_KEY_ID=...
export AWS_SECRET_ACCESS_KEY=...
export S3_BUCKET=my-backup-bucket
sudo ./backup.sh --s3
```

### 4. kubeconfig 설정 (로컬 머신)

```bash
# 서버에서 kubeconfig 복사
scp root@<서버IP>:/etc/rancher/k3s/k3s.yaml ~/.kube/config

# 서버 주소 변경
sed -i 's/127.0.0.1/<서버IP>/g' ~/.kube/config

# 권한 설정
chmod 600 ~/.kube/config
```

## k3s 주요 명령어

```bash
# 서비스 상태
sudo systemctl status k3s

# 로그 확인
sudo journalctl -u k3s -f

# k3s 중지/시작
sudo systemctl stop k3s
sudo systemctl start k3s

# k3s 삭제 (주의!)
sudo /usr/local/bin/k3s-uninstall.sh
```

## 관련 문서

- [k3s 공식 문서](https://docs.k3s.io/)
- [Deploy Architecture](../../../docs/arch/deploy_architecture.md)
