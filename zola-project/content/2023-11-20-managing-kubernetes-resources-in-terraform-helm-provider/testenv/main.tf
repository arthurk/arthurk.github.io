provider "helm" {
  kubernetes {
    config_path = "~/.kube/config"
  }
  # experiments {
  #   manifest = true
  # }
}

resource "helm_release" "istio_base" {
  name             = "istio-base"
  repository       = "https://istio-release.storage.googleapis.com/charts"
  chart            = "base"
  namespace        = "istio-system"
  create_namespace = true
  version          = "1.20.0"
}

resource "helm_release" "istiod" {
  name             = "istiod"
  repository       = "https://istio-release.storage.googleapis.com/charts"
  chart            = "istiod"
  namespace        = "istio-system"
  create_namespace = true
  version          = "1.20.0"

  set { name  = "pilot.resources.requests.memory", value = "100Mi" }


  # to install the CRDs first
  depends_on = [helm_release.istio_base]
}

# resource "helm_release" "grafana" {
#   name             = "grafana"
#   repository       = "https://grafana.github.io/helm-charts"
#   chart            = "grafana"
#   version          = "7.0.6"
#   namespace        = "grafana"
#   create_namespace = true
#
#   set {
#     name = "grafana\\.ini.server.root_url"
#     value = "htps://www.example.com"
#   }
#
#   # set_sensitive {
#   #   name = "grafana\\.ini.server.auth\\.github.client_secret"
#   #   value = "secret"
#   # }
# }

# resource "helm_release" "argocd" {
#   name             = "argocd"
#   repository       = "https://argoproj.github.io/argo-helm"
#   chart            = "argo-cd"
#   version          = "5.51.1"
#   namespace        = "default"
#
# }

# resource "helm_release" "airflow" {
#   name             = "airflow"
#   repository       = "https://airflow.apache.org"
#   chart            = "airflow"
#   version          = "1.11.0"
#   namespace        = "default"
#
#   wait = false
# }

# resource "helm_release" "cert-manager" {
#   name             = "cert-manager"
#   repository       = "https://charts.jetstack.io"
#   chart            = "cert-manager"
#   version          = "1.13.2"
#   namespace        = "default"
#
#   values = [<<EOT
#     installCRDs: true
# EOT
# ]
# }

# resource "helm_release" "mastodon" {
#   name             = "mastodon"
#   chart            = "./chart"
#   version          = "4.0.0"
#   namespace        = "default"
#
#   set {
#     name = "mastodon.secrets.secret_key_base"
#     value = "lol"
#   }
#   set {
#     name = "mastodon.secrets.otp_secret"
#     value = "lol"
#   }
#   set {
#     name = "mastodon.secrets.vapid.private_key"
#     value = "lol"
#   }
#   set {
#     name = "mastodon.secrets.vapid.public_key"
#     value = "lol"
#   }
# }


# resource "helm_release" "kube-prometheus-stack" {
#   name             = "kube-prometheus-stack"
#   repository       = "https://prometheus-community.github.io/helm-charts"
#   chart            = "kube-prometheus-stack"
#   version          = "54.0.1"
#   namespace        = "default"
#
#   set {
#     name = "alertmanager.enabled"
#     value = ""
#   }
# }
