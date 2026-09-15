# Stack separado do infra/ de propósito: usa outro provider (New Relic) com outra
# credencial, e um plan do cluster não pode falhar porque a chave do New Relic não
# está configurada — nem o contrário.
terraform {
  required_version = ">= 1.10.0"

  required_providers {
    newrelic = {
      source  = "newrelic/newrelic"
      version = "~> 3.0"
    }
  }

  backend "s3" {
    bucket       = "mechanicltda-terraform-state-788516091173"
    key          = "prod/observability/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}

provider "newrelic" {
  account_id = var.newrelic_account_id
  api_key    = var.newrelic_api_key
  region     = var.newrelic_region
}
