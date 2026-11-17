# Monitor de ping (SIMPLE) em /health pela URL pública do gateway. Monitores de ping
# não consomem a cota de checagens sintéticas do plano gratuito, então a checagem a
# cada 5 minutos não gera custo.
#
# O /health passa por todos os saltos da entrada — API Gateway, VPC Link, ALB interno,
# NodePort e pod —, então ele mede o uptime percebido por quem consome a API, e não só
# o de um componente.
resource "newrelic_synthetics_monitor" "saude_api" {
  count = local.api_base_url != "" ? 1 : 0

  name   = local.monitor_saude
  type   = "SIMPLE"
  status = "ENABLED"
  period = "EVERY_5_MINUTES"
  uri    = "${local.api_base_url}/health"

  locations_public = ["US_EAST_1", "SA_EAST_1"]

  verify_ssl                = true
  treat_redirect_as_failure = true
}

# O state da observabilidade foi recriado depois que o monitor já existia na conta do
# New Relic, e o nome do monitor é único: sem adotar o existente, o apply falha com
# "Monitor name already exists". O bloco abaixo procura o monitor pelo nome e o importa
# para o state. Depois de importado, o import não faz mais nada. Em uma conta nova, sem
# o monitor, rode com TF_VAR_adotar_monitor_existente=false.
data "newrelic_entity" "monitor_saude_existente" {
  count = var.adotar_monitor_existente && local.api_base_url != "" ? 1 : 0

  name   = local.monitor_saude
  domain = "SYNTH"
  type   = "MONITOR"
}

import {
  for_each = { for m in data.newrelic_entity.monitor_saude_existente : "saude_api" => m.guid }
  to       = newrelic_synthetics_monitor.saude_api[0]
  id       = each.value
}
