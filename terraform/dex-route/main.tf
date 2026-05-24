###############################################################################
# dex-route — Gateway Envoy + HTTPRoute pour exposer Dex via Tailscale
#
# Crée une Gateway Envoy dédiée à Dex avec son propre proxy Tailscale
# (dex.<tailnet>), et la HTTPRoute correspondante qui pointe sur le Service
# "dex" déployé par le chart Helm Dex (apps/dex/).
#
# Pré-requis :
#   - Envoy Gateway installé (chart envoy-gateway, controller eg)
#   - Tailscale Operator installé
#   - Le namespace "dex" existe (créé par le chart Helm ou bootstrap-secrets.sh)
#
# Le déploiement de Dex lui-même est géré par ArgoCD via apps/dex/.
# Terraform ne fait QUE provisionner la route.
###############################################################################

resource "kubectl_manifest" "gateway" {
  yaml_body = yamlencode({
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "Gateway"

    metadata = {
      name      = "dex"
      namespace = var.dex_namespace
    }

    spec = {
      gatewayClassName = var.gateway_class_name

      infrastructure = {
        annotations = {
          "tailscale.com/expose"   = "true"
          "tailscale.com/hostname" = var.tailscale_hostname
          "tailscale.com/tags"     = var.tailscale_tags
        }
      }

      listeners = [
        {
          name     = "http"
          protocol = "HTTP"
          port     = 80

          allowedRoutes = {
            namespaces = {
              from = "Same"
            }
          }
        }
      ]
    }
  })
}

resource "kubectl_manifest" "dex_route" {
  yaml_body = yamlencode({
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "HTTPRoute"

    metadata = {
      name      = "dex"
      namespace = var.dex_namespace
    }

    spec = {
      hostnames = [
        "${var.tailscale_hostname}.${var.tailnet_domain}"
      ]

      parentRefs = [
        {
          name        = "dex"
          sectionName = "http"
        }
      ]

      rules = [
        {
          matches = [
            {
              path = {
                type  = "PathPrefix"
                value = "/"
              }
            }
          ]

          backendRefs = [
            {
              name = var.dex_service_name
              port = var.dex_service_port
            }
          ]
        }
      ]
    }
  })

  depends_on = [kubectl_manifest.gateway]
}
