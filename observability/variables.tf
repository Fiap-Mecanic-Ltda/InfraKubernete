variable "newrelic_account_id" {
  type        = number
  description = "ID da conta do New Relic (canto inferior esquerdo da UI, ou em Administration > Access management)."
}

variable "newrelic_api_key" {
  type        = string
  description = "User API key do New Relic (NRAK-...). Nao e a license key usada pelos agentes."
  sensitive   = true
}

variable "newrelic_region" {
  type        = string
  description = "Regiao da conta do New Relic: US ou EU."
  default     = "US"
}

variable "cluster_name" {
  type        = string
  description = "Nome do cluster na integracao Kubernetes (global.cluster do HelmChart em k8s/observabilidade)."
  default     = "mechanicltda-prod"
}

variable "namespace_aplicacao" {
  type    = string
  default = "mechanicltda"
}

variable "app_name_api" {
  type        = string
  description = "NEW_RELIC_APP_NAME do deployment da API."
  default     = "mechanicltda-api"
}

variable "app_name_web" {
  type        = string
  description = "NEW_RELIC_APP_NAME do deployment do Web."
  default     = "mechanicltda-web"
}

variable "api_base_url" {
  type        = string
  description = <<-EOT
    URL pública do API Gateway, alvo do monitor de disponibilidade. Vazio lê o
    output api_base_url do stack da Lambda; se aquele stack ainda não tiver sido
    aplicado, o monitor não é criado.
  EOT
  default     = ""
}

variable "email_alertas" {
  type        = string
  description = "E-mail que recebe as notificacoes dos alertas. Vazio cria os alertas sem notificacao (visiveis so na UI)."
  default     = ""
}

# Limiares dos alertas

variable "latencia_p95_limite_ms" {
  type        = number
  description = "Latencia p95 das requisicoes da API acima da qual o alerta dispara."
  default     = 1500
}

variable "taxa_erro_limite_percentual" {
  type    = number
  default = 5
}

variable "uso_recurso_limite_percentual" {
  type        = number
  description = "Uso de CPU ou memoria do container, em % do limit, acima do qual o alerta dispara."
  default     = 90
}
