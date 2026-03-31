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
| **Preview server** | Handles GTM preview/debug sessions. Cluster-internal only (ClusterIP). |
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

## Outputs

| Output | Description |
|--------|-------------|
| `tagging_server_load_balancer_ip` | Public IP – set this as your DNS A record target |
| `preview_server_cluster_ip` | Internal cluster IP of the preview server |
| `cluster_id` | OVHCloud cluster ID |
| `kubernetes_version` | Running Kubernetes version |
| `namespace` | Kubernetes namespace used |

## Destroying the infrastructure

```bash
terraform destroy
```

> **Warning:** This will delete the Kubernetes cluster, node pool, and all deployed
> workloads. Ensure you have backed up any data before proceeding.

## Security notes

* **Never commit `terraform.tfvars`** – it contains API keys and the GTM container
  config. The provided `.gitignore` excludes it automatically.
* The `container_config` variable is marked `sensitive = true` so it will not appear
  in Terraform plan/apply output.
* The OVH API credentials (`ovh_application_key`, `ovh_application_secret`,
  `ovh_consumer_key`) are also `sensitive = true`.

