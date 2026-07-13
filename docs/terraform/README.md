# Terraform Documentation

This directory contains detailed documentation for every Terraform file and module.

## Files in This Directory

| File | What It Covers |
|------|---------------|
| [01-environments-dev.md](./01-environments-dev.md) | The root environment — `environments/dev/` all files |
| [02-module-networking.md](./02-module-networking.md) | VPC, subnets, secondary ranges |
| [03-module-service-accounts.md](./03-module-service-accounts.md) | All GCP service accounts and IAM bindings |
| [04-module-gke.md](./04-module-gke.md) | GKE cluster, node pools, autoscaling, workload identity |
| [05-module-argocd-bootstrap.md](./05-module-argocd-bootstrap.md) | ArgoCD install, root app, WI bindings |
| [06-module-github-wif.md](./06-module-github-wif.md) | GitHub Actions Workload Identity Federation |
| [07-module-artifact-registry.md](./07-module-artifact-registry.md) | Private Docker registry |
| [08-supporting-modules.md](./08-supporting-modules.md) | cloud-router, nat, firewall, project, dns modules |
| [09-output-flow.md](./09-output-flow.md) | Full output → input chain across all modules |

## Dependency Order (Apply Sequence)

```
project → networking → cloud_router → nat
                    ↘ firewall
project → service_accounts
networking + service_accounts + nat → gke
gke → argocd_bootstrap
project → artifact_registry
project → github_wif
```

## Quick Navigation

- **How values flow between modules** → [09-output-flow.md](./09-output-flow.md)
- **Why WIF uses null_resource not TF resources** → [06-module-github-wif.md](./06-module-github-wif.md)
- **Why ArgoCD uses kubectl not kubernetes_manifest** → [05-module-argocd-bootstrap.md](./05-module-argocd-bootstrap.md)
- **Node pool sizing** → [01-environments-dev.md](./01-environments-dev.md#locals-sizing)
