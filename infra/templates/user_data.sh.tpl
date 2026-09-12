#!/bin/bash
set -eux
exec > >(tee /var/log/user-data.log) 2>&1

dnf update -y
dnf install -y aws-cli

# k3s: Kubernetes leve rodando na própria instância. --service-node-port-range
# amplo o suficiente para expor os Services da API (8080) e do Web (8090) via
# NodePort, batendo com o que o security group libera.
# Retry: o instalador (get.k3s.io/update.k3s.io, atrás de CDN) já falhou aqui
# antes com erro de SSL transitório; com "set -e" ativo, uma falha aqui
# abortava o script inteiro e nada mais rodava.
for i in $(seq 1 10); do
  if curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server --service-node-port-range=8000-9000" sh -; then
    break
  fi
  echo "Falha ao instalar k3s (tentativa $i/10), tentando novamente em 15s..."
  sleep 15
done

if ! command -v /usr/local/bin/kubectl >/dev/null 2>&1; then
  echo "ERRO: k3s nao foi instalado apos 10 tentativas" >&2
  exit 1
fi

# Publica o join-token do k3s no SSM para os workers do ASG lerem no boot.
until [ -s /var/lib/rancher/k3s/server/node-token ]; do sleep 2; done

aws ssm put-parameter \
  --region "${region}" \
  --name "${token_param_name}" \
  --type SecureString \
  --value "$(cat /var/lib/rancher/k3s/server/node-token)" \
  --overwrite

# Deixa o KUBECONFIG já setado em qualquer sessão interativa (SSM/SSH) nesta
# instância - sem isso, "kubectl" cai no default antigo (localhost:8080) e
# falha com um erro genérico ("couldn't get current server API group list")
# em vez de dizer que não achou o kubeconfig.
echo 'export KUBECONFIG=/etc/rancher/k3s/k3s.yaml' > /etc/profile.d/kubeconfig.sh

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
until /usr/local/bin/kubectl get nodes >/dev/null 2>&1; do sleep 2; done
/usr/local/bin/kubectl wait --for=condition=Ready node --all --timeout=180s

/usr/local/bin/kubectl create namespace mechanicltda --dry-run=client -o yaml \
  | /usr/local/bin/kubectl apply -f -

# ── metrics-server ───────────────────────────────────────────────────────
# Exigido pelo HPA (k8s/base/api-hpa.yaml e web-hpa.yaml) para expor CPU/
# memória dos pods — k3s não vem com ele instalado por padrão. Sem isso o
# HPA fica preso em "TARGETS: <unknown>/70%" e nunca escala.
# Retry pelo mesmo motivo do install do k3s acima: já vimos falha de SSL
# transitória baixando de trás de CDN, e "set -e" abortaria o script inteiro.
for i in $(seq 1 10); do
  if /usr/local/bin/kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml; then
    break
  fi
  echo "Falha ao aplicar o metrics-server (tentativa $i/10), tentando novamente em 15s..."
  sleep 15
done

# --kubelet-insecure-tls: o certificado do kubelet do k3s é self-signed
# (instância única, sem CA corporativa) — sem essa flag o metrics-server
# falha ao coletar métricas com "x509: certificate signed by unknown
# authority" e as métricas nunca aparecem.
# Falhas aqui não abortam o script (|| true): o HPA é um "extra" sobre a
# aplicação em si — API/Web funcionam sem métricas, então uma falha nesta
# etapa não pode derrubar o resto do boot (timer de refresh do ECR abaixo,
# sem o qual o pull de imagem quebra de verdade).
/usr/local/bin/kubectl patch deployment metrics-server -n kube-system --type=json \
  -p '[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]' \
  || echo "AVISO: falha ao aplicar --kubelet-insecure-tls no metrics-server"

/usr/local/bin/kubectl wait --for=condition=Available deployment/metrics-server -n kube-system --timeout=120s \
  || echo "AVISO: metrics-server nao ficou pronto a tempo - HPA nao vai escalar ate isso ser resolvido manualmente"

# Deploy da aplicação (ConfigMap/Secret/Deployments/Services/HPA) fica 100% a
# cargo da pipeline de CI/CD (.github/workflows/deploy.yml via SSM Run
# Command) — evita duas fontes de verdade para os manifestos.

# ── Refresh periódico das credenciais do ECR ────────────────────────────────
# k3s (containerd) não integra nativamente com IAM/ECR como o EKS, e o token
# de auth do ECR expira em 12h. Um timer local recria o Secret
# docker-registry "ecr-creds" a cada 6h usando a IAM role da própria
# instância; a pipeline também atualiza esse Secret a cada deploy.
cat <<'SCRIPT' > /opt/refresh-ecr-creds.sh
#!/bin/bash
set -eu
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

REGION="${region}"
REGISTRY="${ecr_registry_host}"
PASSWORD="$(aws ecr get-login-password --region "$REGION")"

/usr/local/bin/kubectl create secret docker-registry ecr-creds \
  --namespace mechanicltda \
  --docker-server="$REGISTRY" \
  --docker-username=AWS \
  --docker-password="$PASSWORD" \
  --dry-run=client -o yaml | /usr/local/bin/kubectl apply -f -
SCRIPT
chmod 700 /opt/refresh-ecr-creds.sh

cat <<'UNIT' > /etc/systemd/system/refresh-ecr-creds.service
[Unit]
Description=Atualiza o Secret docker-registry do ECR para o k3s
After=k3s.service
Requires=k3s.service

[Service]
Type=oneshot
ExecStart=/opt/refresh-ecr-creds.sh
UNIT

cat <<'TIMER' > /etc/systemd/system/refresh-ecr-creds.timer
[Unit]
Description=Roda refresh-ecr-creds.service a cada 6 horas

[Timer]
OnBootSec=1min
OnUnitActiveSec=6h

[Install]
WantedBy=timers.target
TIMER

systemctl daemon-reload
systemctl enable --now refresh-ecr-creds.timer
systemctl start refresh-ecr-creds.service
