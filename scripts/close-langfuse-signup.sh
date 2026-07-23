#!/usr/bin/env bash
set -euo pipefail

readonly project_id="${1:-kt-tech-up-01}"
readonly zone="${2:-us-central1-a}"
readonly instance="cosmos-langfuse-dev"

printf 'true' | gcloud secrets versions add cosmos-langfuse-disable-signup \
  --project="$project_id" \
  --data-file=-

gcloud compute ssh "$instance" \
  --project="$project_id" \
  --zone="$zone" \
  --tunnel-through-iap \
  --command='sudo bash -ceu '"'"'
    sed -i "s/^AUTH_DISABLE_SIGNUP=.*/AUTH_DISABLE_SIGNUP=true/" /opt/langfuse/.env
    cd /opt/langfuse
    docker compose --env-file .env -f compose.yml up -d --force-recreate langfuse-web
    grep "^AUTH_DISABLE_SIGNUP=true$" .env
  '"'"''

echo "Langfuse public signup is closed; existing accounts can still sign in."
