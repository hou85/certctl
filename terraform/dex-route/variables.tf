variable "dex_namespace" {
  type        = string
  description = "Namespace where Dex is deployed by the Helm chart (apps/dex/)"
  default     = "dex"
}

variable "gateway_class_name" {
  type        = string
  description = "Envoy Gateway class name (typically 'eg' from envoy-gateway chart)"
  default     = "eg"
}

variable "dex_service_name" {
  type        = string
  description = "Name of the Dex Service to route to (defined in apps/dex/templates/service.yaml)"
  default     = "dex"
}

variable "dex_service_port" {
  type        = number
  description = "Port of the Dex Service (the chart exposes port 80 → 5556)"
  default     = 80
}

variable "tailscale_hostname" {
  description = "Short Tailscale hostname (e.g. 'dex' → dex.<tailnet_domain>)"
  type        = string
  default     = "dex"
}

variable "tailscale_tags" {
  description = "Tailscale tags assigned to the proxy node (must be authorized in your tailnet ACL)"
  type        = string
  default     = "tag:k8s"
}

variable "tailnet_domain" {
  type        = string
  description = "Your tailnet's MagicDNS domain (e.g. tail44be45.ts.net)"
}
