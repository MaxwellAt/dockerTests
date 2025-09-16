#!/bin/bash
# Script para executar múltiplos scripts Python variando o teste K6 passado como argumento
# Configure a variável TESTES_K6 para definir quais scripts de teste executar

set -Eeuo pipefail

# === CONFIGURAÇÃO INÍCIO ===
PY_SCRIPT="scripts/config_fixed_backend_prometheus.py"   # Script Python a ser executado
APP_URL="http://143.198.78.77"        # URL da aplicação
STACKS="node-postgres"                 # Stacks a testar
PASTA_K6="tests k6"                    # Pasta correta dos scripts K6
# Lista de scripts de teste K6 a serem usados
TESTES_K6=(
    "delete_users_250vus.js"
)
# === CONFIGURAÇÃO FIM ===

mkdir -p resultados

for TESTE_K6 in "${TESTES_K6[@]}"; do
    echo "[STACK] Executando: python3 $PY_SCRIPT --app_url $APP_URL --stacks $STACKS --k6_script '$PASTA_K6/$TESTE_K6' --repeticoes 1"
    python3 "$PY_SCRIPT" --app_url "$APP_URL" --stacks "$STACKS" --k6_script "$PASTA_K6/$TESTE_K6" --repeticoes 1
    echo "[STACK] Fim: $TESTE_K6"
done

echo "[STACK] Execução completa."
