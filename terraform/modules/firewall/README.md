# Module: firewall

Creates least-privilege firewall rules for the platform VPC.

## Design Principles

- **Default deny**: Explicit deny-all rule at priority 65534 makes the security posture visible and loggable.
- **No public SSH**: SSH is only allowed from Google's IAP IP range (`35.235.240.0/20`) and only to VMs tagged `allow-iap`.
- **Logging enabled**: All rules log metadata to Cloud Logging for security analysis.
- **Minimal surface**: No rules open inbound traffic to `0.0.0.0/0` except health check probes from Google's documented ranges.

## Rules Created

| Rule Name | Direction | Source | Target | Ports | Priority |
|---|---|---|---|---|---|
| `allow-internal` | INGRESS | `10.0.0.0/16` | All instances | TCP, UDP, ICMP, SCTP | 1000 |
| `allow-iap-ssh` | INGRESS | `35.235.240.0/20` | Tag: `allow-iap` | TCP/22 | 1000 |
| `allow-health-checks` | INGRESS | GCP health check ranges | All instances | TCP | 1000 |
| `deny-all-ingress` | INGRESS | `0.0.0.0/0` | All instances | All | 65534 |

## Usage

```hcl
module "firewall" {
  source     = "../../modules/firewall"
  project_id = var.project_id
  vpc_name   = module.networking.vpc_name
}
```

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `project_id` | `string` | required | GCP project ID |
| `vpc_name` | `string` | required | VPC to apply rules to |
| `internal_cidr` | `string` | `10.0.0.0/16` | VPC internal CIDR |

## Outputs

| Name | Description |
|---|---|
| `firewall_rule_names` | List of created firewall rule names |
