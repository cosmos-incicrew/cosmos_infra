#!/usr/bin/env bash
set -euo pipefail

readonly project_id="${1:-kt-tech-up-01}"

put() {
  local id="$1" value="$2"
  printf '%s' "$value" | gcloud secrets versions add "$id" \
    --project="$project_id" \
    --data-file=-
}

prompt() {
  local label="$1" value
  read -r -s -p "$label: " value
  echo >&2
  printf '%s' "$value"
}

random_b64() { openssl rand -base64 32 | tr -d '\n'; }
random_hex() { openssl rand -hex 32; }

put cosmos-supabase-url "$(prompt SUPABASE_URL)"
put cosmos-supabase-service-role-key "$(prompt SUPABASE_SERVICE_ROLE_KEY)"
put cosmos-kakao-admin-key "$(prompt KAKAO_ADMIN_KEY)"
put cosmos-docs-basic-auth-hash "$(prompt 'Caddy bcrypt hash')"
put cosmos-langfuse-public-key "lf_pk_$(random_hex)"
put cosmos-langfuse-secret-key "lf_sk_$(random_hex)"
put cosmos-langfuse-disable-signup false
put cosmos-langfuse-nextauth-secret "$(random_b64)"
put cosmos-langfuse-salt "$(random_b64)"
put cosmos-langfuse-encryption-key "$(random_hex)"
put cosmos-langfuse-postgres-password "$(random_hex)"
put cosmos-langfuse-clickhouse-password "$(random_hex)"
put cosmos-langfuse-redis-password "$(random_hex)"
put cosmos-langfuse-minio-password "$(random_hex)"
put cosmos-langfuse-init-user-email "$(prompt 'Langfuse admin email')"
put cosmos-langfuse-init-user-password "$(prompt 'Langfuse admin password')"

echo "Development secret versions created."
