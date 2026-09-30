terraform {
  required_version = ">= 1.9"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "azurerm" {
  features {}

  # Subscription is intentionally not hardcoded. Set ARM_SUBSCRIPTION_ID in your
  # environment (azurerm 4.x requires an explicit subscription) or export it via
  # `az account show --query id -o tsv`.
}
