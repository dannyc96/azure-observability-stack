# Remote state backend.
#
# Local state is fine for a demo you deploy and destroy in one sitting. For
# anything shared or long-lived, uncomment this block and point it at a storage
# account provisioned out of band (never by the configuration whose state it
# holds). Run `terraform init -migrate-state` after uncommenting.
#
# terraform {
#   backend "azurerm" {
#     resource_group_name  = "rg-tfstate"
#     storage_account_name = "sttfstatedannyc"
#     container_name       = "tfstate"
#     key                  = "azure-observability-stack.tfstate"
#     use_azuread_auth     = true
#   }
# }
