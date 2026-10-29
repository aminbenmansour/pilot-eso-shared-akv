variable "app" {
  description = "Application name used for identity, federation, and secret prefix matching."
  type        = string
}

variable "env" {
  description = "Environment name (e.g. dev, prod)."
  type        = string
}

variable "location" {
  description = "Azure location where the user-assigned identity is created."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group containing the managed identity and federated credential."
  type        = string
}

variable "oidc_issuer_url" {
  description = "AKS OIDC issuer URL (from the AKS cluster resource)."
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace where the External Secrets Operator service account exists."
  type        = string
}

variable "key_vault_id" {
  description = "Resource ID of the Azure Key Vault."
  type        = string
}
