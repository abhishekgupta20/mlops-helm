# ==============================================================================
# Minimal IaC snippet showing how the ml-api Helm chart can be deployed via
# Terraform instead of the `helm install` CLI. This is intentionally simple
# and cloud-agnostic: it does NOT provision a cluster (no EKS/GKE/AKS, no
# billable cloud resources) -- it just points the Terraform Helm provider at
# whatever Kubernetes cluster your current kubeconfig context already
# resolves to (a local Minikube cluster, a real cluster, anything).
#
# In other words: this is the Terraform equivalent of
#   helm upgrade --install ml-api-dev charts/ml-api -f values-dev.yaml
# ==============================================================================

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.14"
    }
  }
}

provider "helm" {
  kubernetes {
    config_path = var.kubeconfig_path   # e.g. ~/.kube/config (Minikube's default)
  }
}

resource "helm_release" "ml_api" {
  name             = "ml-api-${var.environment}"
  namespace        = "ml-api-${var.environment}"
  create_namespace = true
  wait             = true
  timeout          = 180

  # Point directly at the local chart folder. Once the chart is published
  # (see .github/workflows/helm-chart-ci-cd.yaml), swap these two lines for:
  #   repository = "oci://ghcr.io/your-org/charts"
  #   chart      = "ml-api"
  #   version    = var.chart_version
  chart = "${path.module}/../charts/ml-api"

  # Same per-environment values file MLEs use with plain `helm install` --
  # so Terraform-driven and manual deploys can never drift apart.
  values = [
    file("${path.module}/../charts/ml-api/values-${var.environment}.yaml")
  ]

  # Secrets are never inlined here -- see README "Secrets Handling".
  # Example of injecting one at apply-time from a CI/Terraform Cloud
  # secret variable, without ever writing it to a file or state diff plaintext:
  #
  # set_sensitive {
  #   name  = "secret.data.DB_PASSWORD"
  #   value = var.db_password
  # }
}

output "release_status" {
  value = helm_release.ml_api.status
}
