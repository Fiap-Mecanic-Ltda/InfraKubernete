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
#
# O ID numérico de cada repositório entra junto porque a organização usa
# immutable subject claims: o sub do token OIDC chega como
# "repo:OWNER@<owner_id>/REPO@<repo_id>:ref:..." em vez de apenas os nomes.
# Consulte o ID em https://api.github.com/repos/<owner>/<repo> (campo "id").
variable "github_repositories" {
  type        = map(number)
  description = "Repositórios GitHub (owner/repo => ID numérico) autorizados a assumir a role de CI/CD via OIDC."
  default = {
    "Fiap-Mecanic-Ltda/MechanicLtda"   = 1200845101
    "Fiap-Mecanic-Ltda/InfraKubernete" = 1360727713
  }
}

# ID numérico da organização, que compõe o mesmo sub claim imutável.
# https://api.github.com/orgs/Fiap-Mecanic-Ltda (campo "id").
variable "github_owner_id" {
  type        = number
  description = "ID numérico da organização dona dos repositórios no GitHub."
  default     = 273456374
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

# Sub-redes de aplicação (ALB interno e ENIs do VPC Link)

variable "app_subnet_a_cidr" {
  type        = string
  description = "CIDR da sub-rede de aplicacao na primeira AZ (ALB interno e VPC Link)."
  default     = "10.0.4.0/24"
}

variable "app_subnet_b_cidr" {
  type        = string
  description = "CIDR da sub-rede de aplicacao na segunda AZ. O ALB exige duas AZs."
  default     = "10.0.5.0/24"
}

variable "expose_nodeport_publicly" {
  type        = bool
  description = <<-EOT
    Mantém as portas 8080 (API) e 8090 (Web) abertas para var.api_allowed_cidr.
    Fica `true` durante a virada para o API Gateway, para não interromper o
    ambiente enquanto o gateway é validado. Depois do smoke test, passe para
    `false`: a API deixa de ser acessível fora da VPC e o gateway se torna a
    única entrada.
  EOT
  default     = true
}

variable "app_base_url_aprovacao" {
  type        = string
  description = <<-EOT
    URL base dos links de aprovacao de OS enviados por e-mail. Vazio mantém o
    IP público da EC2 (comportamento das fases anteriores). Depois que o API
    Gateway estiver no ar, aponte para a URL dele (HTTPS).
  EOT
  default     = ""
}

variable "cpf_hash_key" {
  type        = string
  description = <<-EOT
    Chave do índice cego (HMAC-SHA256) do CPF/CNPJ. Precisa ser o mesmo valor
    usado pela Lambda de autenticação: o hash gravado pela aplicação é o mesmo
    que a função consulta. Mínimo de 32 caracteres.
  EOT
  sensitive   = true
}
