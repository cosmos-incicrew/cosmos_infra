# cosmos_infra

Cosmos 개발 환경의 GCP 인프라와 셀프 호스팅 Langfuse를 관리하는 저장소입니다.

백엔드 API와 Langfuse는 서로 다른 GCE VM에서 실행합니다. 비용과 성능의 균형을
고려해 개발 단계에서는 작은 사양으로 시작하지만, 저장소와 배포 구조는 실제 운영
환경에서도 확장할 수 있는 형태를 따릅니다.

> **현재는 팀 내부 개발·테스트 환경입니다.**
> API와 Langfuse는 외부 네트워크에서도 접속할 수 있으며, 고정 IP와 `nip.io` 주소를
> 사용하므로 팀원의 접속 IP가 바뀌어도 별도 허용 목록을 수정할 필요가 없습니다.
> `terraform apply`를 실행하면 GCP 비용이 발생합니다.
>
> 저장소에는 인프라 구성이 준비되어 있지만, 아직 실제 GCP 리소스는 만들지 않은
> 상태입니다. 백엔드 자동 배포도 `cosmos_server`의 배포 변경이 `main`에 반영된
> 뒤부터 동작합니다.

## 구성

| 구분 | 기본값 | 역할 |
|---|---|---|
| GCP 프로젝트 | `kt-tech-up-01` | Vertex AI와 개발 인프라를 함께 운영 |
| 리전 / 영역 | `us-central1` / `us-central1-a` | 개발 단계의 비용을 우선한 위치 |
| API VM | `e2-medium` | FastAPI 백엔드와 Caddy 실행 |
| Langfuse VM | `e2-highmem-2` | Langfuse와 PostgreSQL, ClickHouse, Redis, MinIO 실행 |
| 컨테이너 저장소 | Artifact Registry | 백엔드 Docker 이미지 저장 |
| 비밀값 | Secret Manager | API와 Langfuse가 사용하는 설정값 보관 |
| Terraform 상태 | Cloud Storage | 로컬과 GitHub Actions가 같은 상태를 사용 |
| GitHub 인증 | Workload Identity Federation | 장기 서비스 계정 키 없이 GCP에 접근 |

API와 Langfuse VM은 각각 고정 외부 IP를 사용합니다. 별도 도메인을 구매하지 않은
상태이므로 주소는 다음과 같은 형태로 자동 생성됩니다.

```text
https://api.<고정-IP의 점을 하이픈으로 바꾼 값>.nip.io
https://langfuse.<고정-IP의 점을 하이픈으로 바꾼 값>.nip.io
```

API 문서(`/docs`, `/redoc`, `/openapi.json`)에는 Caddy Basic Auth가 적용됩니다.
일반 API 요청과 Langfuse 로그인은 각 서비스의 인증 방식을 그대로 사용합니다.

## 폴더 구조

```text
cosmos_infra/
├─ bootstrap/                  # 원격 상태 버킷과 GitHub-GCP 인증 기반
├─ environments/development/  # 개발 환경의 VM, 네트워크, IAM, 저장소와 Secret
├─ scripts/                    # 최초 Secret 등록과 운영 보조 명령
├─ templates/                  # VM 시작 스크립트, Docker Compose와 Caddy 설정
└─ tests/                      # 운영 스크립트 테스트
```

`bootstrap`은 나머지 인프라를 안전하게 관리하기 위한 기반입니다. 최초 한 번만 로컬에서
적용한 뒤, 일반적인 인프라 변경은 GitHub Actions의 검토 절차를 통해 적용합니다.

## 준비 사항

최초 배포를 진행하는 사람은 다음 도구와 권한이 필요합니다.

- Terraform `1.15.8`
- Google Cloud CLI(`gcloud`)
- Docker(Caddy 비밀번호 해시를 만들 때 사용)
- `kt-tech-up-01` 프로젝트를 관리할 수 있는 Google Cloud 권한
- GitHub 조직 `cosmos-incicrew`의 저장소와 Environment 설정 권한

아래 명령은 이 저장소의 루트에서 실행합니다. 먼저 Google Cloud의 Application Default
Credentials로 로그인합니다.

```bash
gcloud auth login
gcloud auth application-default login
gcloud config set project kt-tech-up-01
```

## 최초 배포

최초 배포는 세 단계로 진행합니다.

### 1. Terraform 기반 만들기

Terraform 상태 버킷은 Terraform 초기화보다 먼저 필요하므로, 버킷만 직접 만든 뒤
곧바로 Terraform 관리 대상으로 가져옵니다.

```bash
gcloud storage buckets create gs://kt-tech-up-01-cosmos-terraform-state \
  --project=kt-tech-up-01 \
  --location=us-central1 \
  --uniform-bucket-level-access \
  --public-access-prevention

terraform -chdir=bootstrap init
terraform -chdir=bootstrap import \
  google_storage_bucket.terraform_state \
  kt-tech-up-01-cosmos-terraform-state
terraform -chdir=bootstrap plan
terraform -chdir=bootstrap apply
```

적용이 끝나면 필요한 GCP API, Terraform 서비스 계정, GitHub Workload Identity
Federation이 준비됩니다. 다음 명령으로 GitHub에 등록할 값을 확인할 수 있습니다.

```bash
terraform -chdir=bootstrap output
```

> 상태 버킷이 이미 존재하고 Terraform에도 등록되어 있다면 생성과 `import`를 다시
> 실행하지 않습니다.

### 2. Secret 등록하기

VM을 만들기 전에 Secret Manager의 컨테이너를 먼저 생성하고 실제 값을 넣습니다.
이 단계의 `-target`은 최초 Secret 생성에만 사용합니다.

```bash
terraform -chdir=environments/development init
terraform -chdir=environments/development apply \
  -target='google_secret_manager_secret.development'
```

API 문서에 사용할 비밀번호는 평문과 별도로 bcrypt 해시를 만듭니다.

```bash
docker run --rm caddy:2.11.4 \
  caddy hash-password --plaintext '팀 비밀번호'
```

이제 Secret을 등록합니다. 스크립트는 Supabase 값, Kakao Admin 키, 위에서 만든 Caddy
해시와 Langfuse 관리자 계정을 차례로 묻습니다. 입력값은 화면에 표시되지 않습니다.

```bash
./scripts/put-development-secrets.sh kt-tech-up-01
```

Langfuse 내부 암호화 키와 데이터베이스 비밀번호는 스크립트가 안전한 무작위 값으로
만듭니다. 실제 Secret 값은 Terraform 코드나 상태 파일에 저장되지 않습니다.

### 3. 개발 환경 만들기

전체 변경 내용을 먼저 확인한 다음, 저장된 계획 파일을 그대로 적용합니다.

```bash
terraform -chdir=environments/development plan -out=development.tfplan
terraform -chdir=environments/development apply development.tfplan
```

완료 후 생성된 접속 주소와 GitHub 설정값을 확인합니다.

```bash
terraform -chdir=environments/development output
```

VM의 시작 스크립트가 Docker와 서비스를 준비하므로, 최초 기동에는 몇 분이 걸릴 수
있습니다.

## GitHub Actions 연결

GitHub Actions는 서비스 계정 키 파일을 저장하지 않습니다. `bootstrap`에서 만든
Workload Identity Federation을 통해 필요한 순간에만 GCP 권한을 얻습니다.

각 저장소의 GitHub `Settings → Secrets and variables → Actions → Variables`에 다음
값을 등록합니다. 값은 `terraform output` 결과에서 가져옵니다.

| 저장소 | 변수 |
|---|---|
| 공통 | `GCP_PROJECT_ID`, `GCP_WORKLOAD_IDENTITY_PROVIDER` |
| `cosmos_infra` | `GCP_TERRAFORM_SERVICE_ACCOUNT`, `API_URL`, `LANGFUSE_URL` |
| `cosmos_server` | `GCP_DEPLOY_SERVICE_ACCOUNT`, `GCP_REGION`, `ARTIFACT_REPOSITORY`, `GCE_API_INSTANCE`, `GCE_API_ZONE` |

변수는 `plan` 작업에서도 읽을 수 있도록 저장소 변수로 등록합니다.

`cosmos_infra`와 `cosmos_server`에는 `development` Environment를 만들고 저장소
Owner를 required reviewer로 지정합니다. 인프라 `apply`와 백엔드 배포는 이 검토를
통과한 뒤에만 진행됩니다.

## 배포와 운영

### 백엔드 배포

`cosmos_server`의 `main` 브랜치에 변경이 반영되면 CI가 백엔드 이미지를 빌드하고
검증합니다. 승인 후 이미지를 Artifact Registry에 올리고 API VM에 배포합니다.

이번 자동 배포 범위에는 백엔드 서버만 포함합니다. DB migration은 자동으로 실행하지
않습니다.

### 인프라 변경

인프라 변경은 `Infrastructure plan or apply` 워크플로에서 수동으로 실행합니다.

- `plan`: 변경될 리소스만 확인하며 실제 인프라는 수정하지 않습니다.
- `apply`: 같은 실행에서 만든 plan을 저장한 뒤, `development` Environment 승인을
  거쳐 적용합니다.

비용이나 데이터에 영향을 줄 수 있으므로 `apply` 승인 전에 생성·변경·삭제되는
리소스를 확인합니다.

### VM 시작·정지

기본 운영은 24시간 가동입니다. 사용하지 않는 기간에는 `Development environment
control` 워크플로에서 두 VM을 함께 관리할 수 있습니다.

- `status`: 현재 VM 상태 확인
- `start`: Langfuse를 먼저 시작하고 준비가 끝나면 API 시작
- `stop`: API를 먼저 중지한 뒤 Langfuse 중지

VM을 정지하면 컴퓨팅 비용은 줄어들지만 디스크, 고정 IP, 스냅샷 등 일부 비용은 계속
발생합니다. 다시 시작해도 고정 IP와 접속 주소는 유지됩니다.

### Langfuse 가입 닫기

Langfuse가 처음 기동되면 팀원이 각자 계정을 만듭니다. 필요한 계정을 모두 만든 직후
아래 명령으로 신규 가입을 닫습니다.

```bash
./scripts/close-langfuse-signup.sh
```

신규 가입만 막히며 기존 계정은 계속 로그인할 수 있습니다.

### Langfuse 데이터 관리

- trace는 OSS Public API를 이용한 일일 정리 작업으로 30일 동안 보관합니다.
- Langfuse 데이터 디스크는 매일 스냅샷을 만들고 7일 동안 보관합니다.
- Langfuse 버전을 올릴 때는 Terraform의 `langfuse_image_tag`를 변경하고 인프라
  plan과 apply 절차를 따릅니다.

## 배포 확인

Terraform output에서 확인한 주소로 상태를 점검합니다.

```bash
api_url="$(terraform -chdir=environments/development output -raw api_url)"
langfuse_url="$(terraform -chdir=environments/development output -raw langfuse_url)"

curl "$api_url/health"
curl "$api_url/health/ready"
curl "$langfuse_url/api/public/health"
```

- `/health`가 실패하면 API 컨테이너 또는 Caddy 기동 상태를 확인합니다.
- `/health/ready`만 실패하면 Supabase 연결과 Secret 값을 확인합니다.
- Langfuse health가 실패하면 Langfuse VM과 Docker Compose 상태를 확인합니다.

VM에 직접 접속해야 할 때는 외부 SSH 포트를 열지 않고 IAP 터널을 사용합니다.

```bash
gcloud compute ssh cosmos-api-dev \
  --project=kt-tech-up-01 \
  --zone=us-central1-a \
  --tunnel-through-iap

gcloud compute ssh cosmos-langfuse-dev \
  --project=kt-tech-up-01 \
  --zone=us-central1-a \
  --tunnel-through-iap
```

## 기본 리소스와 비용 원칙

개발 단계는 API `e2-medium`, Langfuse `e2-highmem-2`로 시작합니다. Langfuse VM은
16 GiB 메모리와 2 vCPU를 사용하며, 팀 내부의 낮은 trace 유입량을 전제로 한
가성비 중심 구성입니다.

운영 중 CPU가 병목이면 `e2-standard-4`, 메모리가 병목이면 `e2-highmem-4` 이상을
검토합니다. 리소스 사양은 실제 사용량을 확인한 뒤 올리며, 구조는 API와 관측 환경을
분리한 현재 형태를 유지합니다.

인프라를 완전히 제거할 때는 VM뿐 아니라 데이터 디스크와 스냅샷의 보존 여부도 함께
확인해야 합니다. Terraform 삭제 작업은 데이터 손실 가능성이 있으므로 plan 검토 없이
실행하지 않습니다.
