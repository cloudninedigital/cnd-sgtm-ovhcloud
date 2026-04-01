# ─────────────────────────────────────────────────────────────────────────────
# Namespace
# ─────────────────────────────────────────────────────────────────────────────

locals {
  effective_preview_server_url = var.enable_https_ingress ? "https://${var.preview_server_host}" : var.preview_server_url
}

resource "kubernetes_namespace_v1" "sgtm" {
  depends_on = [ovh_cloud_project_kube_nodepool.sgtm_nodepool]

  metadata {
    name = var.namespace
    labels = {
      app = "sgtm"
    }
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# Preview server – Deployment
# ─────────────────────────────────────────────────────────────────────────────

resource "kubernetes_deployment_v1" "preview_server" {
  depends_on = [kubernetes_namespace_v1.sgtm]

  metadata {
    name      = "preview-server"
    namespace = kubernetes_namespace_v1.sgtm.metadata[0].name
    labels = {
      app       = "sgtm"
      component = "preview-server"
    }
  }

  spec {
    replicas = var.preview_server_replicas

    selector {
      match_labels = {
        app       = "sgtm"
        component = "preview-server"
      }
    }

    template {
      metadata {
        labels = {
          app       = "sgtm"
          component = "preview-server"
        }
      }

      spec {
        container {
          name              = "preview-server"
          image             = var.sgtm_image
          image_pull_policy = "Always"

          port {
            container_port = 8080
            name           = "http"
          }

          env {
            name  = "CONTAINER_CONFIG"
            value = var.container_config
          }

          env {
            name  = "RUN_AS_PREVIEW_SERVER"
            value = "true"
          }

          resources {
            requests = {
              cpu    = var.preview_server_cpu_request
              memory = var.preview_server_memory_request
            }
            limits = {
              cpu    = var.preview_server_cpu_limit
              memory = var.preview_server_memory_limit
            }
          }

          liveness_probe {
            http_get {
              path = "/healthy"
              port = 8080
            }
            initial_delay_seconds = 10
            period_seconds        = 15
          }

          readiness_probe {
            http_get {
              path = "/healthy"
              port = 8080
            }
            initial_delay_seconds = 5
            period_seconds        = 10
          }
        }
      }
    }
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# Preview server – ClusterIP Service
# ─────────────────────────────────────────────────────────────────────────────

resource "kubernetes_service_v1" "preview_server" {
  depends_on = [kubernetes_namespace_v1.sgtm]

  metadata {
    name      = "preview-server"
    namespace = kubernetes_namespace_v1.sgtm.metadata[0].name
    labels = {
      app       = "sgtm"
      component = "preview-server"
    }
  }

  spec {
    selector = {
      app       = "sgtm"
      component = "preview-server"
    }

    port {
      port        = 80
      target_port = 8080
      protocol    = "TCP"
      name        = "http"
    }

    type = "ClusterIP"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# Preview server – Public LoadBalancer Service (optional)
# ─────────────────────────────────────────────────────────────────────────────

resource "kubernetes_service_v1" "preview_server_lb" {
  count = var.preview_server_public_enabled ? 1 : 0

  depends_on = [kubernetes_namespace_v1.sgtm]

  metadata {
    name      = "preview-server-lb"
    namespace = kubernetes_namespace_v1.sgtm.metadata[0].name
    labels = {
      app       = "sgtm"
      component = "preview-server"
    }
    annotations = {}
  }

  spec {
    selector = {
      app       = "sgtm"
      component = "preview-server"
    }

    port {
      port        = 80
      target_port = 8080
      protocol    = "TCP"
      name        = "http"
    }

    type = "LoadBalancer"
  }

  timeouts {
    create = "10m"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# Tagging server – Deployment
# ─────────────────────────────────────────────────────────────────────────────

resource "kubernetes_deployment_v1" "tagging_server" {
  depends_on = [kubernetes_service_v1.preview_server]

  metadata {
    name      = "tagging-server"
    namespace = kubernetes_namespace_v1.sgtm.metadata[0].name
    labels = {
      app       = "sgtm"
      component = "tagging-server"
    }
  }

  spec {
    # Initial replica count – the HPA will take over after apply.
    replicas = var.defer_tagging_server_rollout ? 0 : var.tagging_server_min_replicas

    selector {
      match_labels = {
        app       = "sgtm"
        component = "tagging-server"
      }
    }

    template {
      metadata {
        labels = {
          app       = "sgtm"
          component = "tagging-server"
        }
      }

      spec {
        container {
          name              = "tagging-server"
          image             = var.sgtm_image
          image_pull_policy = "Always"

          port {
            container_port = 8080
            name           = "http"
          }

          env {
            name  = "CONTAINER_CONFIG"
            value = var.container_config
          }

          # The tagging server requires a valid HTTPS preview URL.
          env {
            name  = "PREVIEW_SERVER_URL"
            value = local.effective_preview_server_url
          }

          resources {
            requests = {
              cpu    = var.tagging_server_cpu_request
              memory = var.tagging_server_memory_request
            }
            limits = {
              cpu    = var.tagging_server_cpu_limit
              memory = var.tagging_server_memory_limit
            }
          }

          liveness_probe {
            http_get {
              path = "/healthy"
              port = 8080
            }
            initial_delay_seconds = 10
            period_seconds        = 15
          }

          readiness_probe {
            http_get {
              path = "/healthy"
              port = 8080
            }
            initial_delay_seconds = 5
            period_seconds        = 10
          }
        }
      }
    }
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# Tagging server – LoadBalancer Service
# ─────────────────────────────────────────────────────────────────────────────

resource "kubernetes_service_v1" "tagging_server_lb" {
  depends_on = [kubernetes_namespace_v1.sgtm]

  metadata {
    name      = "tagging-server-lb"
    namespace = kubernetes_namespace_v1.sgtm.metadata[0].name
    labels = {
      app       = "sgtm"
      component = "tagging-server"
    }
    # OVHCloud provisions a public load balancer for services of type LoadBalancer.
    # The external IP that is assigned should be used as the target of an A record
    # in your DNS zone (e.g. sgtm.example.com → <EXTERNAL-IP>).
    annotations = {}
  }

  spec {
    selector = {
      app       = "sgtm"
      component = "tagging-server"
    }

    port {
      port        = 80
      target_port = 8080
      protocol    = "TCP"
      name        = "http"
    }

    # TLS termination should be handled externally (e.g. via an Ingress
    # controller with cert-manager, or by attaching an SSL certificate to
    # the OVHCloud load balancer in the control panel).  Do not add a bare
    # port-443 → 8080 mapping here as it would forward HTTPS client traffic
    # to an HTTP backend without decryption.

    type = "LoadBalancer"
  }

  # Allow time for OVHCloud to provision the load balancer.
  timeouts {
    create = "10m"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# Tagging server – HorizontalPodAutoscaler
# ─────────────────────────────────────────────────────────────────────────────

resource "kubernetes_horizontal_pod_autoscaler_v2" "tagging_server" {
  count = var.defer_tagging_server_rollout ? 0 : 1

  depends_on = [kubernetes_deployment_v1.tagging_server]

  metadata {
    name      = "tagging-server-hpa"
    namespace = kubernetes_namespace_v1.sgtm.metadata[0].name
    labels = {
      app       = "sgtm"
      component = "tagging-server"
    }
  }

  spec {
    min_replicas = var.tagging_server_min_replicas
    max_replicas = var.tagging_server_max_replicas

    scale_target_ref {
      api_version = "apps/v1"
      kind        = "Deployment"
      name        = kubernetes_deployment_v1.tagging_server.metadata[0].name
    }

    metric {
      type = "Resource"
      resource {
        name = "cpu"
        target {
          type                = "Utilization"
          average_utilization = var.tagging_server_cpu_target_utilization
        }
      }
    }
  }
}
