# OCI 전용 스크립트

Oracle Cloud Infrastructure(OCI) 배포·프로비저닝·동기화에만 사용하는 스크립트입니다. 공통 스크립트는 `infra/_shared/scripts/`를 사용합니다.

## 스크립트

| 파일 | 설명 |
|------|------|
| **sync_to_oracle.ps1** | 로컬 workspace(infra + app)를 OCI VM으로 동기화 후 docker compose 실행. Bootstrap 시 oracle_bootstrap.sh 호출 |
| **oci_helpers.ps1** | OCI 인스턴스 조회/종료 헬퍼 (Get-OciInstanceByName, Remove-OciInstanceByName) |
| **oci_launch_instance.ps1** | OCI Compute 인스턴스 생성 (cloud-init-docker.yaml 사용) |
| **oracle_bootstrap.sh** | VM에서 Docker Engine + Compose v2 설치 (Oracle Linux / RHEL / Ubuntu 등) |
| **cloud-init-docker.yaml** | OCI 인스턴스용 cloud-init (opc 사용자, Docker+Compose 준비) |

## 사용 시점

- **현재 배포**: OCI VM 기준. 로컬에서 `pwsh -File infra/oci_deploy/scripts/sync_to_oracle.ps1` 실행 시 프로젝트 루트가 작업 디렉터리여야 합니다.
- **레거시(Azure)**: `infra/_shared/scripts/deploy/deploy.ps1` 에서 `-SshUser`, `-DeployDir` 등으로 Azure VM 대상 지정 가능.

## 실행 경로

프로젝트 루트에서:

```powershell
# OCI VM 동기화 및 compose 기동
pwsh -File infra/oci_deploy/scripts/sync_to_oracle.ps1 -HostName "10.0.0.12" -User "opc"

# OCI 인스턴스 생성 (cloud-init 사용)
pwsh -ExecutionPolicy Bypass -File infra/oci_deploy/scripts/oci_launch_instance.ps1 `
  -CompartmentId "ocid1.compartment.oc1..xxxx" `
  -SubnetId "ocid1.subnet.oc1..yyyy" `
  -ImageId "ocid1.image.oc1..zzzz" `
  -DisplayName "observer-vm"
```

sync_to_oracle.ps1은 원격에 `infra`·`app`만 복사하며, 스크립트는 `infra/oci_deploy/scripts/`·`infra/_shared/scripts/`에 포함된 구조로 함께 전달됩니다. Bootstrap 필요 시 원격에서 `$RemoteBase/infra/oci_deploy/scripts/oracle_bootstrap.sh`를 실행합니다.
