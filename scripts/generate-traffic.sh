#!/usr/bin/env bash
# Generate mixed traffic against the orders API so dashboards and alerts have
# real data: mostly healthy CRUD, a slice of simulated errors and latency.
#
# Usage:
#   ./scripts/generate-traffic.sh https://<app-fqdn> [duration_seconds]
#   BASE_URL=$(cd terraform && terraform output -raw app_fqdn) \
#     ./scripts/generate-traffic.sh "https://$BASE_URL" 600
#
# Tip: raise ERROR_WEIGHT to ~30 to push the failure rate past the 5% alert
# threshold and watch the webhook fire.

set -euo pipefail

BASE_URL="${1:-${BASE_URL:-}}"
DURATION="${2:-300}"
ERROR_WEIGHT="${ERROR_WEIGHT:-5}"    # percent of requests hitting /simulate/error
LATENCY_WEIGHT="${LATENCY_WEIGHT:-5}" # percent of requests hitting /simulate/latency

if [[ -z "$BASE_URL" ]]; then
  echo "usage: $0 <base-url> [duration_seconds]" >&2
  echo "example: $0 https://ca-orders-api.niceocean-1234.eastus2.azurecontainerapps.io 300" >&2
  exit 1
fi

BASE_URL="${BASE_URL%/}"
END=$((SECONDS + DURATION))
SKUS=("WIDGET-001" "WIDGET-002" "GADGET-100" "GIZMO-7")
CREATED_IDS=()
COUNT=0

echo "Generating traffic against ${BASE_URL} for ${DURATION}s"
echo "(error weight ${ERROR_WEIGHT}%, latency weight ${LATENCY_WEIGHT}%)"

request() {
  # Fire-and-record; individual failures are the point, not a script error.
  curl --silent --show-error --output /dev/null --max-time 15 \
    --write-out "%{http_code} %{time_total}s ${1} ${2}\n" \
    -X "$1" "${BASE_URL}${2}" "${@:3}" || true
}

while ((SECONDS < END)); do
  ROLL=$((RANDOM % 100))

  if ((ROLL < ERROR_WEIGHT)); then
    request GET /simulate/error
  elif ((ROLL < ERROR_WEIGHT + LATENCY_WEIGHT)); then
    request GET /simulate/latency
  elif ((ROLL < 40)); then
    SKU="${SKUS[RANDOM % ${#SKUS[@]}]}"
    QTY=$((RANDOM % 5 + 1))
    BODY=$(curl --silent --max-time 15 -X POST "${BASE_URL}/orders" \
      -H 'Content-Type: application/json' \
      -d "{\"sku\":\"${SKU}\",\"quantity\":${QTY},\"customer_id\":\"cust-$((RANDOM % 50))\"}" || true)
    ID=$(printf '%s' "$BODY" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p')
    [[ -n "$ID" ]] && CREATED_IDS+=("$ID")
    echo "201 POST /orders sku=${SKU}"
  elif ((ROLL < 60)) && ((${#CREATED_IDS[@]} > 0)); then
    ID="${CREATED_IDS[RANDOM % ${#CREATED_IDS[@]}]}"
    request GET "/orders/${ID}"
  elif ((ROLL < 65)); then
    # Deliberate 404s: distinguishable from 5xx on the error-rate panel.
    request GET "/orders/does-not-exist-$((RANDOM % 1000))"
  else
    request GET /orders
  fi

  COUNT=$((COUNT + 1))
  sleep 0.2
done

echo "Done: ${COUNT} requests sent. Telemetry appears in App Insights within 1-2 minutes."
