# cnd-sgtm-ovhcloud

Terraform template for deploying **Server-side Google Tag Manager (sGTM)** into
[OVHCloud Managed Kubernetes (OKS)](https://www.ovhcloud.com/en/public-cloud/kubernetes/).

## Architecture

```
                      ┌─────────────────────────────────────────┐
                      │           OVHCloud OKS Cluster           │
                      │                                          │
DNS A record ──────►  │  LoadBalancer ──► Tagging Server Pods   │
(sgtm.example.com)    │                        │                 │
                      │                        │ cluster-internal│
                      │                   Preview Server Pod     │
                      └─────────────────────────────────────────┘
```

| Component | Description |
|-----------|-------------|
| **Tagging server** | Main sGTM endpoint. Exposed via a cloud load balancer. Auto-scales with HPA. |
| **Preview server** | Handles GTM preview/debug sessions. ClusterIP by default, with optional public OVH load balancer service. |
| **Ingress + TLS (optional)** | Installs ingress-nginx and cert-manager, then provisions Let's Encrypt certificates for HTTPS endpoints. |
| **HorizontalPodAutoscaler** | Scales tagging-server pods between `min` and `max` replicas based on CPU utilisation. |
| **Node pool** | OVHCloud managed worker node pool with auto-scaling enabled. |

## Prerequisites

| Tool | Version |
|------|---------|
| [Terraform](https://developer.hashicorp.com/terraform/install) | ≥ 1.3 |
| [OVH API credentials](https://www.ovh.com/auth/api/createToken) | – |
| GTM server-container **container config** string | from GTM UI |

### OVH API token permissions required

When creating your token at <https://www.ovh.com/auth/api/createToken>, grant:

```
GET  /cloud/project
GET  /cloud/project/*
POST /cloud/project/*
PUT  /cloud/project/*
DELETE /cloud/project/*
```

## Quick Start

```bash
# 1. Clone this repository
git clone https://github.com/cloudninedigital/cnd-sgtm-ovhcloud.git
cd cnd-sgtm-ovhcloud

# 2. Create your variable file
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars and fill in all REPLACE_WITH_* placeholders

# 3. Initialise Terraform
terraform init

# 4. Review the execution plan
terraform plan

# 5. Apply
terraform apply
```

### Optional: automatic HTTPS endpoints via Terraform

Set these variables in `terraform.tfvars` before `terraform apply`:

```hcl
enable_https_ingress = true
letsencrypt_email    = "ops@example.com"
tagging_server_host  = "sgtm.example.com"
preview_server_host  = "preview.example.com"
```

Then point both DNS A records (`sgtm.example.com`, `preview.example.com`) to the
`ingress_controller_load_balancer_ip` output and wait for certificate issuance.

When `enable_https_ingress = true`, the tagging-server automatically uses
`https://<preview_server_host>` for `PREVIEW_SERVER_URL`.

After a successful apply, Terraform outputs the **load balancer IP address**:

```
tagging_server_load_balancer_ip = "51.x.x.x"
```

Create an **A record** in your DNS zone pointing your sGTM subdomain to that IP:

```
sgtm.example.com  →  51.x.x.x
```

## Variables

All variables are declared in [`variables.tf`](./variables.tf).
A fully annotated example is provided in [`terraform.tfvars.example`](./terraform.tfvars.example).

### Required variables (no default)

| Variable | Description |
|----------|-------------|
| `ovh_application_key` | OVH API application key |
| `ovh_application_secret` | OVH API application secret |
| `ovh_consumer_key` | OVH API consumer key |
| `ovh_cloud_project_service` | OVHCloud project ID |
| `container_config` | sGTM container config string from GTM UI |
| `preview_server_url` | Public HTTPS URL of your preview server (required when `enable_https_ingress = false`) |

### Key optional variables (with defaults)

| Variable | Default | Description |
|----------|---------|-------------|
| `ovh_endpoint` | `ovh-eu` | API endpoint region |
| `region` | `GRA7` | OVH datacenter region |
| `cluster_name` | `sgtm-cluster` | Kubernetes cluster name |
| `kubernetes_version` | `""` (latest) | K8s version |
| `node_flavor` | `b3-8` | Worker node instance flavor |
| `node_pool_min_nodes` | `1` | Min worker nodes |
| `node_pool_max_nodes` | `3` | Max worker nodes |
| `tagging_server_min_replicas` | `2` | Min tagging server pods |
| `tagging_server_max_replicas` | `10` | Max tagging server pods |
| `tagging_server_cpu_limit` | `1000m` | CPU limit per tagging pod |
| `tagging_server_memory_limit` | `512Mi` | Memory limit per tagging pod |
| `enable_https_ingress` | `false` | Install ingress-nginx and cert-manager and expose HTTPS endpoints |
| `letsencrypt_email` | `""` | Email for Let's Encrypt ACME registration (required when HTTPS ingress is enabled) |
| `tagging_server_host` | `""` | DNS host for tagging-server HTTPS endpoint (required when HTTPS ingress is enabled) |
| `preview_server_host` | `""` | DNS host for preview-server HTTPS endpoint (required when HTTPS ingress is enabled) |
| `preview_server_public_enabled` | `true` | Create an OVH public LoadBalancer service for preview-server |
| `preview_server_replicas` | `1` | Preview server pod count |

## Outputs

| Output | Description |
|--------|-------------|
| `tagging_server_load_balancer_ip` | Public IP – set this as your DNS A record target |
| `tagging_server_public_url` | Public URL for immediate testing (LB hostname when available, else nip.io placeholder) |
| `tagging_server_https_url` | HTTPS URL for tagging server when HTTPS ingress is enabled |
| `preview_server_cluster_ip` | Internal cluster IP of the preview server |
| `preview_server_load_balancer_ip` | Public IP of the preview-server LB (when enabled) |
| `preview_server_public_url` | Public preview URL placeholder for testing (HTTP; configure DNS+TLS for production) |
| `preview_server_https_url` | HTTPS URL for preview server when HTTPS ingress is enabled |
| `ingress_controller_load_balancer_ip` | Public IP of ingress-nginx controller; DNS A records should point here |
| `ingress_controller_load_balancer_hostname` | Public hostname of ingress-nginx controller when provider returns hostname |
| `cluster_id` | OVHCloud cluster ID |
| `kubernetes_version` | Running Kubernetes version |
| `namespace` | Kubernetes namespace used |

## Destroying the infrastructure

```bash
terraform destroy
```

> **Warning:** This will delete the Kubernetes cluster, node pool, and all deployed
> workloads. Ensure you have backed up any data before proceeding.

## Troubleshooting

### Error: Unexpected Identity Change (kubernetes provider)

If Terraform fails with an `Unexpected Identity Change` error on
`kubernetes_deployment_v1.tagging_server`, use this recovery flow:

```bash
# 1) Upgrade provider plugins (never downgrade when state was written by newer provider)
terraform init -upgrade

# 2) Check the exact state addresses available
terraform state list

# 3) If the resource exists in state, remove it
terraform state rm kubernetes_deployment_v1.tagging_server

# 4) Import the existing deployment back into state
terraform import kubernetes_deployment_v1.tagging_server sgtm/tagging-server

# 5) Re-run plan/apply
terraform plan
terraform apply
```

If `terraform state rm` says "No matching objects found", continue with the
import step. If the same issue occurs for other Kubernetes resources, repeat
the same `state rm` + `import` flow for each resource address.

## Security notes

* **Never commit `terraform.tfvars`** – it contains API keys and the GTM container
  config. The provided `.gitignore` excludes it automatically.
* The `container_config` variable is marked `sensitive = true` so it will not appear
  in Terraform plan/apply output.
* The OVH API credentials (`ovh_application_key`, `ovh_application_secret`,
  `ovh_consumer_key`) are also `sensitive = true`.

