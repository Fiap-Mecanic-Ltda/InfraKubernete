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
  name  = "${local.ssm_path_prefix}/app-base-url-aprovacao"
  type  = "String"
  value = "http://${aws_eip.app.public_ip}:8080"
}
