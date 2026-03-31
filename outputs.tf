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
  value       = try(kubernetes_service_v1.tagging_server_lb.status[0].load_balancer[0].ingress[0].ip, "pending – check 'kubectl get svc -n ${var.namespace} tagging-server-lb'")
}

output "preview_server_cluster_ip" {
  description = "Cluster-internal IP of the preview server service."
  value       = kubernetes_service_v1.preview_server.spec[0].cluster_ip
}

output "namespace" {
  description = "Kubernetes namespace where sGTM resources are deployed."
  value       = kubernetes_namespace_v1.sgtm.metadata[0].name
}
