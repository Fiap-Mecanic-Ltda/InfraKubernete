#!/bin/bash
set -eux
exec > >(tee /var/log/user-data.log) 2>&1

dnf update -y
dnf install -y aws-cli

REGION="${region}"

# O parametro pode ainda nao existir se este worker subir no mesmo instante
# em que o server ainda esta terminando o proprio boot (ASG nao espera o
# server ficar pronto). Retry, no lugar de falha dura.
TOKEN=""
for i in $(seq 1 20); do
  TOKEN=$(aws ssm get-parameter --region "$REGION" --name "${token_param_name}" \
    --with-decryption --query 'Parameter.Value' --output text 2>/dev/null || true)
  if [ -n "$TOKEN" ] && [ "$TOKEN" != "None" ]; then
    break
  fi
  echo "Token do k3s ainda nao disponivel no SSM (tentativa $i/20), tentando novamente em 15s..."
  sleep 15
done

if [ -z "$TOKEN" ] || [ "$TOKEN" = "None" ]; then
  echo "ERRO: nao consegui obter o token do k3s do SSM apos 20 tentativas" >&2
  exit 1
fi

# O IP do server e resolvido no boot, pela tag Name, em vez de usar so o valor
# fixado no template: quando a EC2 do server e substituida ela ganha um IP novo,
# e um worker que ficou com o IP antigo nunca mais consegue entrar no cluster
# (erro real: "dial tcp <ip-antigo>:6443: connect: no route to host", com o
# worker continuando a servir pods orfaos da geracao anterior do cluster).
# O valor do template fica como fallback, para o caso da consulta falhar.
SERVER_IP=$(aws ec2 describe-instances --region "$REGION"   --filters "Name=tag:Name,Values=${server_name_tag}" "Name=instance-state-name,Values=running"   --query "Reservations[0].Instances[0].PrivateIpAddress" --output text 2>/dev/null || true)

if [ -z "$SERVER_IP" ] || [ "$SERVER_IP" = "None" ]; then
  echo "Nao consegui descobrir o server pela tag; usando o IP do template (${server_private_ip})." >&2
  SERVER_IP="${server_private_ip}"
fi

echo "Entrando no cluster via https://$SERVER_IP:6443"

for i in $(seq 1 10); do
  if curl -sfL https://get.k3s.io | K3S_URL="https://$SERVER_IP:6443" K3S_TOKEN="$TOKEN" sh -; then
    break
  fi
  echo "Falha ao instalar k3s agent (tentativa $i/10), tentando novamente em 15s..." >&2
  sleep 15
done

if ! systemctl is-active --quiet k3s-agent; then
  echo "ERRO: k3s-agent nao ficou ativo apos 10 tentativas" >&2
  exit 1
fi
