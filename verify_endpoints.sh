#!/usr/bin/env bash
# verify_endpoints.sh — validates ALB endpoint routing and ECR repository existence.
# Usage:  ./verify_endpoints.sh <ALB_DNS>
# Or:     ALB_DNS=<dns> ./verify_endpoints.sh
# Exit code 0 = all checks passed; non-zero = one or more failures.

set -euo pipefail

ALB_DNS="${1:-${ALB_DNS:-}}"

if [[ -z "$ALB_DNS" ]]; then
  echo "Usage: $0 <ALB_DNS>"
  echo "  or set the ALB_DNS environment variable"
  exit 1
fi

FAILURES=0

# ── HTTP check helper ─────────────────────────────────────────────────────────
check_http() {
  local desc="$1"
  local url="$2"
  local expected_status="${3:-200}"
  local expected_body="${4:-}"

  printf "  %-45s " "$desc"

  local body
  local status
  body=$(mktemp)
  status=$(curl -s -o "$body" -w "%{http_code}" --max-time 10 "$url" 2>/dev/null) || status="000"
  local body_content
  body_content=$(cat "$body")
  rm -f "$body"

  if [[ "$status" != "$expected_status" ]]; then
    echo "FAIL  (HTTP $status, expected $expected_status)"
    echo "        URL:  $url"
    echo "        Body: $body_content"
    FAILURES=$((FAILURES + 1))
    return
  fi

  if [[ -n "$expected_body" ]] && ! echo "$body_content" | grep -q "$expected_body"; then
    echo "FAIL  (body missing '$expected_body')"
    echo "        URL:  $url"
    echo "        Body: $body_content"
    FAILURES=$((FAILURES + 1))
    return
  fi

  echo "OK    (HTTP $status)"
}

# ── ECR check helper ──────────────────────────────────────────────────────────
check_ecr() {
  local service="$1"

  printf "  %-45s " "ECR repo: $service"

  local uri
  uri=$(aws ecr describe-repositories \
    --repository-names "$service" \
    --query 'repositories[0].repositoryUri' \
    --output text 2>/dev/null) || uri=""

  if [[ -z "$uri" || "$uri" == "None" ]]; then
    echo "FAIL  (repository not found)"
    FAILURES=$((FAILURES + 1))
  else
    echo "OK    ($uri)"
  fi
}

# ── Run checks ────────────────────────────────────────────────────────────────
echo ""
echo "=== ALB endpoint checks: http://$ALB_DNS ==="
echo ""
check_http "GET /service1"              "http://$ALB_DNS/service1"  "200" "Hello from Service 1"
check_http "GET /service2"              "http://$ALB_DNS/service2"  "200" "Hello from Service 2"
check_http "GET /unknown → 404"         "http://$ALB_DNS/unknown"   "404"

echo ""
echo "=== ECR repository checks ==="
echo ""
check_ecr "service1"
check_ecr "service2"

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
if [[ $FAILURES -eq 0 ]]; then
  echo "=== All checks passed ==="
  exit 0
else
  echo "=== $FAILURES check(s) FAILED ==="
  exit 1
fi
