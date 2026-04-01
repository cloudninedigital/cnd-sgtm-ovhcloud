output "cluster_id" {
  description = "OVHCloud Kubernetes cluster ID."
  value       = ovh_cloud_project_kube.sgtm_cluster.id
}

output "cluster_status" {
  description = "Current status of the OVHCloud Kubernetes cluster."
  value       = ovh_cloud_project_kube.sgtm_cluster.status
}

output "kubernetes_version" {
  description = "Kubernetes version running on the cluster."
  value       = ovh_cloud_project_kube.sgtm_cluster.version
}

output "tagging_server_load_balancer_ip" {
  description = "Public IP address of the tagging server load balancer. Map this to an A record in your DNS configuration."
  value       =  !var.enable_https_ingress ? try(kubernetes_service_v1.tagging_server_lb.status[0].load_balancer[0].ingress[0].ip, "pending – check 'kubectl get svc -n ${var.namespace} tagging-server-lb'") : "disabled"
}

output "tagging_server_public_url" {
  description = "Public URL for the tagging server. Uses the load balancer hostname when present, otherwise falls back to a nip.io placeholder based on the external IP."
  value = try(
    "http://${kubernetes_service_v1.tagging_server_lb.status[0].load_balancer[0].ingress[0].hostname}",
    "http://${kubernetes_service_v1.tagging_server_lb.status[0].load_balancer[0].ingress[0].ip}.nip.io",
    "pending – check 'kubectl get svc -n ${var.namespace} tagging-server-lb'"
  )
}

output "tagging_server_https_url" {
  description = "HTTPS URL for tagging server when enable_https_ingress is true."
  value       = var.enable_https_ingress ? "https://${var.tagging_server_host}" : "disabled"
}

output "preview_server_cluster_ip" {
  description = "Cluster-internal IP of the preview server service."
  value       = kubernetes_service_v1.preview_server.spec[0].cluster_ip
}

output "preview_server_load_balancer_ip" {
  description = "Public IP address of the preview server load balancer when enabled."
  value = var.preview_server_public_enabled && !var.enable_https_ingress ? try(
    kubernetes_service_v1.preview_server_lb[0].status[0].load_balancer[0].ingress[0].ip,
    "pending - check 'kubectl get svc -n ${var.namespace} preview-server-lb'"
  ) : "disabled"
}

output "preview_server_public_url" {
  description = "Public preview endpoint for testing when preview_server_public_enabled is true. This is HTTP; use your own DNS plus TLS for production preview_server_url."
  value = var.preview_server_public_enabled ? try(
    "http://${kubernetes_service_v1.preview_server_lb[0].status[0].load_balancer[0].ingress[0].hostname}",
    "http://${kubernetes_service_v1.preview_server_lb[0].status[0].load_balancer[0].ingress[0].ip}.nip.io",
    "pending - check 'kubectl get svc -n ${var.namespace} preview-server-lb'"
  ) : "disabled"
}

output "preview_server_https_url" {
  description = "HTTPS URL for preview server when enable_https_ingress is true."
  value       = var.enable_https_ingress ? "https://${var.preview_server_host}" : "disabled"
}

output "ingress_controller_load_balancer_ip" {
  description = "Ingress controller public IP when enable_https_ingress is true. Point your DNS A records to this value."
  value = var.enable_https_ingress ? try(
    data.kubernetes_service_v1.ingress_nginx_controller[0].status[0].load_balancer[0].ingress[0].ip,
    "pending - check 'kubectl get svc -n ${var.ingress_nginx_namespace} ingress-nginx-controller'"
  ) : "disabled"
}

output "ingress_controller_load_balancer_hostname" {
  description = "Ingress controller public hostname when enable_https_ingress is true (some providers use hostname instead of IP)."
  value = var.enable_https_ingress ? try(
    data.kubernetes_service_v1.ingress_nginx_controller[0].status[0].load_balancer[0].ingress[0].hostname,
    "pending"
  ) : "disabled"
}

output "namespace" {
  description = "Kubernetes namespace where sGTM resources are deployed."
  value       = kubernetes_namespace_v1.sgtm.metadata[0].name
}
