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
