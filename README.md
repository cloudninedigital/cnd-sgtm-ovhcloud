# cnd-sgtm-ovhcloud

Terraform template for deploying **Server-side Google Tag Manager (sGTM)** into
[OVHCloud Managed Kubernetes (OKS)](https://www.ovhcloud.com/en/public-cloud/kubernetes/).

## Architecture

```
                      ┌─────────────────────────────────────────┐
                      │           OVHCloud OKS Cluster           │
                      │                                          │
DNS A records ──────► ingress-nginx ──► Tagging Server Pods   │
(via SNI+Host)    LoadBalancer          │ (auto-scaling)       │
                      │                        │ cluster-internal│
                      │ (TLS termination)  Preview Server Pod    │
                      └─────────────────────────────────────────┘
```

| Component | Description |
|-----------|-------------|
| **Ingress controller (ingress-nginx)** | Public LoadBalancer exposing HTTPS endpoints. Handles TLS termination and host-based routing. |
| **Tagging server** | Main sGTM endpoint at `tagging_server_host`. Auto-scales with HPA based on CPU utilization. |
| **Preview server** | Handles GTM preview/debug sessions at `preview_server_host`. Single pod with internal ClusterIP routing. |
| **cert-manager + Let's Encrypt** | Automatically provisions and renews SSL certificates. No manual certificate management required. |
| **HorizontalPodAutoscaler** | Scales tagging-server pods between `tagging_server_min_replicas` and `tagging_server_max_replicas` based on CPU utilization. |
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

This template deploys **production-ready HTTPS endpoints** with automatic SSL certificates 
from Let's Encrypt. The setup uses a two-phase deployment pattern to work reliably with 
Kubernetes cluster bootstrapping.

In practice, deployment is:
- **2 applies** when `defer_tagging_server_rollout = false`
- **3 applies** when `defer_tagging_server_rollout = true` (recommended for first-time bootstrap)

### Prerequisites for HTTPS deployment

Before starting, ensure you have:
- **DNS zone** configured where you can create A records
- **Email address** for Let's Encrypt (no signup required – certificates are issued automatically)
- **OVH API credentials** with appropriate permissions (see [OVH API token permissions](#ovh-api-token-permissions-required))

### Step 1: Clone and configure

```bash
# 1. Clone this repository
git clone https://github.com/cloudninedigital/cnd-sgtm-ovhcloud.git
cd cnd-sgtm-ovhcloud

# 2. Create your variable file
cp terraform.tfvars.example terraform.tfvars

# 3. Edit terraform.tfvars and fill in all REPLACE_WITH_* placeholders, including:
#    - OVH credentials (ovh_application_key, ovh_application_secret, ovh_consumer_key)
#    - GTM container config string
#    - Your email address for letsencrypt_email
#    - Two DNS hostnames for tagging_server_host and preview_server_host
```

### Step 2: Initial infrastructure and certificate provisioning (Create CRDs)

```bash
# 4. Initialise Terraform
terraform init

# 5. First apply: sets up cluster, services, ingress-nginx, and cert-manager
#    BUT DOES NOT create certificates yet (CRDs need time to register)
terraform apply
```

**What happens:** Kubernetes cluster, node pool, ingress-nginx, and cert-manager are 
provisioned. However, Let's Encrypt ClusterIssuer is NOT created yet because the cert-manager 
CustomResourceDefinitions (CRDs) need additional time to register after first install.

**After Step 2 completes:**
- Go to your DNS provider and create **two A records** pointing to the ingress controller's public IP 
  (shown in Terraform output as `ingress_controller_load_balancer_ip`):
  - `tagging_server_host` → ingress IP
  - `preview_server_host` → ingress IP

For example:
```
sst-ovh-tagging.cloudninedigital.nl    →  51.x.x.x
sst-ovh-preview.cloudninedigital.nl   →  51.x.x.x
```

### Step 3: Enable certificate issuer (Activate Let's Encrypt)

```bash
# 6. Edit terraform.tfvars: change create_letsencrypt_cluster_issuer from false to true
#    create_letsencrypt_cluster_issuer = true

# 7. Second apply: creates Let's Encrypt ClusterIssuer and Ingress certificates
terraform apply
```

**What happens:** The Let's Encrypt ClusterIssuer is created and cert-manager automatically 
requests SSL certificates for both your DNS hostnames. Let's Encrypt validates DNS ownership 
(using HTTP-01 challenges) and issues certificates. **No manual signup is required** – the 
`letsencrypt_email` address is used for account registration automatically.

**After Step 3 completes:**
- Certificates will be provisioned automatically (usually within 30 seconds)
- Both your tagging server and preview server are now accessible via HTTPS
- Your sGTM container automatically detects the preview server HTTPS URL and configures it

Verify certificate status:
```bash
kubectl get certificate -n sgtm
kubectl describe certificate tagging-server-tls -n sgtm
```

### Optional Step 4: Activate tagging-server after TLS is confirmed

If `defer_tagging_server_rollout = true` during bootstrap, tagging-server stays at 0 replicas 
until you explicitly enable it.

```bash
# 8. Edit terraform.tfvars
#    defer_tagging_server_rollout = false

# 9. Third apply (only needed when rollout was deferred)
terraform apply
```

## Understanding the Phase Pattern

### Why there can be two or three applies

Kubernetes has a limitation with **CustomResourceDefinitions (CRDs)**: When cert-manager is 
first installed, its CRD definitions need time to fully register in the cluster before other 
resources can reliably reference them. If you try to create a `ClusterIssuer` (which uses a 
cert-manager CRD) immediately in the same Terraform apply, the Kubernetes provider may fail 
during planning because it can't yet discover the CRD schema.

The base pattern is two applies because of cert-manager CRD registration timing:
1. **Phase 1 (first `terraform apply`)**
2. **Phase 2 (second `terraform apply`)**

If you also defer tagging rollout for safer bootstrap, there is one additional apply:
3. **Phase 3 (third `terraform apply`)**

### Phase-by-phase switch values

| Phase | `create_letsencrypt_cluster_issuer` | `defer_tagging_server_rollout` | Result |
|------|--------------------------------------|----------------------------------|--------|
| Phase 1 | `false` | `true` (recommended) or `false` | Installs cluster + ingress-nginx + cert-manager CRDs |
| Phase 2 | `true` | keep previous value | Creates ClusterIssuer and requests TLS certificates |
| Phase 3 (optional) | `true` | `false` | Starts tagging-server pods if rollout was deferred |

If you do not defer rollout, use:
- Phase 1: `create_letsencrypt_cluster_issuer = false`, `defer_tagging_server_rollout = false`
- Phase 2: `create_letsencrypt_cluster_issuer = true`, `defer_tagging_server_rollout = false`

### About the `letsencrypt_email` address

The email address provided in `letsencrypt_email` is used by Let's Encrypt for:
- **Account registration** (entirely automatic – no manual signup at letsencrypt.org is required)
- **Certificate renewal reminders** (sent as certificates approach expiration)
- **Security notices** (if suspicious activity is detected)

You do **not** need to pre-register or create an account with Let's Encrypt. The cert-manager 
automatically handles all ACME protocol interactions when requesting certificates.

### Deferred rollout recommendation

Use `defer_tagging_server_rollout = true` for first-time environments when DNS and TLS are still 
propagating. This avoids starting tagging-server pods before preview HTTPS is fully reachable.

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
| `letsencrypt_email` | Email address for Let's Encrypt ACME (no signup required – automatic) |
| `tagging_server_host` | DNS hostname for your sGTM tagging server (e.g., `sst-ovh-tagging.cloudninedigital.nl`) |
| `preview_server_host` | DNS hostname for your sGTM preview server (e.g., `sst-ovh-preview.cloudninedigital.nl`) |

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
| `preview_server_replicas` | `1` | Preview server pod count |
| `preview_server_public_enabled` | `true` | Create an OVH public LoadBalancer service for preview-server (redundant when HTTPS ingress enabled) |
| `defer_tagging_server_rollout` | `false` | Set to `true` if DNS/TLS not ready on first deploy – keeps tagging-server at 0 replicas until Step 3 is complete |
| `create_letsencrypt_cluster_issuer` | `false` | **Phase 2 toggle:** Set to `true` on second apply to activate Let's Encrypt certificate provisioning |
| `helm_release_timeout_seconds` | `900` | Helm install/upgrade timeout for ingress-nginx and cert-manager. Increase on new/slower clusters if you see `context deadline exceeded`. |
| `preview_server_url` | `""` | (Deprecated) Only used if HTTPS ingress is manually disabled; use hostnames instead |

## Outputs

| Output | Description |
|--------|-------------|
| `ingress_controller_load_balancer_ip` | **Primary:** Public IP of ingress-nginx controller; set your DNS A records to point here (Step 2) |
| `ingress_controller_load_balancer_hostname` | Public hostname of ingress-nginx controller when OVHCloud returns one |
| `tagging_server_https_url` | HTTPS endpoint for tagging server (available after certificates are issued in Step 3) |
| `preview_server_https_url` | HTTPS endpoint for preview server (available after certificates are issued in Step 3) |
| `tagging_server_load_balancer_ip` | (Deprecated) Legacy IP for standalone tagging LB service; use ingress IP instead |
| `tagging_server_public_url` | (Deprecated) Legacy URL via standalone LB; use ingress HTTPS URL instead |
| `preview_server_load_balancer_ip` | (Deprecated) Legacy IP for standalone preview LB service; use ingress IP instead |
| `preview_server_cluster_ip` | Internal cluster IP of the preview server |
| `preview_server_public_url` | (Deprecated) Legacy URL via standalone LB; use ingress HTTPS URL instead |
| `cluster_id` | OVHCloud cluster ID |
| `kubernetes_version` | Running Kubernetes version |
| `namespace` | Kubernetes namespace used (default: `sgtm`) |

## Destroying the infrastructure

```bash
terraform destroy
```

> **Warning:** This will delete the Kubernetes cluster, node pool, and all deployed
> workloads. Ensure you have backed up any data before proceeding.

## Troubleshooting

### Error: Helm release error (`context deadline exceeded`)

On brand-new clusters, ingress-nginx or cert-manager can take longer than Helm's default timeout
while LoadBalancers, webhooks, and controller pods become ready.

Set a higher timeout in `terraform.tfvars`, for example:

```hcl
helm_release_timeout_seconds = 1200
```

Then run:

```bash
terraform apply
```

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

