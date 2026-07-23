#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 || "$1" != *@sha256:* ]]; then
  echo "usage: deploy-api <artifact-registry-image@sha256:digest>" >&2
  exit 2
fi

exec 9>/run/lock/cosmos-api-deploy.lock
flock 9

readonly image_reference="$1"
cd /opt/cosmos

set -a
source /opt/cosmos/platform.env
set +a

metadata_token() {
  curl -fsS -H 'Metadata-Flavor: Google' \
    'http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token' |
    jq -r .access_token
}

secret() {
  local id="$1"
  curl -fsS -H "Authorization: Bearer $(metadata_token)" \
    "https://secretmanager.googleapis.com/v1/projects/$GCP_PROJECT_ID/secrets/$id/versions/latest:access" |
    jq -r .payload.data | tr '_-' '/+' | base64 -d
}

registry_host="${GCP_REGION}-docker.pkg.dev"
metadata_token | docker login -u oauth2accesstoken --password-stdin "https://${registry_host}"
docker pull "$image_reference"

umask 077
install -d -m 0700 /run/cosmos
{
  printf 'SUPABASE_URL=%s\n' "$(secret cosmos-supabase-url)"
  printf 'SUPABASE_SERVICE_ROLE_KEY=%s\n' "$(secret cosmos-supabase-service-role-key)"
  printf 'KAKAO_ADMIN_KEY=%s\n' "$(secret cosmos-kakao-admin-key)"
  printf 'GEMINI_API_KEY=\n'
  printf 'GCP_PROJECT_ID=%s\n' "$GCP_PROJECT_ID"
  printf 'GCP_LOCATION=global\n'
  printf 'LANGFUSE_PUBLIC_KEY=%s\n' "$(secret cosmos-langfuse-public-key)"
  printf 'LANGFUSE_SECRET_KEY=%s\n' "$(secret cosmos-langfuse-secret-key)"
  printf 'LANGFUSE_BASE_URL=%s\n' "$LANGFUSE_BASE_URL"
  printf 'LANGFUSE_TRACING_ENVIRONMENT=development\n'
  printf 'LANGFUSE_TRACING_RELEASE=%s\n' "${image_reference##*@}"
  printf 'LANGFUSE_TRACING_ENABLED=true\n'
  printf 'API_HOST=%s\n' "$API_HOST"
  printf 'DOCS_BASIC_AUTH_HASH=%s\n' "$(secret cosmos-docs-basic-auth-hash)"
} > /run/cosmos/api.env

previous_image=""
[[ -f current-image ]] && previous_image="$(<current-image)"
printf 'API_IMAGE=%s\nCADDY_IMAGE_TAG=%s\n' "$image_reference" "$CADDY_IMAGE_TAG" > release.env

if ! docker compose --env-file release.env -f compose.yml up -d --remove-orphans; then
  deploy_failed=true
else
  deploy_failed=false
  for _ in $(seq 1 30); do
    if docker compose --env-file release.env -f compose.yml exec -T api \
      python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/health/ready', timeout=3)"; then
      deploy_failed=false
      break
    fi
    deploy_failed=true
    sleep 2
  done
fi

if [[ "$deploy_failed" == true ]]; then
  if [[ -n "$previous_image" ]]; then
    printf 'API_IMAGE=%s\nCADDY_IMAGE_TAG=%s\n' "$previous_image" "$CADDY_IMAGE_TAG" > release.env
    docker compose --env-file release.env -f compose.yml up -d --remove-orphans
  fi
  echo "deployment failed; previous image restored" >&2
  exit 1
fi

printf '%s' "$image_reference" > current-image
docker image prune -f
