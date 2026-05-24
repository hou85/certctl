# certctl + Dex (GitOps)

Déploiement K8s de [certctl](https://github.com/ryant71/certctl) avec authentification
OIDC via Dex et backend GitHub, exposé via Tailscale.

## Architecture

```
Utilisateur (navigateur sur tailnet)
    ↓ https://certctl.tail44be45.ts.net
Proxy Tailscale (TCP passthrough, cert auto-signé)
    ↓
certctl pod (TLS 1.3, port 8080)
    ↓ delegation OIDC pour login web
Dex (https://dex.tail44be45.ts.net, terminaison HTTPS Let's Encrypt par Tailscale)
    ↓ backend OAuth2
GitHub
```

## Structure du repo

```
.
├── apps/
│   ├── certctl/                  # Chart Helm certctl
│   │   ├── Chart.yaml
│   │   ├── values.yaml
│   │   └── templates/
│   └── dex/                      # Chart Helm Dex
│       ├── Chart.yaml
│       ├── values.yaml
│       └── templates/
├── argocd-apps/                  # Applications ArgoCD (appliquées à part)
│   ├── certctl.yaml
│   └── dex.yaml
├── scripts/
│   ├── bootstrap-secrets.sh      # Crée les Secrets hors GitOps (une fois)
│   └── configure-oidc.sh         # Configure le provider OIDC dans certctl (une fois)
└── README.md
```

## Procédure de déploiement (premier setup)

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

Crée dans le cluster :
- `certctl/postgres-secret` (password Postgres aléatoire)
- `certctl/certctl-secret` (API key + bootstrap token aléatoires)
- `certctl/certctl-tls` (cert auto-signé pour le serveur HTTPS de certctl)
- `dex/dex-secrets` (credentials GitHub + client secret OIDC Dex↔certctl)

Fichiers locaux persistants dans `~/.certctl/` :
- `tls.crt` / `tls.key` — cert serveur
- `dex-certctl-client-secret` — client secret OIDC

### 3. (Optionnel) Trust le cert auto-signé localement

Pour utiliser curl/Chrome sans `-k` / sans warning :

```bash
# macOS
sudo security add-trusted-cert -d -r trustRoot \
  -k /Library/Keychains/System.keychain ~/.certctl/tls.crt
```

### 4. Apply les Applications ArgoCD

```bash
kubectl apply -f argocd-apps/certctl.yaml
kubectl apply -f argocd-apps/dex.yaml
```

ArgoCD synchronise tout. Surveille dans l'UI ArgoCD ou :

```bash
kubectl get pods -n certctl -w
kubectl get pods -n dex -w
```

### 5. Configurer le provider OIDC dans certctl

⚠️ Attendre que **certctl ET dex** soient Healthy dans ArgoCD avant de lancer.

```bash
./scripts/configure-oidc.sh
```

Le script :
1. Désactive temporairement `selfHeal` ArgoCD sur l'app certctl
2. Bascule certctl en mode démo pour pouvoir créer le provider OIDC
3. POST le provider OIDC via l'API certctl
4. Rebasule certctl en `api-key`
5. Nettoie les permissions résiduelles
6. Réactive `selfHeal`

### 6. Test login

```bash
# Cmd+Q Chrome puis :
open -a "Google Chrome" https://certctl.tail44be45.ts.net/
```

Clique "Sign in with GitHub via Dex" → redirection GitHub → retour authentifié.

## Configuration

### values certctl (`apps/certctl/values.yaml`)

| Variable | Default | Description |
|---|---|---|
| `image.repository` | `ghcr.io/hou85/certctl-server` | Image du serveur certctl |
| `image.tag` | `latest` | Tag de l'image |
| `tailscale.hostname` | `certctl` | Label DNS court (Tailscale construit le FQDN) |
| `tailscale.tailnet` | `tail44be45.ts.net` | Tailnet pour le FQDN du cert TLS |

### values dex (`apps/dex/values.yaml`)

| Variable | Default | Description |
|---|---|---|
| `image.tag` | `v2.41.1` | Version Dex |
| `tailscale.hostname` | `dex` | Label DNS court |
| `tailscale.tailnet` | `tail44be45.ts.net` | Tailnet (utilisé dans issuer URL) |
| `certctl.hostname` | `certctl` | Label DNS court certctl |
| `certctl.tailnet` | `tail44be45.ts.net` | Tailnet certctl (pour la redirectURI) |

## Maintenance

### Rotation du secret client OIDC Dex↔certctl

```bash
# 1. Régénère le secret local
openssl rand -base64 32 > ~/.certctl/dex-certctl-client-secret

# 2. Met à jour le Secret K8s
kubectl create secret generic dex-secrets -n dex \
  --from-literal=github-client-id="$GITHUB_CLIENT_ID" \
  --from-literal=github-client-secret="$GITHUB_CLIENT_SECRET" \
  --from-literal=certctl-client-secret="$(cat ~/.certctl/dex-certctl-client-secret)" \
  --dry-run=client -o yaml | kubectl apply -f -

# 3. Redémarre Dex
kubectl rollout restart deploy/dex -n dex

# 4. Met à jour le provider OIDC dans certctl (relance le script)
./scripts/configure-oidc.sh
```

### Reset complet

```bash
# ⚠️ DESTRUCTIF : supprime toutes les données certctl + dex
kubectl delete namespace certctl dex
kubectl delete -f argocd-apps/

# Puis recommence la procédure de déploiement
```

### Récupérer l'API key certctl

```bash
kubectl get secret -n certctl certctl-secret \
  -o jsonpath='{.data.auth-secret}' | base64 -d
```

## Troubleshooting

### Dex pas accessible

```bash
kubectl logs -n dex -l app=dex --tail=50
kubectl logs -n tailscale -l tailscale.com/parent-resource=dex-tailscale --tail=50
```

### Le dashboard certctl crash en api-key

C'est un bug connu du frontend certctl dans cette version. Le script
`configure-oidc.sh` règle ça en configurant OIDC (le frontend utilise alors
le flow OIDC web au lieu de paniquer sur `api-key` sans provider).

### Le cert TLS dans le navigateur n'est pas trusté

Voir étape 3 ci-dessus, ou ouvre directement `https://certctl.tail44be45.ts.net`
et accepte le warning (cert auto-signé).
