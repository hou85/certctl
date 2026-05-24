output "gateway_name" {
  value       = "dex"
  description = "Name of the Gateway resource for Dex"
}

output "gateway_namespace" {
  value       = var.dex_namespace
  description = "Namespace of the Gateway"
}

output "tailscale_hostname" {
  value       = var.tailscale_hostname
  description = "Short Tailscale hostname"
}

output "fqdn" {
  value       = "${var.tailscale_hostname}.${var.tailnet_domain}"
  description = "Full DNS name (used as OIDC Issuer URL by certctl)"
}

output "issuer_url" {
  value       = "https://${var.tailscale_hostname}.${var.tailnet_domain}"
  description = "OIDC Issuer URL to configure in certctl (used by configure-oidc.sh)"
}
