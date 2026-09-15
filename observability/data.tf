# URL do gateway publicada pelo stack da Lambda. O defaults cobre o caso de o stack
# ainda não ter sido aplicado (state vazio): o plan segue, e o monitor de
# disponibilidade simplesmente não é criado.
data "terraform_remote_state" "lambda" {
  backend = "s3"

  config = {
    bucket = "mechanicltda-terraform-state-788516091173"
    key    = "prod/lambda/terraform.tfstate"
    region = "us-east-1"
  }

  defaults = {
    api_base_url = ""
  }
}

locals {
  api_base_url = trimsuffix(
    var.api_base_url != "" ? var.api_base_url : data.terraform_remote_state.lambda.outputs.api_base_url,
    "/"
  )

  monitor_saude = "${var.cluster_name} - GET /health pelo API Gateway"

  # Filtros reaproveitados nas consultas NRQL dos alertas e do painel.
  filtro_api       = "appName = '${var.app_name_api}' AND transactionType = 'Web'"
  filtro_container = "clusterName = '${var.cluster_name}' AND namespaceName = '${var.namespace_aplicacao}'"
}
