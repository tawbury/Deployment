# 영속성 및 호스트 매핑 (PVC / HostPath)

Observer 앱의 **DB 데이터**와 **로그**가 서버 초기화(재설치·이미지 재배포) 후에도 유지되도록, K3s에서의 볼륨 설계와 호스트 경로 매핑을 정리한 문서입니다.

## 목표

- DB 데이터: 서버의 `/home/ubuntu/data/observer/db` (또는 동일한 호스트 경로)에 영속 저장
- 로그: 서버의 `/home/ubuntu/data/observer/logs`에 영속 저장
- 777 등 과도한 권한 사용 금지, Secret으로 민감 정보 관리

## 1. 표준 PVC (StorageClass 사용)

현재 매니페스트는 **PersistentVolumeClaim**만 사용합니다. K3s 기본 StorageClass(`local-path`)를 쓰면 데이터는 보통 `/var/lib/rancher/k3s/storage/` 아래에 저장됩니다.

- **observer-db-pvc**: PostgreSQL 전용 (10Gi). Postgres Deployment의 `/var/lib/postgresql/data`에 마운트되며, 실제 서버 `/home/ubuntu/data/db` 매핑 시 이 PVC를 해당 PV에 연결합니다.
- **observer-logs-pvc**: Observer 앱 로그 (5Gi). Observer Deployment의 `/opt/platform/runtime/observer/logs`에 마운트됩니다.
- **observer-data-pvc**: Observer JSONL 데이터 (20Gi). `/opt/platform/runtime/observer/data`에 마운트됩니다.
- **observer-universe-pvc**: Universe 스냅샷 (1Gi). `/opt/platform/runtime/observer/universe`에 마운트됩니다.

서버를 초기화하면 이 경로도 함께 날아갈 수 있으므로, **데이터를 반드시 호스트의 고정 경로에 두고 싶다면** 아래 HostPath 방식을 사용하세요.

## 2. HostPath 기반 영속화 (권장: 서버 재설치 대비)

DB와 로그를 **서버의 `/home/ubuntu/data` 하위**에 두려면, PersistentVolume(PV)을 HostPath로 만들고 PVC가 이를 바라보게 합니다.

### 2.1 호스트 디렉터리 구조

서버(노드)에서 다음 디렉터리를 미리 생성하고, **권한은 755 등 필요한 최소 권한만** 부여합니다 (777 사용 금지).

```text
/home/ubuntu/data/
├── observer/
│   ├── db/      # DB 데이터 (또는 postgres 데이터 디렉터리)
│   └── logs/    # Observer 앱 로그
```

생성 예시 (서버에서):

```bash
sudo mkdir -p /home/ubuntu/data/observer/db /home/ubuntu/data/observer/logs
sudo chown -R 1000:1000 /home/ubuntu/data/observer   # Pod에서 사용할 UID/GID에 맞게 조정
sudo chmod 755 /home/ubuntu/data/observer
sudo chmod 750 /home/ubuntu/data/observer/db /home/ubuntu/data/observer/logs
```

### 2.2 PV + PVC 예시 (HostPath)

**PersistentVolume** (클러스터당 1회 적용, 노드 경로 직접 참조):

```yaml
# observer-db-pv.yaml (HostPath용)
apiVersion: v1
kind: PersistentVolume
metadata:
  name: observer-db-pv
  labels:
    app: observer
spec:
  capacity:
    storage: 10Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: observer-hostpath
  hostPath:
    path: /home/ubuntu/data/observer/db
    type: DirectoryOrCreate
---
# observer-logs-pv.yaml (HostPath용)
apiVersion: v1
kind: PersistentVolume
metadata:
  name: observer-logs-pv
  labels:
    app: observer
spec:
  capacity:
    storage: 5Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: observer-hostpath
  hostPath:
    path: /home/ubuntu/data/observer/logs
    type: DirectoryOrCreate
```

**PVC**는 해당 StorageClass를 요청하도록 overlay에서 패치합니다:

```yaml
# overlays/production/patches/pvc-storageclass.yaml (예시)
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: observer-db-pvc
spec:
  storageClassName: observer-hostpath
  # resources 등은 base와 동일
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: observer-logs-pvc
spec:
  storageClassName: observer-hostpath
```

적용 순서:

1. 호스트에 `/home/ubuntu/data/observer/db`, `/home/ubuntu/data/observer/logs` 생성 및 권한 설정
2. PV 적용: `kubectl apply -f observer-db-pv.yaml -f observer-logs-pv.yaml`
3. base/overlay로 Deployment·PVC 적용: `kubectl apply -k overlays/production`

### 2.3 단일 노드(K3s 1대)에서의 주의사항

- HostPath는 **해당 노드에만** 존재합니다. Pod가 다른 노드로 옮겨가면 해당 노드의 경로가 비어 있을 수 있으므로, 단일 노드이거나 고정 노드에만 스케줄되도록 nodeSelector/테인트를 두는 것이 안전합니다.
- `persistentVolumeReclaimPolicy: Retain`으로 두면 PVC를 지워도 PV와 호스트 디렉터리 데이터는 삭제되지 않습니다. 필요 시 수동으로 PV를 삭제하고 디렉터리를 정리하세요.

## 3. 매핑 요약

| 용도 | Pod / 컨테이너 마운트 경로 | 호스트 경로 (HostPath 사용 시) | PVC 이름 |
|------|--------------------------|-------------------------------|----------|
| DB | Postgres: `/var/lib/postgresql/data` | /home/ubuntu/data/observer/db | observer-db-pvc |
| JSONL 데이터 | Observer: `/opt/platform/runtime/observer/data` | /home/ubuntu/data/observer/data | observer-data-pvc |
| 로그 | Observer: `/opt/platform/runtime/observer/logs` | /home/ubuntu/data/observer/logs | observer-logs-pvc |
| Universe | Observer: `/opt/platform/runtime/observer/universe` | /home/ubuntu/data/observer/universe | observer-universe-pvc |
| Config | Observer: `/opt/platform/runtime/observer/config` | hostPath 직접 (PVC 미사용) | N/A |

## 4. 보안 원칙

- 호스트 디렉터리 권한: **755/750** 수준으로 제한, **777 사용 금지**
- DB 비밀번호·API 키 등은 Kubernetes **Secret**으로만 관리하고, Git에는 넣지 않음
- Secret 생성 가이드: `infra/k8s/base/secrets/observer-secrets.yaml` 주석 참고
