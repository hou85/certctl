###############################################################################
# Terraform backend
#
# Adapte le bucket/region/key selon ta plateforme. Le state contient des refs
# vers les ressources cluster mais aucun secret.
###############################################################################

terraform {
  backend "http" {}
}
