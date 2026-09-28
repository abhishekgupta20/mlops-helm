# ml-api — A Generic Helm Chart for ML Inference APIs (Dev / Staging / Production)

This is my submission for the MLOps Platform Engineering take-home. It contains
**one generic Helm chart** that an ML Engineer (MLE) can use to deploy a
containerized inference API to Dev, Staging or Production by changing
**only a values file** — no copy-pasted manifests, no per-environment forks.

```
mlops-helm-assignment/
├── charts/ml-api/                      # the generic Helm chart
│   ├── Chart.yaml
│   ├── values.yaml                     # shared defaults
│   ├── values-dev.yaml                 # <- MLEs edit these three files only
│   ├── values-staging.yaml
│   ├── values-production.yaml
│   ├── templates/                      # generic K8s manifests
│   │   ├── deployment.yaml, service.yaml, ingress.yaml, hpa.yaml,
│   │   ├── configmap.yaml, secret.yaml, serviceaccount.yaml, NOTES.txt
│   │   └── tests/test-connection.yaml  # `helm test` post-install smoke test
│   └── tests/deployment_test.yaml      # `helm-unittest` chart unit tests
├── .github/workflows/helm-chart-ci-cd.yaml   # lint -> unit test -> package -> publish
├── terraform/                          # small IaC snippet (local cluster, no cloud cost)
├── scripts/deploy-local.sh             # one-command Minikube deploy
├── scripts/smoke-test.sh
└── README.md
```

---

## 1. Design Philosophy

**One chart, many environments, via values only.** Everything that differs
between Dev/Staging/Production is a Helm value with a sane default in
`values.yaml`; `templates/` has zero environment-specific logic. An MLE ships
a new model version by editing one line in one values file:

```bash
# edit ONE line in the right values file
yq -i '.image.tag = "1.4.2"' charts/ml-api/values-production.yaml
git commit -am "ml-api: promote model v1.4.2 to production" && git push
```

| Concern          | Dev                             | Staging                     | Production                          |
|-------------------|----------------------------------|-----------------------------|--------------------------------------|
| Replicas          | 1, fixed                        | 2, autoscale 2–4            | 3, autoscale 3–10                    |
| Service exposure  | `NodePort` (Minikube-friendly)  | `ClusterIP` + Ingress + TLS | `ClusterIP` + Ingress + TLS          |
| Resources         | tiny (25m/32Mi)                 | moderate                    | production-sized, hard limits        |
| Secrets           | disabled                        | `existingSecret` (external) | `existingSecret` (external)          |
| Log level         | debug                            | info                        | warn                                  |

---

## 2. Quickstart: Deploy to a local Minikube cluster

```bash
# Prereqs: docker, minikube, kubectl, helm (v3.8+)
minikube start --driver=docker

# One command: lint -> install -> helm test -> expose
./scripts/deploy-local.sh dev

# ...or do it step by step:
helm lint charts/ml-api -f charts/ml-api/values-dev.yaml
helm upgrade --install ml-api-dev charts/ml-api \
  -f charts/ml-api/values-dev.yaml \
  --namespace ml-api-dev --create-namespace --wait
helm test ml-api-dev --namespace ml-api-dev
```

### Calling the API from your local PC

The chart uses **`gcr.io/google-samples/hello-app:1.0`** — a public
"Hello, world!" container serving on port 8080 — as the stand-in ML API, per
the assignment's suggestion. Swapping in a real model-serving image is a
three-line change to `image.repository` / `image.tag`, nothing else.

```bash
minikube service ml-api-dev -n ml-api-dev --url
curl $(minikube service ml-api-dev -n ml-api-dev --url)
# -> "Hello, world!\nVersion: 1.0.0\nHostname: ml-api-dev-xxxxxxx-yyyyy\n"

# or, works for any service type:
kubectl port-forward -n ml-api-dev svc/ml-api-dev 8080:80
curl http://127.0.0.1:8080
```

---

## 3. Test Cases

| Layer | Tool / file | What it checks |
|---|---|---|
| Static lint | `helm lint` (run against all 3 values files) | Malformed values, missing required fields |
| Unit tests | `helm-unittest` — `charts/ml-api/tests/deployment_test.yaml` | Template logic: e.g. HPA disappears when `autoscaling.enabled=false`, `runAsNonRoot` stays true by default, `spec.replicas` is omitted when the HPA owns scaling, Ingress/Secret only render when enabled |
| Runtime smoke test | `helm test` hook — `templates/tests/test-connection.yaml` | Confirms the actually-deployed Service responds, right after install |

Run everything locally:
```bash
helm plugin install https://github.com/helm-unittest/helm-unittest
helm unittest charts/ml-api
helm lint charts/ml-api -f charts/ml-api/values-production.yaml
```

---

## 4. CI/CD (`.github/workflows/helm-chart-ci-cd.yaml`)

GitHub Actions was chosen for zero external setup; every step is a plain
`helm` CLI call, so it ports to CircleCI/GitLab CI/Jenkins unchanged.

```
PR / push  ──▶  build  (helm lint x3 envs, helm template, helm unittest)

push to main ──▶ build ──▶ publish
                            (helm package, helm push to a private OCI
                             Helm registry)
```

- **Build**: packaged via `helm package` into `ml-api-<version>.tgz`
  (version comes from `Chart.yaml`).
- **Publish**: pushed with `helm push <tgz> oci://ghcr.io/<org>/charts` —
  Helm's native OCI registry support, used against GHCR here as a free
  stand-in for a private registry (swap the login step for ECR/ACR/Artifact
  Registry; only that one step changes).

---

## 5. Version Control Strategy

- **Chart versioning** follows SemVer via `Chart.yaml`'s `version` (chart/
  template changes) vs. `appVersion` (default application image).
- **Values files are the unit of promotion** — `main` holds the current
  desired state for all three environments at once, so `git diff` between
  two commits shows exactly what changed and where.
- Every merge to `main` publishes an immutable, versioned chart artifact —
  rollback is always `helm rollback` or re-pulling an older pinned version,
  never "whatever main currently renders to."

---

## 6. Secrets Handling

**No plaintext secret ever lives in this repo, in `values-*.yaml`, or in
`helm history`.** The chart supports two modes via `secret.*`:

1. **`secret.existingSecret: "<name>"`** (used for Staging/Production) — the
   chart never creates a Secret; it only *references* one that already
   exists in the namespace, provisioned out-of-band by something like
   External Secrets Operator (synced from AWS/GCP/Azure secret managers),
   Sealed Secrets, or SOPS — so the real value never touches this repo.
2. **`secret.enabled: true` + `secret.data`** (Dev-only escape hatch) — the
   chart *can* render a plain `Secret`, but only when no `existingSecret` is
   set, and this is always populated via
   `--set-string secret.data.KEY=$ENV_VAR` at install time (value sourced
   from a CI secret store), never via a committed values file.

---

## 7. Autoscaling

`templates/hpa.yaml` renders a `HorizontalPodAutoscaler` whenever
`autoscaling.enabled=true`, targeting CPU/memory utilization. Disabled in Dev
(fixed single replica); enabled in Staging (2–4 pods) and Production (3–10
pods). `deployment.yaml` omits `spec.replicas` whenever the HPA is enabled,
so the two never fight over ownership of replica count — asserted directly
by a `helm-unittest` test.

---

## 8. Infrastructure as Code

`terraform/main.tf` shows the chart deployed declaratively via Terraform's
Helm provider, using the **same per-environment values file** an MLE would
use with plain `helm install`, against whatever cluster your current
kubeconfig points to (Minikube or otherwise). It does **not** provision any
cloud infrastructure (no EKS/GKE/AKS, no cost) — it's a minimal snippet
showing the deployment pattern, per the assignment's ask.

```bash
cd terraform
terraform init
terraform apply -var="environment=dev"
```

---

## 9. Nice-to-Haves Included

- ✅ Autoscaling policies (Section 7)
- ✅ Version control strategy documented (Section 5)
- ✅ Secrets designed to never touch the repo, with a clear pattern for
  production-grade secret managers (Section 6)

## 10. Known Simplifications (by design, per assignment scope)

- The "ML API" is a hello-world placeholder image — the chart is agnostic to
  that, and swapping it is a 3-line diff.
- The Terraform snippet deploys to whatever cluster is in your kubeconfig; it
  does not provision cloud infrastructure, per the assignment's note that
  IaC here doesn't need to be a working, billable setup.
- Ingress TLS assumes cert-manager is already installed cluster-wide, which
  is standard in most orgs and out of scope for a chart whose job is the
  application, not cluster bootstrapping.
