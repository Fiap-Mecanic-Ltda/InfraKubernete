#!/usr/bin/env bash
# Espera um comando do SSM terminar e imprime a invocacao em JSON.
#
# Substitui o "aws ssm wait command-executed", que desiste depois de 100s
# (20 tentativas de 5s) e devolve o comando ainda em InProgress. O deploy
# falhava por isso mesmo quando o kubectl no no estava so demorando.
#
# Uso: esperar-ssm.sh <command-id> <instance-id> [limite-em-segundos]
# Saida: JSON da invocacao no stdout; codigo 0 se terminou com Success.

set -uo pipefail

COMMAND_ID="${1:?informe o command id}"
INSTANCE_ID="${2:?informe o instance id}"
LIMITE="${3:-600}"

fim=$(( $(date +%s) + LIMITE ))
invocacao=""

while :; do
  invocacao=$(aws ssm get-command-invocation \
    --command-id "$COMMAND_ID" \
    --instance-id "$INSTANCE_ID" 2>/dev/null || true)

  status=$(printf '%s' "$invocacao" | python3 -c '
import json, sys
bruto = sys.stdin.read().strip()
print(json.loads(bruto)["Status"] if bruto else "Pending")
' 2>/dev/null || echo "Pending")

  case "$status" in
    Success)
      printf '%s' "$invocacao"
      exit 0
      ;;
    Cancelled|TimedOut|Failed)
      printf '%s' "$invocacao"
      exit 1
      ;;
  esac

  if [ "$(date +%s)" -ge "$fim" ]; then
    echo "Tempo esgotado depois de ${LIMITE}s com o comando em '$status'." >&2
    printf '%s' "$invocacao"
    exit 1
  fi

  sleep 10
done
