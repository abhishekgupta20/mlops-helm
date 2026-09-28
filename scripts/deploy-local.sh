#!/usr/bin/env bash
# Deploy the ml-api chart to a local Minikube cluster using the Dev values,
# then port-forward it so it's callable from your local machine.
#
# Usage: ./scripts/deploy-local.sh [dev|staging|production]
set -euo pipefail

ENVIRONMENT="${1:-dev}"
CHART_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/charts/ml-api"
RELEASE="ml-api-${ENVIRONMENT}"
NAMESPACE="ml-api-${ENVIRONMENT}"

echo "==> Checking Minikube status"
if ! minikube status >/dev/null 2>&1; then
  echo "==> Starting Minikube"
  minikube start --driver=docker --cpus=2 --memory=3072
fi

echo "==> Linting chart with ${ENVIRONMENT} values"
helm lint "${CHART_DIR}" -f "${CHART_DIR}/values-${ENVIRONMENT}.yaml"

echo "==> Installing/upgrading release '${RELEASE}' in namespace '${NAMESPACE}'"
helm upgrade --install "${RELEASE}" "${CHART_DIR}" \
  -f "${CHART_DIR}/values-${ENVIRONMENT}.yaml" \
  --namespace "${NAMESPACE}" --create-namespace \
  --wait --timeout 3m

echo "==> Running Helm test (post-install smoke test)"
helm test "${RELEASE}" --namespace "${NAMESPACE}"

echo "==> Deployment complete. Exposing service on your local machine..."
if kubectl get svc "${RELEASE}" -n "${NAMESPACE}" -o jsonpath='{.spec.type}' | grep -q NodePort; then
  minikube service "${RELEASE}" -n "${NAMESPACE}" --url
else
  echo "Port-forwarding http://127.0.0.1:8080 -> service/${RELEASE}:80 (Ctrl+C to stop)"
  kubectl port-forward -n "${NAMESPACE}" "svc/${RELEASE}" 8080:80
fi
