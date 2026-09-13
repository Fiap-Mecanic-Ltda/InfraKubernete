# Painel do desafio, com as três visões exigidas — volume diário de ordens de serviço,
# tempo médio de execução por status e erros nas integrações — mais latência das APIs,
# recursos do Kubernetes e disponibilidade, que é o que se olha primeiro quando um
# alerta dispara.
#
# Os eventos OrdemServicoEvento, OrdemServicoFalha e FalhaIntegracao são gravados pela
# aplicação (NewRelicMonitoramentoService). Os status aparecem pelo nome de exibição
# ("Diagnóstico", "Execução", "Finalizada").

locals {
  eventos_os = "OrdemServicoEvento"
}

resource "newrelic_one_dashboard" "mechanicltda" {
  name        = "MechanicLtda - ${var.cluster_name}"
  permissions = "public_read_only"

  # ── Ordens de serviço ───────────────────────────────────────────────────────
  page {
    name = "Ordens de servico"

    widget_billboard {
      title  = "OS abertas hoje"
      row    = 1
      column = 1
      width  = 3
      height = 3

      nrql_query {
        account_id = var.newrelic_account_id
        query      = "SELECT count(*) AS 'OS abertas' FROM ${local.eventos_os} WHERE tipo = 'Criada' SINCE today"
      }
    }

    widget_line {
      title  = "Volume diario de ordens de servico"
      row    = 1
      column = 4
      width  = 9
      height = 3

      nrql_query {
        account_id = var.newrelic_account_id
        query      = "SELECT count(*) AS 'OS abertas' FROM ${local.eventos_os} WHERE tipo = 'Criada' SINCE 30 days ago TIMESERIES 1 day"
      }
    }

    widget_bar {
      title  = "Tempo medio por status: Diagnostico, Execucao e Finalizacao (minutos)"
      row    = 4
      column = 1
      width  = 6
      height = 3

      # Tempo em cada etapa, medido na saída dela. Finalização é o intervalo entre a OS
      # ficar Finalizada e ser Entregue.
      nrql_query {
        account_id = var.newrelic_account_id
        query      = "SELECT average(minutosNoStatusAnterior) AS 'minutos' FROM ${local.eventos_os} WHERE tipo = 'MudancaStatus' AND statusAnterior IN ('EmDiagnostico', 'EmExecucao', 'Finalizada') FACET statusAnteriorDescricao SINCE 30 days ago"
      }
    }

    widget_table {
      title  = "Tempo em cada etapa (minutos)"
      row    = 4
      column = 7
      width  = 6
      height = 3

      nrql_query {
        account_id = var.newrelic_account_id
        query      = "SELECT count(*) AS 'transicoes', average(minutosNoStatusAnterior) AS 'media', percentile(minutosNoStatusAnterior, 90) AS 'p90', max(minutosNoStatusAnterior) AS 'maximo' FROM ${local.eventos_os} WHERE tipo = 'MudancaStatus' FACET statusAnteriorDescricao SINCE 30 days ago"
      }
    }

    widget_line {
      title  = "Falhas no processamento de OS"
      row    = 7
      column = 1
      width  = 8
      height = 3

      nrql_query {
        account_id = var.newrelic_account_id
        query      = "SELECT count(*) FROM OrdemServicoFalha FACET categoria, operacao SINCE 7 days ago TIMESERIES"
      }
    }

    widget_table {
      title  = "Ultimas falhas de sistema"
      row    = 7
      column = 9
      width  = 4
      height = 3

      nrql_query {
        account_id = var.newrelic_account_id
        query      = "SELECT timestamp, operacao, ordemServicoId, erro, mensagem FROM OrdemServicoFalha WHERE categoria = 'Sistema' SINCE 7 days ago LIMIT 20"
      }
    }
  }

  # ── APIs ────────────────────────────────────────────────────────────────────
  page {
    name = "APIs"

    widget_line {
      title  = "Latencia da API (ms): p50, p95 e p99"
      row    = 1
      column = 1
      width  = 8
      height = 3

      nrql_query {
        account_id = var.newrelic_account_id
        query      = "SELECT percentile(duration * 1000, 50, 95, 99) FROM Transaction WHERE ${local.filtro_api} SINCE 3 hours ago TIMESERIES"
      }
    }

    widget_billboard {
      title  = "Disponibilidade de /health (24 h)"
      row    = 1
      column = 9
      width  = 4
      height = 3

      nrql_query {
        account_id = var.newrelic_account_id
        query      = "SELECT percentage(count(*), WHERE result = 'SUCCESS') AS 'uptime' FROM SyntheticCheck WHERE monitorName = '${local.monitor_saude}' SINCE 1 day ago"
      }
    }

    widget_bar {
      title  = "Transacoes mais lentas (p95, ms)"
      row    = 4
      column = 1
      width  = 6
      height = 3

      nrql_query {
        account_id = var.newrelic_account_id
        query      = "SELECT percentile(duration * 1000, 95) FROM Transaction WHERE ${local.filtro_api} FACET name SINCE 1 day ago LIMIT 10"
      }
    }

    widget_line {
      title  = "Throughput e taxa de erro"
      row    = 4
      column = 7
      width  = 6
      height = 3

      nrql_query {
        account_id = var.newrelic_account_id
        query      = "SELECT rate(count(*), 1 minute) AS 'req/min', percentage(count(*), WHERE error IS true) AS '% erro' FROM Transaction WHERE ${local.filtro_api} SINCE 3 hours ago TIMESERIES"
      }
    }

    widget_table {
      title  = "Erros recentes com correlacao (requestId do API Gateway)"
      row    = 7
      column = 1
      width  = 12
      height = 3

      nrql_query {
        account_id = var.newrelic_account_id
        query      = "SELECT timestamp, level, message, context.CorrelationId, trace.id FROM Log WHERE entity.name IN ('${var.app_name_api}', '${var.app_name_web}') AND level IN ('ERROR', 'Error', 'CRITICAL', 'Critical') SINCE 1 day ago LIMIT 50"
      }
    }
  }

  # ── Integrações ─────────────────────────────────────────────────────────────
  page {
    name = "Integracoes"

    widget_line {
      title  = "Falhas nas integracoes"
      row    = 1
      column = 1
      width  = 6
      height = 3

      nrql_query {
        account_id = var.newrelic_account_id
        query      = "SELECT count(*) FROM FalhaIntegracao FACET integracao, operacao SINCE 7 days ago TIMESERIES"
      }
    }

    widget_bar {
      title  = "Erros da API por tipo de excecao"
      row    = 1
      column = 7
      width  = 6
      height = 3

      nrql_query {
        account_id = var.newrelic_account_id
        query      = "SELECT count(*) FROM TransactionError WHERE appName IN ('${var.app_name_api}', '${var.app_name_web}') FACET error.class SINCE 1 day ago"
      }
    }

    widget_line {
      title  = "Tempo no banco de dados por requisicao (ms)"
      row    = 4
      column = 1
      width  = 6
      height = 3

      nrql_query {
        account_id = var.newrelic_account_id
        query      = "SELECT average(databaseDuration * 1000) AS 'SQL Server' FROM Transaction WHERE ${local.filtro_api} SINCE 3 hours ago TIMESERIES"
      }
    }

    widget_table {
      title  = "Ultimas falhas de integracao"
      row    = 4
      column = 7
      width  = 6
      height = 3

      nrql_query {
        account_id = var.newrelic_account_id
        query      = "SELECT timestamp, integracao, operacao, erro, mensagem FROM FalhaIntegracao SINCE 7 days ago LIMIT 20"
      }
    }
  }

  # ── Kubernetes ──────────────────────────────────────────────────────────────
  page {
    name = "Kubernetes"

    widget_line {
      title  = "CPU por pod (% do limit)"
      row    = 1
      column = 1
      width  = 6
      height = 3

      nrql_query {
        account_id = var.newrelic_account_id
        query      = "SELECT average(cpuCoresUtilization) FROM K8sContainerSample WHERE ${local.filtro_container} FACET podName SINCE 3 hours ago TIMESERIES"
      }
    }

    widget_line {
      title  = "Memoria por pod (% do limit)"
      row    = 1
      column = 7
      width  = 6
      height = 3

      nrql_query {
        account_id = var.newrelic_account_id
        query      = "SELECT average(memoryWorkingSetUtilization) FROM K8sContainerSample WHERE ${local.filtro_container} FACET podName SINCE 3 hours ago TIMESERIES"
      }
    }

    widget_line {
      title  = "Replicas do HPA: atuais e desejadas"
      row    = 4
      column = 1
      width  = 6
      height = 3

      nrql_query {
        account_id = var.newrelic_account_id
        query      = "SELECT latest(currentReplicas) AS 'atuais', latest(desiredReplicas) AS 'desejadas' FROM K8sHpaSample WHERE ${local.filtro_container} FACET displayName SINCE 3 hours ago TIMESERIES"
      }
    }

    widget_line {
      title  = "CPU dos nos (%)"
      row    = 4
      column = 7
      width  = 6
      height = 3

      nrql_query {
        account_id = var.newrelic_account_id
        query      = "SELECT average(cpuPercent) FROM SystemSample WHERE clusterName = '${var.cluster_name}' FACET hostname SINCE 3 hours ago TIMESERIES"
      }
    }

    widget_table {
      title  = "Reinicios de container (24 h)"
      row    = 7
      column = 1
      width  = 12
      height = 3

      nrql_query {
        account_id = var.newrelic_account_id
        query      = "SELECT sum(restartCountDelta) AS 'reinicios', latest(status) AS 'status' FROM K8sContainerSample WHERE ${local.filtro_container} FACET podName, containerName SINCE 1 day ago"
      }
    }
  }
}
