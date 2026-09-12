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
  # a URL HTTPS do gateway (output api_endpoint do stack da Lambda).
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
