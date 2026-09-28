# Terraform (IaC snippet)

Deploys the `ml-api` chart the same way `helm install` does, but declaratively,
against whatever cluster your current kubeconfig points to (e.g. Minikube).
No cloud resources, no cost, nothing to provision beyond the chart itself.

```bash
cd terraform
terraform init
terraform apply -var="environment=dev"
```
