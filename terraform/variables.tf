variable "environment" {
  description = "Target environment: dev | staging | production"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "production"], var.environment)
    error_message = "environment must be one of: dev, staging, production."
  }
}

variable "kubeconfig_path" {
  description = "Path to kubeconfig used to reach the target cluster (Minikube's default shown)"
  type        = string
  default     = "~/.kube/config"
}
