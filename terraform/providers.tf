terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.10.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.4.0"
    }
  }
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = true
    }
  }
}

# Used to create the workload-identity annotated service accounts. It defaults
# to the current kubeconfig context, so make sure it points at the AKS cluster
# before planning/applying (az aks get-credentials ...).
provider "kubernetes" {}
