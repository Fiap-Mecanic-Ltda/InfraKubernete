# Notificação por e-mail dos incidentes da política. Opcional: sem email_alertas os
# alertas existem e aparecem na UI do New Relic, mas ninguém é avisado.

locals {
  notificar_por_email = var.email_alertas != ""
}

resource "newrelic_notification_destination" "email" {
  count = local.notificar_por_email ? 1 : 0

  account_id = var.newrelic_account_id
  name       = "${var.cluster_name} - e-mail do time"
  type       = "EMAIL"

  property {
    key   = "email"
    value = var.email_alertas
  }
}

resource "newrelic_notification_channel" "email" {
  count = local.notificar_por_email ? 1 : 0

  account_id     = var.newrelic_account_id
  name           = "${var.cluster_name} - canal de e-mail"
  type           = "EMAIL"
  destination_id = newrelic_notification_destination.email[0].id
  product        = "IINT"

  property {
    key   = "subject"
    value = "[MechanicLtda] {{ issueTitle }}"
  }
}

resource "newrelic_workflow" "alertas" {
  count = local.notificar_por_email ? 1 : 0

  name                  = "${var.cluster_name} - alertas por e-mail"
  muting_rules_handling = "NOTIFY_ALL_ISSUES"

  issues_filter {
    name = "Politica MechanicLtda"
    type = "FILTER"

    predicate {
      attribute = "labels.policyIds"
      operator  = "EXACTLY_MATCHES"
      values    = [newrelic_alert_policy.mechanicltda.id]
    }
  }

  destination {
    channel_id = newrelic_notification_channel.email[0].id
  }
}
