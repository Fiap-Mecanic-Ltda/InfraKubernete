# Alertas do desafio: latência das APIs, consumo de recursos do Kubernetes,
# healthcheck/uptime e falhas no processamento de ordens de serviço — mais falha nas
# integrações, que o painel também exige.
#
# Uma incidência por condição (PER_CONDITION): latência alta e falha de OS ao mesmo
# tempo são dois problemas, não um só.

resource "newrelic_alert_policy" "mechanicltda" {
  name                = "${var.cluster_name} - MechanicLtda"
  incident_preference = "PER_CONDITION"
}

# ── Latência e erros da API (APM) ────────────────────────────────────────────

resource "newrelic_nrql_alert_condition" "latencia_api" {
  account_id  = var.newrelic_account_id
  policy_id   = newrelic_alert_policy.mechanicltda.id
  type        = "static"
  name        = "API: latencia p95 acima de ${var.latencia_p95_limite_ms} ms"
  description = "Requisicoes Web da API mais lentas que o limite por 5 minutos seguidos. Veja o painel APIs para a transacao responsavel."
  enabled     = true

  nrql {
    query = "SELECT percentile(duration, 95) * 1000 FROM Transaction WHERE ${local.filtro_api}"
  }

  critical {
    operator              = "above"
    threshold             = var.latencia_p95_limite_ms
    threshold_duration    = 300
    threshold_occurrences = "all"
  }

  aggregation_window           = 60
  aggregation_method           = "event_flow"
  aggregation_delay            = 120
  violation_time_limit_seconds = 86400
}

resource "newrelic_nrql_alert_condition" "taxa_erro_api" {
  account_id  = var.newrelic_account_id
  policy_id   = newrelic_alert_policy.mechanicltda.id
  type        = "static"
  name        = "API: taxa de erro acima de ${var.taxa_erro_limite_percentual}%"
  description = "Percentual de requisicoes com erro (5xx ou excecao nao tratada) por 5 minutos seguidos."
  enabled     = true

  nrql {
    query = "SELECT percentage(count(*), WHERE error IS true) FROM Transaction WHERE ${local.filtro_api}"
  }

  critical {
    operator              = "above"
    threshold             = var.taxa_erro_limite_percentual
    threshold_duration    = 300
    threshold_occurrences = "all"
  }

  aggregation_window           = 60
  aggregation_method           = "event_flow"
  aggregation_delay            = 120
  violation_time_limit_seconds = 86400
}

# ── Processamento de ordens de serviço (eventos de negócio) ──────────────────

resource "newrelic_nrql_alert_condition" "falha_processamento_os" {
  account_id  = var.newrelic_account_id
  policy_id   = newrelic_alert_policy.mechanicltda.id
  type        = "static"
  name        = "OS: falha no processamento"
  description = <<-EOT
    Uma operação do ciclo de vida da OS (criar, diagnosticar, aprovar, executar,
    finalizar, entregar) falhou por erro de sistema. Violações de regra de negócio
    (categoria Negocio) não entram: já viram 400 para quem chamou.
  EOT
  enabled     = true

  nrql {
    query = "SELECT count(*) FROM OrdemServicoFalha WHERE categoria = 'Sistema'"
  }

  critical {
    operator              = "above"
    threshold             = 0
    threshold_duration    = 300
    threshold_occurrences = "at_least_once"
  }

  # Evento esparso: sem fill, uma janela sem falha não teria valor e o incidente não
  # fecharia sozinho.
  fill_option = "static"
  fill_value  = 0

  aggregation_window           = 300
  aggregation_method           = "event_timer"
  aggregation_timer            = 60
  violation_time_limit_seconds = 86400
}

resource "newrelic_nrql_alert_condition" "falha_integracao" {
  account_id  = var.newrelic_account_id
  policy_id   = newrelic_alert_policy.mechanicltda.id
  type        = "static"
  name        = "Integracoes: falha no envio de e-mail"
  description = "Notificacao de status ou link de aprovacao de OS nao foi enviado ao cliente. A transicao de status aconteceu, mas o cliente nao foi avisado."
  enabled     = true

  nrql {
    query = "SELECT count(*) FROM FalhaIntegracao"
  }

  critical {
    operator              = "above"
    threshold             = 0
    threshold_duration    = 300
    threshold_occurrences = "at_least_once"
  }

  fill_option = "static"
  fill_value  = 0

  aggregation_window           = 300
  aggregation_method           = "event_timer"
  aggregation_timer            = 60
  violation_time_limit_seconds = 86400
}

# ── Kubernetes (integração do cluster) ───────────────────────────────────────

resource "newrelic_nrql_alert_condition" "cpu_container" {
  account_id  = var.newrelic_account_id
  policy_id   = newrelic_alert_policy.mechanicltda.id
  type        = "static"
  name        = "Kubernetes: CPU do container acima de ${var.uso_recurso_limite_percentual}% do limit"
  description = "Uso de CPU em relacao ao limit por 10 minutos. Se o HPA ja estiver no maximo de replicas, falta capacidade no cluster."
  enabled     = true

  nrql {
    query = "SELECT average(cpuCoresUtilization) FROM K8sContainerSample WHERE ${local.filtro_container} FACET podName"
  }

  critical {
    operator              = "above"
    threshold             = var.uso_recurso_limite_percentual
    threshold_duration    = 600
    threshold_occurrences = "all"
  }

  aggregation_window           = 60
  aggregation_method           = "event_flow"
  aggregation_delay            = 120
  violation_time_limit_seconds = 86400
}

resource "newrelic_nrql_alert_condition" "memoria_container" {
  account_id  = var.newrelic_account_id
  policy_id   = newrelic_alert_policy.mechanicltda.id
  type        = "static"
  name        = "Kubernetes: memoria do container acima de ${var.uso_recurso_limite_percentual}% do limit"
  description = "Working set perto do limit por 10 minutos: o proximo passo e o OOMKill do pod."
  enabled     = true

  nrql {
    query = "SELECT average(memoryWorkingSetUtilization) FROM K8sContainerSample WHERE ${local.filtro_container} FACET podName"
  }

  critical {
    operator              = "above"
    threshold             = var.uso_recurso_limite_percentual
    threshold_duration    = 600
    threshold_occurrences = "all"
  }

  aggregation_window           = 60
  aggregation_method           = "event_flow"
  aggregation_delay            = 120
  violation_time_limit_seconds = 86400
}

resource "newrelic_nrql_alert_condition" "reinicio_container" {
  account_id  = var.newrelic_account_id
  policy_id   = newrelic_alert_policy.mechanicltda.id
  type        = "static"
  name        = "Kubernetes: container reiniciando"
  description = "O container reiniciou (crash, OOMKill ou liveness falhando em /health)."
  enabled     = true

  nrql {
    query = "SELECT max(restartCountDelta) FROM K8sContainerSample WHERE ${local.filtro_container} FACET podName"
  }

  critical {
    operator              = "above"
    threshold             = 0
    threshold_duration    = 300
    threshold_occurrences = "at_least_once"
  }

  aggregation_window           = 60
  aggregation_method           = "event_flow"
  aggregation_delay            = 120
  violation_time_limit_seconds = 86400
}

# ── Disponibilidade (monitor sintético em /health) ───────────────────────────

resource "newrelic_nrql_alert_condition" "healthcheck" {
  count = local.api_base_url != "" ? 1 : 0

  account_id  = var.newrelic_account_id
  policy_id   = newrelic_alert_policy.mechanicltda.id
  type        = "static"
  name        = "Disponibilidade: /health falhando pelo API Gateway"
  description = "Duas checagens seguidas falharam. O caminho testado passa por gateway, VPC Link, ALB e pods: qualquer um deles fora derruba o check."
  enabled     = true

  nrql {
    query = "SELECT filter(count(*), WHERE result = 'FAILED') FROM SyntheticCheck WHERE monitorName = '${local.monitor_saude}'"
  }

  critical {
    operator              = "above"
    threshold             = 1
    threshold_duration    = 600
    threshold_occurrences = "at_least_once"
  }

  fill_option = "static"
  fill_value  = 0

  aggregation_window           = 600
  aggregation_method           = "event_timer"
  aggregation_timer            = 300
  violation_time_limit_seconds = 86400
}
