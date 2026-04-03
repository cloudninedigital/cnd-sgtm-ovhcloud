# ─────────────────────────────────────────────────────────────────────────────
# Optional HTTPS ingress stack (ingress-nginx + cert-manager + Ingress)
# ─────────────────────────────────────────────────────────────────────────────

resource "helm_release" "ingress_nginx" {
  count = var.enable_https_ingress ? 1 : 0

  name             = "ingress-nginx"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  namespace        = var.ingress_nginx_namespace
  create_namespace = true
  wait             = true
  timeout          = var.helm_release_timeout_seconds

  set = [
    {
      name  = "controller.service.type"
      value = "LoadBalancer"
    },
    {
      name  = "controller.ingressClassResource.name"
      value = var.ingress_class_name
    },
    {
      name  = "controller.ingressClass"
      value = var.ingress_class_name
    }
  ]

  depends_on = [ovh_cloud_project_kube_nodepool.sgtm_nodepool]
}

resource "helm_release" "cert_manager" {
  count = var.enable_https_ingress ? 1 : 0

  name             = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  namespace        = var.cert_manager_namespace
  create_namespace = true
  wait             = true
  timeout          = var.helm_release_timeout_seconds

  set = [
    {
      name  = "installCRDs"
      value = "true"
    }
  ]

  depends_on = [helm_release.ingress_nginx]
}

resource "time_sleep" "wait_for_cert_manager_crds" {
  count = var.enable_https_ingress ? 1 : 0

  create_duration = "30s"

  depends_on = [helm_release.cert_manager]
}

resource "kubernetes_manifest" "letsencrypt_cluster_issuer" {
  count = var.enable_https_ingress && var.create_letsencrypt_cluster_issuer ? 1 : 0

  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = {
      name = "letsencrypt-http01"
    }
    spec = {
      acme = {
        email  = var.letsencrypt_email
        server = "https://acme-v02.api.letsencrypt.org/directory"
        privateKeySecretRef = {
          name = "letsencrypt-http01-account-key"
        }
        solvers = [
          {
            http01 = {
              ingress = {
                class = var.ingress_class_name
              }
            }
          }
        ]
      }
    }
  }

  depends_on = [time_sleep.wait_for_cert_manager_crds]
}

resource "kubernetes_ingress_v1" "tagging_server" {
  count = var.enable_https_ingress ? 1 : 0

  metadata {
    name      = "tagging-server"
    namespace = kubernetes_namespace_v1.sgtm.metadata[0].name
    annotations = {
      "cert-manager.io/cluster-issuer" = "letsencrypt-http01"
    }
  }

  spec {
    ingress_class_name = var.ingress_class_name

    tls {
      hosts       = [var.tagging_server_host]
      secret_name = "tagging-server-tls"
    }

    rule {
      host = var.tagging_server_host

      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = kubernetes_service_v1.tagging_server_lb.metadata[0].name
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }

  depends_on = [helm_release.cert_manager]
}

resource "kubernetes_ingress_v1" "preview_server" {
  count = var.enable_https_ingress ? 1 : 0

  metadata {
    name      = "preview-server"
    namespace = kubernetes_namespace_v1.sgtm.metadata[0].name
    annotations = {
      "cert-manager.io/cluster-issuer"                = "letsencrypt-http01"
      "nginx.ingress.kubernetes.io/proxy-read-timeout" = "75"
    }
  }

  spec {
    ingress_class_name = var.ingress_class_name

    tls {
      hosts       = [var.preview_server_host]
      secret_name = "preview-server-tls"
    }

    rule {
      host = var.preview_server_host

      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = kubernetes_service_v1.preview_server.metadata[0].name
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }

  depends_on = [helm_release.cert_manager]
}

data "kubernetes_service_v1" "ingress_nginx_controller" {
  count = var.enable_https_ingress ? 1 : 0

  metadata {
    name      = "ingress-nginx-controller"
    namespace = var.ingress_nginx_namespace
  }

  depends_on = [helm_release.ingress_nginx]
}
