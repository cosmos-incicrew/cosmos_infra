# cosmos_infra

Cosmos 개발 환경의 GCP 인프라와 셀프 호스팅 Langfuse를 관리한다.

## 구조

- `bootstrap/`: Terraform 원격 상태 버킷과 GitHub Workload Identity Federation
- `environments/development/`: API·Langfuse VM, 네트워크, IAM, Artifact Registry,
  Secret Manager
- `scripts/`: 최초 secret 입력과 운영 보조 스크립트
- `templates/`: VM startup, Docker Compose, Caddy 설정

기본 GCP 프로젝트는 `kt-tech-up-01`, 리전은 비용을 우선해 `us-central1`이다.

개발 단계 리소스는 API `e2-medium`, Langfuse `e2-highmem-2`로 시작한다.
Langfuse VM은 16 GiB 메모리를 확보하되 2 vCPU로 비용을 낮춘 구성이라, 팀 내부의
낮은 trace 유입량을 전제로 한다. CPU 병목이면 `e2-standard-4`, 메모리 병목이면
`e2-highmem-4` 이상으로 올린다.

## 적용 순서

```bash
gcloud auth application-default login

# 최초 한 번만: backend bucket을 만든 뒤 Terraform 관리 대상으로 import한다.
gcloud storage buckets create gs://kt-tech-up-01-cosmos-terraform-state \
  --project=kt-tech-up-01 \
  --location=us-central1 \
  --uniform-bucket-level-access \
  --public-access-prevention
terraform -chdir=bootstrap init
terraform -chdir=bootstrap import \
  google_storage_bucket.terraform_state \
  kt-tech-up-01-cosmos-terraform-state
terraform -chdir=bootstrap apply

# bootstrap output의 provider 값을 GitHub repository variable에 등록한다.
terraform -chdir=environments/development init
terraform -chdir=environments/development apply \
  -target='google_secret_manager_secret.development'
./scripts/put-development-secrets.sh kt-tech-up-01

terraform -chdir=environments/development plan -out=development.tfplan
terraform -chdir=environments/development apply development.tfplan
```

`put-development-secrets.sh`는 값을 터미널에서 숨김 입력하고 Secret Manager에 새
version으로 저장한다. Terraform state에는 secret 값이 들어가지 않는다.
`-target` 적용은 최초 secret container 생성에만 사용한다.

Caddy 문서 인증용 bcrypt hash는 평문 비밀번호와 분리해 만든다.

```bash
docker run --rm caddy:2.11.4 caddy hash-password --plaintext '팀 비밀번호'
```

Langfuse가 처음 기동되면 팀원이 각자 계정을 만든다. 가입이 끝난 즉시 아래 명령으로
신규 가입을 닫는다. 이 작업은 기존 계정의 로그인을 막지 않는다.

```bash
./scripts/close-langfuse-signup.sh
```

## GitHub 환경 변수

bootstrap 및 development output을 기준으로 `development` environment에 아래 변수를
등록한다.

- 두 저장소 공통: `GCP_PROJECT_ID`, `GCP_WORKLOAD_IDENTITY_PROVIDER`
- `cosmos_infra`: `GCP_TERRAFORM_SERVICE_ACCOUNT`, `API_URL`, `LANGFUSE_URL`
- `cosmos_server`: `GCP_DEPLOY_SERVICE_ACCOUNT`, `GCP_REGION`,
  `ARTIFACT_REPOSITORY`, `GCE_API_INSTANCE`, `GCE_API_ZONE`

변수는 plan job에서도 읽을 수 있도록 저장소 변수로 등록한다. `development`
environment에는 Owner를 required reviewer로 지정해, 저장된 plan을 확인한 뒤에만
apply job이 진행되게 한다.

## 운영

- API 배포: `cosmos_server`의 `main` CI/CD
- Langfuse 업데이트: 이 저장소의 수동 workflow
- 전체 시작/중지: 이 저장소의 수동 workflow
- DB migration: 범위 밖
- Langfuse trace 보존: OSS Public API 기반 일일 정리 작업으로 30일
- Langfuse 데이터 디스크 snapshot: 매일, 7일 보관

비용이 발생하므로 `terraform apply` 전 plan을 반드시 검토한다.
