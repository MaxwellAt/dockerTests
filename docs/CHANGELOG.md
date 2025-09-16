# Changelog

Todas as mudanças notáveis neste projeto serão documentadas neste arquivo.

Formato baseado em Keep a Changelog e Semantic Versioning quando aplicável.

## [Unreleased]

### Alterado
- K6: salvar apenas o arquivo de métricas (summary) em `resultados/*_metrics.json`; o JSON bruto (`--out json=...`) foi desativado por padrão.
  - `main.py`: `executar_k6` agora recebe `output_path` opcional e `save_raw` (padrão `False`).
  - Chamadas atualizadas em `main.py` e em scripts de configuração para `save_raw=False` e `output_path=None`.
- Scripts de execução `run_stack_k6*.sh`:
  - Removido `eval` e corrigido quoting para caminhos com espaços (como `tests k6/`).
  - Adicionado `set -Eeuo pipefail` e criação de `resultados/` quando necessário.
- Orquestrador `chamar_bot.sh`:
  - Empacotamento atômico dos resultados via staging temporário (evita `.tar.gz` corrompidos).
  - Validação do `.tar.gz` com `tar -tzf` antes de apagar `resultados/`.
  - Envio ao Telegram torna-se resiliente (erros de `curl` não encerram o script).
  - Suporte a `TELEGRAM_TOKEN` e `TELEGRAM_CHAT_ID` por variável de ambiente.
  - Logs e mensagens mais claras por ciclo e script.

### Correções
- Evitados aborts acidentais do k6 por sinais e pelo uso de `eval` em shell scripts.

### Notas de Migração
- Para reativar o JSON bruto do k6 em um ponto específico: chame `executar_k6(..., output_path="resultados/arquivo.json", save_raw=True)`.
- `chamar_bot.sh` agora compacta e envia somente se houver conteúdo em `resultados/`.
