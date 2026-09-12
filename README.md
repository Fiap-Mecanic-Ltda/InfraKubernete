# InfraKubernete — Infraestrutura de Kubernetes do MechanicLtda

Repositório de **infraestrutura de Kubernetes** do projeto MechanicLtda: o Terraform que
provisiona o cluster (rede, EC2 com k3s, workers em Auto Scaling, ECR, SSM, IAM/OIDC) e os
manifestos que rodam a aplicação nele.

## Os quatro repositórios do projeto


| # | Repositório                                                      | Conteúdo                                                  | CI/CD                                   |
| - | ----------------------------------------------------------------- | ---------------------------------------------------------- | --------------------------------------- |
| 1 | [Lambda](https://github.com/Fiap-Mecanic-Ltda/Lambda)             | Function serverless (API Gateway + Lambda) que emite o JWT | build, testes e deploy da função      |
| 2 | **InfraKubernete** (este)                                         | `infra/` (Terraform do cluster) + `k8s/` (Kustomize)       | `terraform plan/apply` + deploy no k3s  |
| 3 | [InfraSGBD](https://github.com/Fiap-Mecanic-Ltda/InfraSGBD)       | Terraform do RDS SQL Server + connection string no SSM     | `terraform plan/apply`                  |
| 4 | [MechanicLtda](https://github.com/Fiap-Mecanic-Ltda/MechanicLtda) | Aplicação .NET 9 (`src/`, `tests/`, Dockerfiles)         | build, testes e push das imagens no ECR |

O contrato entre o repositório 4 e este é o **ECR**: a aplicação publica as imagens
(`mechanicltda-api` / `mechanicltda-web`, tags `latest` + SHA do commit) e o deploy daqui aplica a
última imagem publicada no cluster.

O contrato entre este e o repositório 3 é o **state remoto**: o stack do banco lê daqui, via
`terraform_remote_state`, o `vpc_id`, as `db_subnet_ids` e os security groups dos nós k3s
(`ec2_security_group_id`, `worker_security_group_id`) — por isso **este stack sobe primeiro**.

## Estrutura

```text
InfraKubernete/
├── infra/                 # Terraform: VPC, EC2 (k3s), ASG de workers, ECR, SSM, IAM/OIDC
│   ├── network.tf         # VPC, subnets (pública + as duas de banco), IGW, rotas
│   ├── ec2.tf             # Instância do control plane do k3s + EIP
│   ├── asg.tf             # Auto Scaling Group dos workers k3s
│   ├── ecr.tf             # Repositórios de imagem (api e web)
│   ├── security_groups.tf # SGs da EC2, dos workers e da malha k3s
│   ├── ssm.tf             # Segredos da aplicação (SecureString) e prefixo /projeto/ambiente
│   ├── iam.tf             # Role/instance profile das instâncias, acesso via Session Manager
│   ├── github_oidc.tf     # OIDC + role assumida pelas pipelines dos repositórios 2 e 4
│   ├── outputs.tf         # Inclui os valores consumidos pelo stack do banco
│   └── templates/         # user_data (instala k3s, metrics-server e o renovador do ECR)
├── k8s/                   # Manifestos (Kustomize): base + overlays local/prod
└── .github/workflows/
    ├── terraform.yml      # plan automático em infra/**; apply manual
    └── deploy.yml         # aplica os manifestos no k3s via SSM Run Command
```

O que **não** está aqui: o RDS (repositório 3), a Lambda (repositório 1) e o código da
aplicação (repositório 4).

Detalhes dos manifestos, do fluxo de deploy e das decisões de design: **[k8s/README.md](k8s/README.md)**.

## Como rodar o Terraform localmente

```bash
cd infra
cp terraform.tfvars.example terraform.tfvars   # preencher com valores reais (nunca commitar)
terraform init
terraform plan
terraform apply
```

O state fica remoto no S3 (`infra/versions.tf`, chave `prod/terraform.tfstate`), com locking
nativo (`use_lockfile`). Para desmontar: `terraform destroy` — destrua antes o stack do banco,
que depende dos outputs daqui.

## Pipelines

### `terraform.yml`

- **plan**: automático em push/PR que toquem `infra/**`; também via `workflow_dispatch`.
- **apply**: só via `workflow_dispatch` com `action = apply`, protegido pelo Environment
  `production`.
- Autentica com a **chave estática do usuário `terraform-deployer`** (não OIDC): a role de OIDC é
  criada por este próprio apply, então no bootstrap ainda não existe nada para assumir.

### `deploy.yml`

- Roda em push que toque `k8s/**` e via `workflow_dispatch` (com `image_tag` opcional).
- Autentica na AWS via **OIDC** (`secrets.AWS_ROLE_ARN`), sem access keys.
- Sem `image_tag`, resolve sozinho a **última imagem publicada no ECR** — a tag imutável (SHA)
  em vez de `latest`, porque os Deployments usam `imagePullPolicy: IfNotPresent` e reaplicar
  `latest` não traria a imagem nova para o nó.
- A porta 6443 do k3s nunca é exposta: os manifestos renderizados vão para o S3 e um
  `aws ssm send-command` roda `kubectl apply` **dentro** da instância.

> Depois de um push na `main` do repositório da aplicação, rode o `deploy.yml`
> (Actions → Deploy no Kubernetes → Run workflow) para levar a imagem nova ao cluster.

## Secrets e variáveis necessários neste repositório

(Settings → Secrets and variables → Actions)


| Nome                    | Tipo   | Usado por       | Uso                                          |
| ----------------------- | ------ | --------------- | -------------------------------------------- |
| `AWS_ACCESS_KEY_ID`     | Secret | `terraform.yml` | Chave do usuário`terraform-deployer`        |
| `AWS_SECRET_ACCESS_KEY` | Secret | `terraform.yml` | idem                                         |
| `JWT_SECRET_KEY`        | Secret | `terraform.yml` | `TF_VAR_jwt_secret_key`                      |
| `ENCRYPTION_KEY`        | Secret | `terraform.yml` | `TF_VAR_encryption_cpf_cnpj_key`             |
| `EMAIL_PASSWORD`        | Secret | `terraform.yml` | `TF_VAR_email_password`                      |
| `AWS_ROLE_ARN`          | Secret | `deploy.yml`    | Output`github_actions_role_arn` do Terraform |

O Environment `production` (Settings → Environments) precisa existir para o job de `apply`.

`aws_region`, `project_name` e `environment` **não** são variáveis do GitHub: os workflows leem os
defaults direto de `infra/variables.tf` (fonte única de verdade).

## Primeira subida (ordem entre os repositórios)

1. `terraform apply` **aqui** — cria VPC, subnets, EC2 com k3s, workers, ECR e IAM/OIDC.
2. `terraform apply` no **[InfraSGBD](https://github.com/Fiap-Mecanic-Ltda/InfraSGBD)** — cria o RDS nas subnets acima e grava
   a connection string no SSM.
3. Push na `main` do **repositório da aplicação** — publica as imagens no ECR.
4. `deploy.yml` **aqui** — aplica os manifestos e sobe a aplicação no cluster.

Entre 1 e 3, cadastre `AWS_ROLE_ARN` (output `github_actions_role_arn`) nos repositórios que
autenticam via OIDC.

## Trust policy do OIDC

`infra/variables.tf` → `github_repositories` mapeia os repositórios autorizados a assumir a role
(`owner/repo` → ID numérico) e `github_branches` lista as branches liberadas. Ao adicionar um
repositório novo (a Lambda, por exemplo) ou uma branch que dispara pipeline, atualize essas
variáveis e rode `terraform apply` — sem isso o job correspondente falha no
`configure-aws-credentials` com erro de `sts:AssumeRoleWithWebIdentity`.

O ID numérico é obrigatório porque a organização usa **immutable subject claims**: o `sub` do token
OIDC chega como `repo:OWNER@<owner_id>/REPO@<repo_id>:ref:refs/heads/<branch>`, e não com os nomes
puros. Consulte o ID em `https://api.github.com/repos/<owner>/<repo>` (campo `id`) e o da
organização em `https://api.github.com/orgs/<owner>` (`github_owner_id`). O trust policy publica as
duas formas de `sub`, então a role continua assumível caso a organização desligue a opção.

Para descobrir o `sub` exato que a AWS recebeu numa falha, consulte o CloudTrail: 

```bash
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=AssumeRoleWithWebIdentity \
  --region us-east-1 --max-results 5 \
  --query 'Events[].CloudTrailEvent' --output text
```
