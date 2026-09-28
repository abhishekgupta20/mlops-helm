#!/usr/bin/env bash
# Quick curl-based smoke test against a running ml-api service.
# Usage: ./scripts/smoke-test.sh [url]   (defaults to http://127.0.0.1:8080)
set -euo pipefail

URL="${1:-http://127.0.0.1:8080}"

echo "==> Hitting ${URL}"
response=$(curl -fsS --max-time 5 "${URL}")
echo "${response}"

if echo "${response}" | grep -qi "hello"; then
  echo "✅ Smoke test PASSED"
  exit 0
else
  echo "❌ Smoke test FAILED (unexpected response body)"
  exit 1
fi
