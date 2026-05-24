# terraform/

Infrastructure de routage pour Dex, gérée par Terraform.

## Modules

### `dex-route/`

Provisionne la **Gateway Envoy** + **HTTPRoute** + **`tailscale serve`** qui
expose le Service `dex` (déployé séparément par ArgoCD via `apps/dex/`) sur
`https://dex.<tailnet>` avec un cert Let's Encrypt automatique.

#### Pré-requis cluster

- **Envoy Gateway** installé (provisionné par le repo `argocd-project`)
- **Tailscale Operator** installé (idem)
- Le namespace `dex` existe (créé par `scripts/bootstrap-secrets.sh` ou le chart Helm via ArgoCD)

#### Usage direct (ce dossier comme root module)

```bash
cd terraform/dex-route

# Configure le backend (adapte bucket/region dans backend.tf)
terraform init

# Vérifie le plan
terraform plan

# Applique
terraform apply
```

#### Usage comme module depuis un autre repo

```hcl
module "dex_route" {
  source = "git::https://gitlab-1.tail44be45.ts.net/infra/certctl.git//terraform/dex-route?ref=main"

  dex_namespace      = "dex"
  gateway_class_name = "eg"
  tailscale_hostname = "dex"
  tailnet_domain     = "tail44be45.ts.net"
}
```

#### Outputs

- `fqdn` — ex. `dex.tail44be45.ts.net`
- `issuer_url` — ex. `https://dex.tail44be45.ts.net` (à utiliser pour configurer OIDC dans certctl)
- `gateway_name`, `gateway_namespace` — refs pour debugging

#### Variables

| Variable | Default | Description |
|---|---|---|
| `dex_namespace` | `dex` | Namespace du Service Dex |
| `gateway_class_name` | `eg` | Envoy Gateway class |
| `dex_service_name` | `dex` | Service ciblé par la HTTPRoute |
| `dex_service_port` | `80` | Port du Service |
| `tailscale_hostname` | `dex` | Label DNS court |
| `tailscale_tags` | `tag:k8s` | Tags Tailscale du proxy |
| `tailnet_domain` | (requis) | Ton tailnet (ex: `tail44be45.ts.net`) |

#### Ordre de déploiement

Dans cet ordre :

1. **Plateforme** (repo `argocd-project`) : Envoy Gateway + Tailscale Operator + ArgoCD
2. **Bootstrap secrets** (ce repo) : `scripts/bootstrap-secrets.sh`
3. **dex-route Terraform** (ce dossier) : crée Gateway + HTTPRoute + tailscale serve
4. **ArgoCD apps** : `kubectl apply -f argocd-apps/dex.yaml` → déploie le chart Helm Dex
   (le Service `dex` apparaît, la HTTPRoute trouve son backend)
5. **OIDC config** : `scripts/configure-oidc.sh` → enregistre Dex comme provider dans certctl

L'ordre 3-4 est commutatif : tu peux déployer le chart Dex avant Terraform sans risque,
la HTTPRoute matchera juste rien tant que le Service `dex` n'existe pas.
