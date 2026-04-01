# ─────────────────────────────────────────────────────────────────────────────
# OVHCloud provider / project
# ─────────────────────────────────────────────────────────────────────────────

variable "ovh_endpoint" {
  description = "OVH API endpoint (e.g. ovh-eu, ovh-us, ovh-ca)."
  type        = string
  default     = "ovh-eu"
}

variable "ovh_application_key" {
  description = "OVH API application key."
  type        = string
  sensitive   = true
}

variable "ovh_application_secret" {
  description = "OVH API application secret."
  type        = string
  sensitive   = true
}

variable "ovh_consumer_key" {
  description = "OVH API consumer key."
  type        = string
  sensitive   = true
}

variable "ovh_cloud_project_service" {
  description = "OVHCloud project service name (tenant/project ID shown in the OVH control panel)."
  type        = string
}

variable "region" {
  description = "OVHCloud region where the Kubernetes cluster will be created (e.g. GRA7, DE1, UK1)."
  type        = string
  default     = "GRA7"
}

# ─────────────────────────────────────────────────────────────────────────────
# Kubernetes cluster
# ─────────────────────────────────────────────────────────────────────────────

variable "cluster_name" {
  description = "Name for the OVHCloud managed Kubernetes cluster."
  type        = string
  default     = "sgtm-cluster"
}

variable "kubernetes_version" {
  description = "Kubernetes version to use (e.g. 1.28, 1.29). Leave empty to use the OVHCloud default."
  type        = string
  default     = ""
}

variable "node_flavor" {
  description = "OVHCloud instance flavor for worker nodes (e.g. b3-8, b3-16)."
  type        = string
  default     = "b3-8"
}

variable "node_pool_min_nodes" {
  description = "Minimum number of worker nodes in the auto-scaling pool."
  type        = number
  default     = 1
}

variable "node_pool_max_nodes" {
  description = "Maximum number of worker nodes in the auto-scaling pool."
  type        = number
  default     = 3
}

variable "node_pool_desired_nodes" {
  description = "Desired (initial) number of worker nodes in the pool."
  type        = number
  default     = 1
}

# ─────────────────────────────────────────────────────────────────────────────
# Server-side GTM – general
# ─────────────────────────────────────────────────────────────────────────────

variable "namespace" {
  description = "Kubernetes namespace in which all sGTM resources will be deployed."
  type        = string
  default     = "sgtm"
}

variable "sgtm_image" {
  description = "Container image for the sGTM server."
  type        = string
  default     = "gcr.io/cloud-tagging-10302018/gtm-cloud-image:stable"
}

variable "container_config" {
  description = "Server-side GTM container config ID copied from the GTM UI (Settings → Container config)."
  type        = string
  sensitive   = true
}

variable "enable_https_ingress" {
  description = "Install ingress-nginx and cert-manager, then expose tagging and preview servers via HTTPS Ingress."
  type        = bool
  default     = false
}

variable "letsencrypt_email" {
  description = "Email address used for the Let's Encrypt ACME account when enable_https_ingress is true."
  type        = string
  default     = ""

  validation {
    condition     = !var.enable_https_ingress || (var.letsencrypt_email != "" && can(regex("@", var.letsencrypt_email)))
    error_message = "When enable_https_ingress is true, letsencrypt_email must be set to a valid email address."
  }
}

variable "tagging_server_host" {
  description = "Public DNS host for the tagging server HTTPS endpoint (for example sgtm.example.com)."
  type        = string
  default     = ""

  validation {
    condition     = !var.enable_https_ingress || var.tagging_server_host != ""
    error_message = "When enable_https_ingress is true, tagging_server_host must be set."
  }
}

variable "preview_server_host" {
  description = "Public DNS host for the preview server HTTPS endpoint (for example preview.example.com)."
  type        = string
  default     = ""

  validation {
    condition     = !var.enable_https_ingress || var.preview_server_host != ""
    error_message = "When enable_https_ingress is true, preview_server_host must be set."
  }
}

variable "ingress_nginx_namespace" {
  description = "Namespace where ingress-nginx is installed when enable_https_ingress is true."
  type        = string
  default     = "ingress-nginx"
}

variable "cert_manager_namespace" {
  description = "Namespace where cert-manager is installed when enable_https_ingress is true."
  type        = string
  default     = "cert-manager"
}

variable "ingress_class_name" {
  description = "IngressClass name used by the HTTPS ingress resources."
  type        = string
  default     = "nginx"
}

variable "preview_server_url" {
  description = "HTTPS URL of the preview server used by tagging-server pods (for example https://preview.example.com)."
  type        = string
  default     = ""

  validation {
    condition     = var.enable_https_ingress || can(regex("^https://", var.preview_server_url))
    error_message = "Set preview_server_url to a real HTTPS URL (e.g. https://preview.example.com), or enable_https_ingress=true."
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# Tagging server
# ─────────────────────────────────────────────────────────────────────────────

variable "tagging_server_min_replicas" {
  description = "Minimum number of tagging server pods (HorizontalPodAutoscaler lower bound)."
  type        = number
  default     = 2
}

variable "tagging_server_max_replicas" {
  description = "Maximum number of tagging server pods (HorizontalPodAutoscaler upper bound)."
  type        = number
  default     = 10
}

variable "tagging_server_cpu_request" {
  description = "CPU request for each tagging server pod (e.g. 250m)."
  type        = string
  default     = "250m"
}

variable "tagging_server_cpu_limit" {
  description = "CPU limit for each tagging server pod (e.g. 1000m)."
  type        = string
  default     = "1000m"
}

variable "tagging_server_memory_request" {
  description = "Memory request for each tagging server pod (e.g. 256Mi)."
  type        = string
  default     = "256Mi"
}

variable "tagging_server_memory_limit" {
  description = "Memory limit for each tagging server pod (e.g. 512Mi)."
  type        = string
  default     = "512Mi"
}

variable "tagging_server_cpu_target_utilization" {
  description = "Target average CPU utilisation percentage that triggers HPA scaling."
  type        = number
  default     = 70
}

# ─────────────────────────────────────────────────────────────────────────────
# Preview server
# ─────────────────────────────────────────────────────────────────────────────

variable "preview_server_replicas" {
  description = "Number of preview server pod replicas."
  type        = number
  default     = 1
}

variable "preview_server_public_enabled" {
  description = "Whether to create a public LoadBalancer service for the preview server."
  type        = bool
  default     = true
}

variable "preview_server_cpu_request" {
  description = "CPU request for each preview server pod (e.g. 100m)."
  type        = string
  default     = "100m"
}

variable "preview_server_cpu_limit" {
  description = "CPU limit for each preview server pod (e.g. 500m)."
  type        = string
  default     = "500m"
}

variable "preview_server_memory_request" {
  description = "Memory request for each preview server pod (e.g. 128Mi)."
  type        = string
  default     = "128Mi"
}

variable "preview_server_memory_limit" {
  description = "Memory limit for each preview server pod (e.g. 256Mi)."
  type        = string
  default     = "256Mi"
}
