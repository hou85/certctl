# certctl + Dex (GitOps + Gateway API)

Déploiement K8s de [certctl](https://github.com/ryant71/certctl) avec authentification
OIDC via Dex et backend GitHub, exposé via la Gateway Envoy + Tailscale.

## Architecture

```
Utilisateur (sur tailnet)
  ↓ certctl.tail44be45.ts.net  /  dex.tail44be45.ts.net
Proxy Tailscale "argocd" (HTTPS Let's Encrypt, fait par la Gateway Envoy via tailscale.com/expose)
  ↓ HTTP plain
Gateway Envoy "main" (namespace argocd, listener http:80)
  ↓ routage par hostname (HTTPRoute)
Service certctl (ClusterIP) ou Service dex (ClusterIP)
```

Le proxy Tailscale est attaché au pod Envoy de la Gateway via
`Gateway.spec.infrastructure.annotations`. Tailscale termine HTTPS avec un cert
Let's Encrypt automatique pour chaque hostname `*.tail44be45.ts.net`.

## Structure

```
.
├── apps/
│   ├── certctl/                  # Chart Helm certctl
│   │   ├── Chart.yaml, values.yaml
│   │   └── templates/
│   └── dex/                      # Chart Helm Dex
│       ├── Chart.yaml, values.yaml
│       └── templates/
│           ├── deployment.yaml
│           ├── service.yaml
│           ├── httproute.yaml    # ← route via la Gateway Envoy
│           ├── configmap.yaml
│           ├── rbac.yaml
│           └── namespace.yaml
├── argocd-apps/                  # Applications ArgoCD
│   ├── certctl.yaml
│   └── dex.yaml
├── scripts/
│   ├── bootstrap-secrets.sh
│   └── configure-oidc.sh
└── README.md
```

## Prérequis cluster

- **Envoy Gateway** installé (controller `gateway.envoyproxy.io/gatewayclass-controller`)
- **Gateway `main`** dans le namespace `argocd` avec :
  - `infrastructure.annotations` contenant `tailscale.com/expose: "true"` et `tailscale.com/hostname`
  - Listener `http` sur le port 80
  - `allowedRoutes.namespaces.from: All` (pour permettre aux HTTPRoute d'être dans d'autres namespaces)
- **Tailscale Operator** installé avec MagicDNS + HTTPS activés sur le tailnet

### Ouvrir la Gateway aux routes cross-namespace

Si ta Gateway a `from: Same`, patche-la pour permettre `from: All` :

```bash
kubectl patch gateway main -n argocd --type merge -p '{
  "spec": {
    "listeners": [{
      "name": "http",
      "port": 80,
      "protocol": "HTTP",
      "allowedRoutes": {
        "namespaces": {"from": "All"}
      }
    }]
  }
}'
```

## Procédure de déploiement

### 1. Créer l'OAuth App GitHub

1. https://github.com/settings/developers → **New OAuth App**
2. Remplir :
   - **Application name** : `certctl-dex`
   - **Homepage URL** : `https://dex.tail44be45.ts.net`
   - **Authorization callback URL** : `https://dex.tail44be45.ts.net/callback`
3. Note le **Client ID** et génère un **Client Secret**

### 2. Bootstrap des Secrets (hors GitOps)

```bash
export GITHUB_CLIENT_ID="Iv1.xxxxxxxxxxxxxxxx"
export GITHUB_CLIENT_SECRET="xxxxxxxxxxxxxxxxxxxxxxxxx"

./scripts/bootstrap-secrets.sh
```

### 3. Apply les Applications ArgoCD

```bash
kubectl apply -f argocd-apps/certctl.yaml
kubectl apply -f argocd-apps/dex.yaml
```

### 4. Vérifier l'accessibilité

```bash
# Attendre que tout soit synced + healthy dans ArgoCD
kubectl get application -n argocd

# Vérifier que Dex répond via le hostname Tailscale
curl -s https://dex.tail44be45.ts.net/.well-known/openid-configuration | jq | head -10
```

### 5. Configurer le provider OIDC dans certctl

```bash
./scripts/configure-oidc.sh
```

### 6. Test login

```bash
osascript -e 'tell application "Google Chrome" to quit'
open -a "Google Chrome" https://certctl.tail44be45.ts.net/
```

## Maintenance

### Récupérer l'API key certctl

```bash
kubectl get secret -n certctl certctl-secret \
  -o jsonpath='{.data.auth-secret}' | base64 -d
```

### Reset complet (destructif)

```bash
kubectl delete namespace certctl dex
kubectl delete -f argocd-apps/
# Puis recommencer la procédure de déploiement
```
