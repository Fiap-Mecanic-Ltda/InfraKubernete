variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "project_name" {
  type    = string
  default = "mechanicltda"
}

variable "environment" {
  type    = string
  default = "prod"
}

# Depois da separação dos repositórios, dois projetos usam a mesma role: o da
# aplicação (build/push das imagens no ECR) e este, de infra (deploy dos
# manifestos no k3s via SSM). Os dois precisam constar no trust policy do OIDC.
variable "github_repositories" {
  type        = list(string)
  description = "Repositórios GitHub (owner/repo) autorizados a assumir a role de CI/CD via OIDC."
  default = [
    "Fiap-Mecanic-Ltda/MechanicLtda",
    "Fiap-Mecanic-Ltda/InfraKubernete",
  ]
}

# Branches cujos workflows podem assumir a role de CI/CD. O sub claim do OIDC
# carrega a ref do job, então cada branch que dispara pipeline precisa constar
# aqui — "homolog" é a branch de trabalho atual, enquanto a "main" segue como
# alvo final.
variable "github_branches" {
  type        = list(string)
  description = "Branches autorizadas a assumir a role de CI/CD via OIDC."
  default     = ["main", "homolog"]
}

# Rede

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  type    = string
  default = "10.0.1.0/24"
}

variable "db_subnet_a_cidr" {
  type    = string
  default = "10.0.2.0/24"
}

variable "db_subnet_b_cidr" {
  type    = string
  default = "10.0.3.0/24"
}

variable "api_allowed_cidr" {
  type        = string
  description = "CIDR com acesso à API (porta 8080) e ao Web (porta 8090). Default público (0.0.0.0/0) é intencional: a aplicação é consumida externamente (Swagger, demo). Restrinja em variables.tfvars para um CIDR menor se o ambiente não precisar de acesso público irrestrito."
  default     = "0.0.0.0/0"
}

# EC2

variable "ec2_instance_type" {
  type        = string
  description = "Tipo da instância EC2 que roda a API."
  default     = "t3.small"
}

variable "ec2_key_pair_name" {
  type        = string
  description = "Key pair EC2 usado no acesso SSH."
}

# Workers k3s (ASG)

variable "worker_instance_type" {
  type        = string
  description = "Tipo da instância EC2 dos workers k3s do ASG."
  default     = "t3.small"
}

variable "worker_min_size" {
  type    = number
  default = 1
}

variable "worker_max_size" {
  type    = number
  default = 3
}

variable "worker_desired_capacity" {
  type    = number
  default = 1
}

variable "worker_asg_target_cpu" {
  type        = number
  description = "CPU média alvo (%) do ASG para o target tracking scaling."
  default     = 60
}

# RDS: a instancia, o subnet group e o security group do banco ficam no
# repositorio de infra do banco gerenciado. Aqui sobram apenas os CIDRs das
# subnets de banco (acima), porque a rede e provisionada por este stack.

# ECR

variable "ecr_repository_name" {
  type    = string
  default = "mechanicltda-api"
}

variable "ecr_repository_web_name" {
  type    = string
  default = "mechanicltda-web"
}

# Segredos da aplicação

variable "jwt_secret_key" {
  type        = string
  description = "Chave secreta de assinatura dos tokens JWT (mínimo 32 caracteres)."
  sensitive   = true
}

variable "encryption_cpf_cnpj_key" {
  type        = string
  description = "Chave de criptografia dos campos CPF/CNPJ (mínimo 32 caracteres)."
  sensitive   = true
}

variable "email_password" {
  type        = string
  description = "Senha de app do Gmail para envio de e-mails via SMTP."
  sensitive   = true
}
