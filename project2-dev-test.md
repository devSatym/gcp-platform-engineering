# Project 2 — Dev environment test runbook

This runbook tests the current dev platform: Terraform infrastructure, ArgoCD
bootstrap, GitOps reconciliation, platform components, and the registered
OpenTelemetry Demo workload.

No command here is executed automatically. Review the Terraform plan before
the explicitly approved provisioning step. Do not run terraform destroy.

## 1. Prerequisites

Verify the tools:

    terraform version
    gcloud version
    kubectl version --client
    helm version
    git --version

You need a GCP project with billing enabled, permission to create the
configured resources, access to the GitHub repository, and network access from
the Terraform runner to the GKE control plane.

## 2. Authenticate to GCP

Use shell variables only; do not commit credentials or secret values.

    export TEST_PROJECT_ID="your-dev-gcp-project-id"
    export TEST_REGION="your-gcp-region"
    export TEST_ZONE="your-gcp-zone"
    gcloud auth login
    gcloud auth application-default login
    gcloud config set project "$TEST_PROJECT_ID"
    gcloud auth list
    gcloud projects describe "$TEST_PROJECT_ID"

## 3. Replace dev placeholders

Edit these files:

    terraform/environments/dev/terraform.tfvars
    gitops/environments/dev/config.yaml

Replace every replace-with-* value, including:

- GCP project ID, region, zone, cluster name
- VPC, router, NAT, node pool, and Artifact Registry names
- GitHub repository in owner/repository format
- pinned ArgoCD chart version
- Git repository and GitOps repository URLs

Check for unresolved placeholders:

    rg -n 'replace-with|YOUR_|example\.invalid|https://replace' \
      terraform/environments/dev gitops/environments/dev

The command should return no results.

## 4. Static validation

From the repository root:

    terraform fmt -check -recursive
    git diff --check
    cd terraform/environments/dev
    terraform init -backend=false
    terraform validate
    cd ../..

Validate GitOps and GitHub Actions YAML:

    python3 - <<'PY'
    import pathlib
    import yaml
    files = sorted(
        list(pathlib.Path("gitops").rglob("*.yaml"))
        + list(pathlib.Path(".github").rglob("*.yaml"))
        + list(pathlib.Path(".github").rglob("*.yml"))
    )
    for path in files:
        with path.open() as stream:
            list(yaml.safe_load_all(stream))
        print(f"OK {path}")
    print(f"Validated {len(files)} YAML files")
    PY

If installed:

    yamllint gitops .github/workflows

## 5. Validate the workload chart

The Demo is workload-owned under gitops/workloads/opentelemetry-demo.

    helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
    helm repo update
    helm show chart open-telemetry/opentelemetry-demo --version 0.40.9

Parse the workload values:

    python3 - <<'PY'
    import pathlib
    import yaml
    files = sorted(pathlib.Path("gitops/workloads").glob("*/values/*.yaml"))
    for path in files:
        with path.open() as stream:
            yaml.safe_load(stream)
        print(f"OK {path}")
    PY

Optionally render the dev chart locally. Do not apply this output directly:

    helm template opentelemetry-demo \
      open-telemetry/opentelemetry-demo \
      --version 0.40.9 \
      --namespace opentelemetry-demo-dev \
      -f gitops/workloads/opentelemetry-demo/values/base.yaml \
      -f gitops/workloads/opentelemetry-demo/values/dev.yaml \
      > /tmp/opentelemetry-demo-dev-rendered.yaml

## 6. Review the Terraform plan

    cd terraform/environments/dev
    terraform init
    terraform plan -out=/tmp/project2-dev.tfplan
    terraform show -no-color /tmp/project2-dev.tfplan \
      > /tmp/project2-dev-plan.txt
    less /tmp/project2-dev-plan.txt

Confirm the plan targets only the intended dev foundation:

- GCP APIs, VPC, subnets, firewall, router, and NAT
- GKE cluster and dev node pools
- Artifact Registry
- IAM, service accounts, and Workload Identity Federation
- Secret Manager foundations
- ArgoCD bootstrap

It must not contain normal workload Deployments, Services, application
replicas, dashboards, or application-specific ports.

## 7. Provision dev — explicit approval required

Only after reviewing the complete plan:

    terraform apply /tmp/project2-dev.tfplan

Do not use -auto-approve for the first test. Stop if Terraform shows an
unexpected project, region, resource name, or destructive change.

Terraform may install ArgoCD and bootstrap its AppProjects and root
Application. Subsequent Kubernetes resources should be reconciled by ArgoCD.

## 8. Connect to GKE

Use the exact configured values:

    gcloud container clusters get-credentials your-dev-cluster-name \
      --region your-dev-region \
      --project your-dev-gcp-project-id

    kubectl cluster-info
    kubectl get nodes -o wide
    kubectl get namespaces

## 9. Verify ArgoCD and GitOps

    kubectl -n argocd get pods
    kubectl -n argocd get applications
    kubectl -n argocd get applicationsets
    kubectl -n argocd get appprojects

Inspect generated workload Applications:

    kubectl -n argocd get applications -o wide
    kubectl -n argocd describe applicationset workloads
    kubectl -n argocd describe applicationset platform-components

The Demo Application must be generated from the workload registration and
environment configuration, not from an OTel-specific generator.

## 10. Verify platform components

    kubectl -n platform-system get pods
    kubectl -n kube-system get deployment metrics-server
    kubectl top nodes
    kubectl top pods -A
    kubectl get priorityclasses

No ExternalSecret objects may exist for the Demo currently; its registration
does not require external secrets. That is expected.

## 11. Verify the Demo workload

    kubectl get namespace opentelemetry-demo-dev
    kubectl -n opentelemetry-demo-dev get pods -o wide
    kubectl -n opentelemetry-demo-dev get deployments
    kubectl -n opentelemetry-demo-dev get services
    kubectl -n opentelemetry-demo-dev get pods -w

If the chart exposes the frontend proxy:

    kubectl -n opentelemetry-demo-dev port-forward \
      svc/otel-demo-frontendproxy 8080:8080

Open http://localhost:8080. Service names can vary with the chart version;
always confirm them with kubectl get svc.

## 12. Safe GitOps verification

Do not manually delete resources during the first test. Inspect status:

    kubectl -n argocd get application \
      -l app.kubernetes.io/part-of=workloads \
      -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status

Expected result is Synced and Healthy after reconciliation.

## 13. Troubleshooting

ArgoCD:

    kubectl -n argocd describe application opentelemetry-demo-dev
    kubectl -n argocd logs deploy/argocd-application-controller
    kubectl -n argocd logs deploy/argocd-repo-server

Workload:

    kubectl -n opentelemetry-demo-dev describe pod <pod-name>
    kubectl -n opentelemetry-demo-dev logs <pod-name> --all-containers
    kubectl -n opentelemetry-demo-dev get events --sort-by=.lastTimestamp

Common failures:

- unresolved placeholders
- inaccessible GitOps repository
- invalid ArgoCD chart version
- no private control-plane connectivity
- invalid zone/region combination
- insufficient dev node capacity
- chart and values schema mismatch

## 14. Completion checklist

- [ ] No dev placeholders remain.
- [ ] Terraform plan targets the intended project.
- [ ] Plan has no unexpected deletes.
- [ ] GKE nodes are Ready.
- [ ] ArgoCD pods are Ready.
- [ ] AppProjects and ApplicationSets exist.
- [ ] Platform Applications are Synced and Healthy.
- [ ] Workload Application is generated from registration.
- [ ] Demo pods become Ready.
- [ ] Demo is reachable through port-forward if desired.
- [ ] No secrets were committed.
- [ ] No direct workload kubectl apply was used.

Do not destroy the environment as part of routine testing. A later destroy
requires a separately reviewed plan and explicit approval.
