output "painel_url" {
  description = "Link do painel no New Relic."
  value       = newrelic_one_dashboard.mechanicltda.permalink
}

output "politica_alertas_id" {
  value = newrelic_alert_policy.mechanicltda.id
}

output "monitor_saude" {
  description = "Nome do monitor sintetico de /health, ou vazio quando a URL do gateway ainda nao existe."
  value       = local.api_base_url != "" ? local.monitor_saude : ""
}
