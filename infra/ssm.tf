locals {
  ssm_path_prefix = "/${var.project_name}/${var.environment}"
}

resource "aws_ssm_parameter" "jwt_secret_key" {
  name  = "${local.ssm_path_prefix}/jwt-secret-key"
  type  = "SecureString"
  value = var.jwt_secret_key
}

resource "aws_ssm_parameter" "encryption_key" {
  name  = "${local.ssm_path_prefix}/encryption-key"
  type  = "SecureString"
  value = var.encryption_cpf_cnpj_key
}

resource "aws_ssm_parameter" "email_password" {
  name  = "${local.ssm_path_prefix}/email-password"
  type  = "SecureString"
  value = var.email_password
}

# O parametro "${local.ssm_path_prefix}/db-connection-string" e criado pelo
# repositorio de infra do banco gerenciado (quem conhece endereco, usuario e
# senha do RDS). O deploy le os dois prefixos do mesmo jeito - a policy de
# leitura (iam.tf / github_oidc.tf) ja cobre o prefixo inteiro.

resource "aws_ssm_parameter" "app_base_url_aprovacao" {
  name = "${local.ssm_path_prefix}/app-base-url-aprovacao"
  type = "String"

  # Os links de aprovação vão por e-mail para o cliente, então precisam apontar
  # para um endereço que ele consiga abrir. Enquanto o API Gateway não estiver
  # no ar, segue o IP público da EC2; depois, defina app_base_url_aprovacao com
  # a URL HTTPS do gateway (output api_base_url do stack da Lambda).
  value = var.app_base_url_aprovacao != "" ? var.app_base_url_aprovacao : "http://${aws_eip.app.public_ip}:8080"
}

# Índice cego do CPF/CNPJ. Consumido pela aplicação (Secret do Kubernetes, via
# pipeline de deploy) e pela Lambda de autenticação, que lê este mesmo parâmetro
# no apply. O valor precisa ser idêntico nos dois lados: a aplicação grava o
# hash e a função consulta por ele.
resource "aws_ssm_parameter" "cpf_hash_key" {
  name  = "${local.ssm_path_prefix}/cpf-hash-key"
  type  = "SecureString"
  value = var.cpf_hash_key
}

# License key do New Relic. Só existe quando informada: o deploy.yml liga o agente APM
# e instala a integração Kubernetes apenas se este parâmetro estiver no SSM.
# nonsensitive() só no teste de vazio - o valor em si continua sensível.
resource "aws_ssm_parameter" "newrelic_license_key" {
  count = nonsensitive(var.newrelic_license_key != "") ? 1 : 0

  name  = "${local.ssm_path_prefix}/newrelic-license-key"
  type  = "SecureString"
  value = var.newrelic_license_key
}

# Credenciais do RabbitMQ compartilhado pelos microsservicos da Fase 4 (Saga da
# OS, Billing e Execucao). Ficam num prefixo proprio: o deploy deste repositorio
# monta o Secret do broker, e o de cada servico monta o Secret do cliente.
#
# A senha so e lida de var.rabbitmq_segredo na criacao do parametro. Depois disso
# o valor no SSM manda (ignore_changes): o RabbitMQ grava o usuario no volume na
# primeira subida, entao trocar a senha aqui deixaria broker e servicos com
# senhas diferentes. Sem a variavel no CI (secret RABBITMQ_SEGREDO vazio), nada
# muda; para girar a senha, troque no SSM e recrie o volume do broker.
resource "aws_ssm_parameter" "rabbitmq_user" {
  name  = "${local.ssm_path_prefix}/mensageria/rabbitmq-user"
  type  = "String"
  value = var.rabbitmq_user
}

resource "aws_ssm_parameter" "rabbitmq_segredo" {
  name  = "${local.ssm_path_prefix}/mensageria/rabbitmq-segredo"
  type  = "SecureString"
  value = var.rabbitmq_segredo != "" ? var.rabbitmq_segredo : "defina-rabbitmq-segredo"

  lifecycle {
    ignore_changes = [value]
  }
}

moved {
  from = aws_ssm_parameter.rabbitmq_user[0]
  to   = aws_ssm_parameter.rabbitmq_user
}

moved {
  from = aws_ssm_parameter.rabbitmq_segredo[0]
  to   = aws_ssm_parameter.rabbitmq_segredo
}
