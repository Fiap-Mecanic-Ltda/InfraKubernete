# Manifestos Kubernetes — MechanicLtda

Manifestos para deploy da stack (`api`, `web`, e opcionalmente `sqlserver`) em um cluster
Kubernetes, organizados como base + overlays (Kustomize) para cobrir dois cenários distintos:

- **`overlays/local`** — desenvolvimento em `kind`/`minikube`, com um pod `sqlserver` próprio
  (mesmo papel do `docker-compose.yml`).
- **`overlays/prod`** — o cluster real deste projeto: **k3s rodando na EC2** provisionada pelo
  Terraform deste repositório (`infra/`), sem pod de banco — usa o **RDS SQL Server** criado pelo
  repositório [InfraSGBD](https://github.com/Fiap-Mecanic-Ltda/InfraSGBD).

## Estrutura

```
k8s/
├── base/                 # Namespace, ConfigMap, Secret (placeholder), Deployments/Services/HPA de api e web
└── overlays/
    ├── local/            # + sqlserver (pod) + initContainers de espera (sqlserver → api → web)
    └── prod/              # Services viram NodePort (8080/8090) + imagePullSecrets (ECR)
```

| Recurso | Onde |
|---|---|
| Namespace, ConfigMap, Secret | `base/` |
| Deployment/Service/HPA da API | `base/api-*.yaml` |
| Deployment/Service/HPA do Web | `base/web-*.yaml` |
| SQL Server (pod, só dev local) | `overlays/local/sqlserver-*.yaml` |
| NodePort + `imagePullSecrets` (só prod) | patches em `overlays/prod/kustomization.yaml` |

## Rodando localmente (kind/minikube)

Pré-requisitos: **metrics-server** (HPA) e um **StorageClass** padrão para o PVC do SQL Server.
Carregue as imagens locais no cluster antes de aplicar:

```bash
# kind
kind load docker-image mechanicltda-api:latest mechanicltda-web:latest
# minikube
minikube image load mechanicltda-api:latest && minikube image load mechanicltda-web:latest
```

Segredos — não edite `base/secret.yaml`, crie à parte:

```bash
kubectl create namespace mechanicltda --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic mechanicltda-secrets \
  --namespace mechanicltda \
  --from-literal=SA_PASSWORD='<senha-forte>' \
  --from-literal=JWT_SECRET_KEY='<chave-jwt-min-32-chars>' \
  --from-literal=ENCRYPTION_KEY='<chave-criptografia-min-32-chars>' \
  --from-literal=EmailSettings__Password='<senha-de-app-gmail>' \
  --from-literal=AppSettings__BaseUrlAprovacao='http://localhost:8080' \
  --from-literal=ConnectionStrings__DefaultConnection='Server=mechanicltda-sqlserver;Database=MechanicLtdaDb;User Id=sa;Password=<senha-forte>;TrustServerCertificate=True;' \
  --dry-run=client -o yaml | kubectl apply -f -
```

Deploy e acompanhamento:

```bash
kubectl apply -k k8s/overlays/local
kubectl get pods,svc,hpa -n mechanicltda
kubectl port-forward -n mechanicltda svc/mechanicltda-api 8080:8080
kubectl port-forward -n mechanicltda svc/mechanicltda-web 8090:8080
```

## Produção (k3s na EC2 do Terraform)

Não é para aplicar manualmente — quem faz isso é a pipeline deste repositório
(`.github/workflows/deploy.yml`), em push que toque `k8s/**` e sob demanda
(`workflow_dispatch`), depois que o repositório da aplicação publica uma imagem nova no ECR.
Descrição do fluxo e pré-requisitos abaixo, útil pra depurar.

### Como a pipeline acessa o cluster

O k3s roda só na própria instância EC2 e **a porta 6443 nunca é exposta** publicamente
(mesma postura do resto do projeto: sem SSH, só SSM Session Manager). A pipeline autentica na
AWS via **OIDC** (sem access keys) e usa `aws ssm send-command` pra rodar `kubectl apply`
*dentro* da instância — o manifesto renderizado (com as tags de imagem do commit atual) é
enviado em base64 dentro do próprio comando SSM.

### Qual imagem o deploy aplica

Sem `image_tag` informado, o workflow consulta o ECR (`aws ecr describe-images`) e usa a **tag
imutável da última imagem publicada** (o SHA do commit da aplicação), nunca `latest`: os
Deployments usam `imagePullPolicy: IfNotPresent`, então reaplicar `latest` não traria a imagem
nova para o nó. Para fixar uma versão específica (rollback, por exemplo), rode o workflow
manualmente informando a tag.

### O que o Terraform já provisiona para isso

- `infra/templates/user_data.sh.tpl` instala o k3s no boot (`--service-node-port-range=8000-9000`,
  pra aceitar os NodePorts 8080/8090 do overlay `prod`) e um systemd timer que renova as
  credenciais do ECR a cada 6h (containerd do k3s não tem integração nativa com IAM, ao
  contrário do EKS — o token do ECR expira em 12h).
- `infra/ecr.tf` — repositórios `mechanicltda-api` e `mechanicltda-web` (nomes vêm de
  `var.ecr_repository_name`/`var.ecr_repository_web_name`, `infra/variables.tf`).
- `infra/security_groups.tf` — libera `8080` (API) e `8090` (Web) no security group da EC2.
- `infra/github_oidc.tf` — OIDC provider do GitHub Actions + role `github_actions`
  (permissões: push no ECR, `ssm:SendCommand`/`GetCommandInvocation` restritas à instância,
  `ssm:GetParameter` para ler os segredos da aplicação, e leitura do state remoto em S3 —
  usada pela pipeline para resolver `ec2_instance_id`, `ssm_path_prefix` e as URLs do ECR via
  `terraform output` em vez de hardcoded no workflow).
- `infra/ssm.tf` — os segredos da aplicação (`jwt_secret_key`, `encryption_cpf_cnpj_key`,
  `email_password`) ficam no **SSM Parameter Store** (`SecureString`), sob o prefixo
  `/var.project_name/var.environment` (`local.ssm_path_prefix`, exposto como output
  `ssm_path_prefix`), alimentados a partir do `terraform.tfvars` (nunca commitado). A
  **connection string do RDS** fica no mesmo prefixo, mas é gravada pelo **repositório de infra
  do banco gerenciado** — quem conhece endereço, usuário e senha do banco. A pipeline lê tudo de
  lá pra montar o Secret do Kubernetes a cada deploy.

### A pipeline lê `infra/variables.tf` — não hardcoda nada

O `deploy.yml` extrai os defaults de `aws_region`, `project_name` e `environment` direto de
`infra/variables.tf` e deriva o resto deles, em vez de duplicar esses valores como Repository
Variables:

| Valor | Como é obtido |
|---|---|
| Registry do ECR | `aws-actions/amazon-ecr-login` (output `registry`) |
| Tag da imagem | `aws ecr describe-images` na última imagem publicada, ou o input `image_tag` |
| Instance ID da EC2 | `aws ec2 describe-instances` filtrando pela tag `Name` (`projeto-ambiente-api`) — o ID muda toda vez que a instância é substituída |
| Prefixo do SSM | `/project_name/environment` |

Se você mudar `project_name` ou `environment` em `infra/variables.tf`, a pipeline acompanha no
próximo `terraform apply` + deploy — nada para atualizar no workflow.

### Secrets/variáveis necessários no repositório GitHub

(Settings → Secrets and variables → Actions, **neste** repositório)

| Nome | Tipo | Uso |
|---|---|---|
| `AWS_ROLE_ARN` | Secret | Output `github_actions_role_arn` do Terraform — usado pelo `deploy.yml` via OIDC |
| `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` | Secret | Chave do `terraform-deployer`, usada só pelo `terraform.yml` |
| `JWT_SECRET_KEY`, `ENCRYPTION_KEY`, `EMAIL_PASSWORD` | Secret | `TF_VAR_*` do `terraform.yml` |

Não existe `KUBE_CONFIG` nem `EC2_INSTANCE_ID` como secret — o instance ID é descoberto pela tag
e os segredos da aplicação vivem só no SSM (geridos pelo Terraform).

### Primeira subida

1. `terraform apply` neste repositório (cria VPC, EC2 + k3s, workers, ECR e IAM/OIDC).
2. `terraform apply` no repositório InfraSGBD (cria o RDS e grava a connection string
   no SSM).
3. Cadastrar `AWS_ROLE_ARN` (output `github_actions_role_arn`) aqui e no repositório da
   aplicação.
4. Push na `main` do repositório da aplicação — publica as imagens no ECR.
5. Rodar o workflow *Deploy no Kubernetes* aqui — aplica os manifestos via SSM.

## Decisões e limitações conhecidas

- **RDS em produção, pod só em dev local**: `base/api-deployment.yaml` e `web-deployment.yaml`
  não têm mais o `initContainer` que espera o SQL Server — ele só existe no overlay `local`
  (patch em `overlays/local/kustomization.yaml`), porque em produção o banco é o RDS externo,
  já disponível antes da API subir.
- **SQL Server como Deployment (não StatefulSet) no overlay local**: instância única com PVC
  (`strategy: Recreate` evita dois pods montando o mesmo volume `ReadWriteOnce`
  simultaneamente). Não é candidato a HPA.
- **`minReplicas: 1` nos HPAs — proposital**: a aplicação aplica migrations e faz o seed
  inicial do banco a cada boot (idempotente, mas o seed usa um `check-then-insert` sem lock
  distribuído — diferente das migrations do EF Core, que já usam `sp_getapplock`). Com
  `minReplicas: 1`, apenas um pod sobe no primeiro boot, evitando dois pods inserindo o seed
  em paralelo antes de qualquer um ver o banco populado. Se `minReplicas >= 2` for necessário
  no futuro, mova a migration/seed para um `Job` único executado antes dos Deployments.
- **k3s em vez de EKS**: escolha deliberada para este projeto (custo zero adicional, reaproveita
  a EC2 já provisionada). Migrar para EKS é um caminho de evolução válido se a carga justificar
  um cluster gerenciado multi-nó — nesse caso, `overlays/prod` muda pouco (o overlay já é
  cluster-agnóstico), mas o Terraform (VPC/subnets, node groups, IAM do cluster) seria
  praticamente reescrito.
