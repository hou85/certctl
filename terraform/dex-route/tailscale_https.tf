###############################################################################
# Active HTTPS (cert Let's Encrypt) sur le proxy Tailscale dédié à Dex.
#
# Pattern repris de argocd-route :
#   1. Attendre que le proxy Tailscale du Service Envoy soit Ready
#   2. Installer socat dans le pod proxy
#   3. socat forward 127.0.0.1:8080 → Service Envoy du namespace dex
#   4. tailscale serve --bg http://127.0.0.1:8080
#      → Tailscale termine HTTPS sur 443 avec Let's Encrypt automatique
#
# Le Service Envoy et le pod proxy ont des noms générés dynamiquement (hash
# imprévisible). On les découvre via labels au lieu de hardcoder les noms.
###############################################################################

resource "null_resource" "tailscale_https" {
  depends_on = [
    kubectl_manifest.gateway,
    kubectl_manifest.dex_route
  ]

  triggers = {
    gateway_id = kubectl_manifest.gateway.id
    route_id   = kubectl_manifest.dex_route.id
  }

  provisioner "local-exec" {
    command = <<EOT
set -e

DEX_NS="${var.dex_namespace}"
GW_NAME="dex"

echo "Discovering Envoy Service for Gateway $DEX_NS/$GW_NAME..."

ENVOY_SVC=$(kubectl get svc -n envoy-gateway-system \
  -l "gateway.envoyproxy.io/owning-gateway-name=$GW_NAME,gateway.envoyproxy.io/owning-gateway-namespace=$DEX_NS" \
  -o jsonpath='{.items[0].metadata.name}')

if [ -z "$ENVOY_SVC" ]; then
  echo "ERROR: Envoy Service not found for Gateway $DEX_NS/$GW_NAME"
  exit 1
fi

ENVOY_FQDN="$${ENVOY_SVC}.envoy-gateway-system.svc.cluster.local"
echo "Envoy Service FQDN: $ENVOY_FQDN"

echo "Waiting for Tailscale proxy pod (parent-resource=$ENVOY_SVC)..."

kubectl wait \
  -n tailscale \
  --for=condition=Ready pod \
  -l "tailscale.com/parent-resource=$ENVOY_SVC" \
  --timeout=180s

POD=$(kubectl get pod -n tailscale \
  -l "tailscale.com/parent-resource=$ENVOY_SVC" \
  -o jsonpath='{.items[0].metadata.name}')

if [ -z "$POD" ]; then
  echo "ERROR: Tailscale proxy pod not found"
  exit 1
fi

echo "Using pod: $POD"

kubectl exec -n tailscale "$POD" -- sh -c "
set -e

apk add --no-cache socat >/dev/null 2>&1 || true

pkill socat || true

nohup socat \
  TCP-LISTEN:8080,fork,reuseaddr \
  TCP:$ENVOY_FQDN:80 \
  >/tmp/socat.log 2>&1 &

sleep 3

tailscale serve reset || true
tailscale serve --bg http://127.0.0.1:8080
"

echo "✓ tailscale serve configured."
echo "✓ Dex available at https://${var.tailscale_hostname}.${var.tailnet_domain}"
EOT
  }
}
