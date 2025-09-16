#!/bin/bash
# chamar_bot.sh
# Orquestra 3 scripts em sequência. Após cada execução:
# - Gera um .tar.gz de 'resultados/' de forma atômica
# - Valida o tar
# - Envia ao Telegram
# - Limpa e recria 'resultados/'

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

SCRIPT1="run_stack_k6.sh"
SCRIPT2="run_stack_k6-250vus.sh"
SCRIPT3="run_stack_k6-500vus.sh"
RESULTADOS_DIR="resultados"

# Use variáveis de ambiente se estiverem definidas; mantenha default local como fallback
TOKEN="${TELEGRAM_TOKEN:-8262830230:AAGEjQzyqPVLtUuOSAB5yFqE3_CyIlzjHX4}"
CHAT_ID="${TELEGRAM_CHAT_ID:-1277981659}"
REPEAT=${REPEAT:-3}

# Evita que falhas no curl abortem o script (com set -e habilitado)
send_msg() {
    local text="$1"
    if [ -n "${TOKEN:-}" ] && [ -n "${CHAT_ID:-}" ]; then
        if ! curl -fsS -X POST "https://api.telegram.org/bot$TOKEN/sendMessage" \
            --data-urlencode "chat_id=$CHAT_ID" \
            --data-urlencode "text=$text" >/dev/null; then
            echo "[WARN] Falha ao enviar mensagem ao Telegram"
        fi
    else
        echo "[INFO] TOKEN/CHAT_ID não configurados; pulando envio de mensagem"
    fi
}

send_file() {
    local file="$1"
    if [ ! -f "$file" ]; then
        echo "[WARN] Arquivo $file não existe para envio"
        return 0
    fi
    if [ -n "${TOKEN:-}" ] && [ -n "${CHAT_ID:-}" ]; then
        if ! curl -fsS -X POST "https://api.telegram.org/bot$TOKEN/sendDocument" \
            -F chat_id="$CHAT_ID" \
            -F document=@"$file" >/dev/null; then
            echo "[WARN] Falha ao enviar arquivo $file ao Telegram"
        fi
    else
        echo "[INFO] TOKEN/CHAT_ID não configurados; pulando envio de arquivo"
    fi
}

cleanup_tmp() {
    local tmpdir="${1:-}"
    if [ -n "$tmpdir" ] && [ -d "$tmpdir" ]; then
        rm -rf "$tmpdir" || true
    fi
}

trap 'echo "[INFO] Sinal recebido, finalizando com segurança..."' SIGINT SIGTERM

package_results() {
    local ciclo="$1" script_base="$2"

    if [ ! -d "$RESULTADOS_DIR" ]; then
        send_msg "⚠️ [Ciclo $ciclo][$script_base] pasta '$RESULTADOS_DIR' não encontrada — nada a compactar"
        return 0
    fi

    # Evita tar vazio (quando pasta existe mas está vazia)
    if [ -z "$(ls -A "$RESULTADOS_DIR" 2>/dev/null || true)" ]; then
        send_msg "⚠️ [Ciclo $ciclo][$script_base] pasta '$RESULTADOS_DIR' está vazia — nada a compactar"
        return 0
    fi

    local zip_name="${RESULTADOS_DIR}_${script_base}_ciclo${ciclo}_$(date +%Y%m%d_%H%M%S).tar.gz"
    local tmpdir
    tmpdir="$(mktemp -d)"
    # Cópia atômica para staging
    cp -a "$RESULTADOS_DIR" "$tmpdir/" 
    # Compacta a partir do staging para evitar alterações durante tar
    tar -C "$tmpdir" -czf "$zip_name" "$(basename "$RESULTADOS_DIR")"
    # Valida o tar
    if tar -tzf "$zip_name" >/dev/null 2>&1; then
        send_msg "📦 [Ciclo $ciclo][$script_base] compactado em $zip_name"
        # grava o tamanho da pasta 'resultados' em um arquivo de log ao lado do .tar.gz
        size_log="${zip_name%.tar.gz}.size.log"
        size="$(du -sh "$RESULTADOS_DIR" 2>/dev/null | awk '{print $1}')"
        printf '%s size=%s path=%s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$size" "$RESULTADOS_DIR" > "$size_log" || \
            echo "[WARN] Falha ao escrever $size_log"
        # Remove pasta original somente após tar válido
        rm -rf "$RESULTADOS_DIR"
        send_file "$zip_name"
        # Opcional: remover o .tar.gz após envio
        # rm -f "$zip_name"
    else
        send_msg "⚠️ [Ciclo $ciclo][$script_base] arquivo $zip_name inválido (tar corrupto)"
    fi
    cleanup_tmp "$tmpdir"
}

mkdir -p "$RESULTADOS_DIR"

# loop principal
for i in $(seq 1 "$REPEAT"); do
    echo "=== Ciclo $i ==="

    for SCRIPT in "$SCRIPT1" "$SCRIPT2" "$SCRIPT3"; do
        local_script_path="$SCRIPT_DIR/$SCRIPT"
        if [ ! -x "$local_script_path" ]; then
            echo "[WARN] Script $local_script_path não é executável ou inexistente; tentando com bash"
        fi
        echo "--- Executando $SCRIPT (início: $(date)) ---"
        # executa o script e captura o código de saída
        if [ -x "$local_script_path" ]; then
            "$local_script_path" || true
            rc=$?
        else
            bash "$local_script_path" || true
            rc=$?
        fi

        # envia status da execução
        if [ ${rc:-1} -eq 0 ]; then
            send_msg "✅ [Ciclo $i] $SCRIPT finalizou com sucesso às $(date)"
        else
            send_msg "❌ [Ciclo $i] $SCRIPT terminou com erro (exit=${rc:-1}) às $(date)"
        fi

        # compacta, envia e apaga a pasta de resultados (se existir)
        script_base="$(basename "$SCRIPT" .sh)"
        package_results "$i" "$script_base"

        # recria a pasta resultados vazia para o próximo script
        mkdir -p "$RESULTADOS_DIR"
        echo "--- Fim $SCRIPT (fim: $(date)) ---"
    done
done

