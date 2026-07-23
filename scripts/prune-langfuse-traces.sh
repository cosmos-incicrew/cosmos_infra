#!/usr/bin/env bash
set -euo pipefail

readonly langfuse_dir="${LANGFUSE_DIR:-/opt/langfuse}"
readonly retention_days="${LANGFUSE_RETENTION_DAYS:-30}"
readonly api_base="${LANGFUSE_API_BASE:-http://127.0.0.1:3000/api/public}"
readonly public_key="$(sed -n 's/^LANGFUSE_INIT_PROJECT_PUBLIC_KEY=//p' "$langfuse_dir/.env")"
readonly secret_key="$(sed -n 's/^LANGFUSE_INIT_PROJECT_SECRET_KEY=//p' "$langfuse_dir/.env")"

if ! cutoff="$(date -u -d "$retention_days days ago" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null)"; then
  cutoff="$(date -u -v-"${retention_days}"d '+%Y-%m-%dT%H:%M:%SZ')"
fi
readonly cutoff
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT
ids_file="$work_dir/trace-ids"
: > "$ids_file"

page=1
while true; do
  response="$(curl --fail --silent --show-error \
    --user "${public_key}:${secret_key}" \
    --get "$api_base/traces" \
    --data-urlencode "toTimestamp=$cutoff" \
    --data-urlencode "fields=core" \
    --data-urlencode "orderBy=timestamp.asc" \
    --data-urlencode "limit=100" \
    --data-urlencode "page=$page")"

  jq -r ".data[].id" <<<"$response" >> "$ids_file"
  total_pages="$(jq -r ".meta.totalPages" <<<"$response")"
  ((page >= total_pages)) && break
  ((page += 1))
done

if [[ ! -s "$ids_file" ]]; then
  echo "No Langfuse traces older than $cutoff."
  exit 0
fi

split -l 50 "$ids_file" "$work_dir/batch-"
deleted=0
for batch in "$work_dir"/batch-*; do
  payload="$(jq -Rn '[inputs] | {traceIds: .}' < "$batch")"
  count="$(wc -l < "$batch" | tr -d ' ')"
  curl --fail --silent --show-error \
    --user "${public_key}:${secret_key}" \
    --request DELETE \
    --header "Content-Type: application/json" \
    --data "$payload" \
    "$api_base/traces" >/dev/null
  ((deleted += count))
  sleep 1
done

echo "Scheduled deletion for $deleted Langfuse traces older than $cutoff."
