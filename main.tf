# ─────────────────────────────────────────────────────────────────────────────
# Provider configuration
# ─────────────────────────────────────────────────────────────────────────────

provider "ovh" {
  endpoint           = var.ovh_endpoint
  application_key    = var.ovh_application_key
  application_secret = var.ovh_application_secret
  consumer_key       = var.ovh_consumer_key
}

# The kubernetes provider is configured once the cluster is ready.
provider "kubernetes" {
  host                   = data.ovh_cloud_project_kube.sgtm_cluster.kubeconfig_attributes[0].host
  client_certificate     = base64decode(data.ovh_cloud_project_kube.sgtm_cluster.kubeconfig_attributes[0].client_certificate)
  client_key             = base64decode(data.ovh_cloud_project_kube.sgtm_cluster.kubeconfig_attributes[0].client_key)
  cluster_ca_certificate = base64decode(data.ovh_cloud_project_kube.sgtm_cluster.kubeconfig_attributes[0].cluster_ca_certificate)
}

# ─────────────────────────────────────────────────────────────────────────────
# Managed Kubernetes cluster
# ─────────────────────────────────────────────────────────────────────────────

resource "ovh_cloud_project_kube" "sgtm_cluster" {
  service_name = var.ovh_cloud_project_service
  name         = var.cluster_name
  region       = var.region

  # Only set the version when explicitly specified; otherwise OVHCloud picks the default.
  version = var.kubernetes_version != "" ? var.kubernetes_version : null
}

# Read cluster details (including kubeconfig) after creation so that the
# kubernetes/helm providers can connect.
data "ovh_cloud_project_kube" "sgtm_cluster" {
  service_name = var.ovh_cloud_project_service
  kube_id      = ovh_cloud_project_kube.sgtm_cluster.id
}

# ─────────────────────────────────────────────────────────────────────────────
# Node pool with auto-scaling
# ─────────────────────────────────────────────────────────────────────────────

resource "ovh_cloud_project_kube_nodepool" "sgtm_nodepool" {
  service_name = var.ovh_cloud_project_service
  kube_id      = ovh_cloud_project_kube.sgtm_cluster.id

  name          = "${var.cluster_name}-pool"
  flavor_name   = var.node_flavor
  desired_nodes = var.node_pool_desired_nodes
  min_nodes     = var.node_pool_min_nodes
  max_nodes     = var.node_pool_max_nodes
  autoscale     = true
}
