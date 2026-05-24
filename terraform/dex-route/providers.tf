terraform {
  required_version = ">= 1.5"

  required_providers {
    kubectl = {
      source  = "alekc/kubectl"
      version = ">= 2.0"
    }
  }
}

# Provider configuré au niveau du root module (envs/ ou ici directement)
# Le module suppose que kubectl est déjà configuré pour pointer sur le bon cluster.
