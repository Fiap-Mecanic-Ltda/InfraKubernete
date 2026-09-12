output "ec2_public_ip" {
  value = aws_eip.app.public_ip
}

output "ec2_instance_id" {
  value = aws_instance.app.id
}

output "ecr_repository_url" {
  value = aws_ecr_repository.api.repository_url
}

output "ecr_repository_web_url" {
  value = aws_ecr_repository.web.repository_url
}

output "github_actions_role_arn" {
  value = aws_iam_role.github_actions.arn
}

# Deriva de var.project_name/var.environment (ssm.tf) - a pipeline de CI/CD le
# este output em vez de hardcodar o prefixo, para respeitar o que estiver
# configurado em variables.tf/terraform.tfvars.
output "ssm_path_prefix" {
  value = local.ssm_path_prefix
}

output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnet_id" {
  value = aws_subnet.public.id
}

# ── Consumidos pelo stack de infra do banco gerenciado ───────────────────────
# O repositorio do RDS le estes outputs via terraform_remote_state (o state
# deste stack fica em s3://.../prod/terraform.tfstate) em vez de duplicar a
# rede ou descobrir ids por data source com filtro de tag.

output "db_subnet_ids" {
  description = "Subnets privadas onde o RDS e provisionado (aws_db_subnet_group, no stack do banco)."
  value       = [aws_subnet.db_a.id, aws_subnet.db_b.id]
}

output "ec2_security_group_id" {
  description = "SG do server k3s - origem autorizada na porta 1433 do RDS."
  value       = aws_security_group.ec2.id
}

output "worker_security_group_id" {
  description = "SG dos workers k3s - um pod da API pode ser agendado em qualquer no."
  value       = aws_security_group.worker.id
}
