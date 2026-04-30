#!/bin/bash
# DevSyn Diagnostic Script
# Coleta informações de diagnóstico para resolver problemas de deployment

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC}  $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

APP_DIR="/opt/devsyn"
USER="devsyn"
SERVICE_NAME="devsyn"

echo "======================================="
echo "🔍 DevSyn Deployment Diagnostic"
echo "======================================="
echo ""

# 1. Diretório principal
info "1️⃣  Verificando diretório principal..."
if [[ -d "$APP_DIR" ]]; then
    echo "  ✓ Existe: $APP_DIR"
    du -sh "$APP_DIR"
else
    error "Diretório não existe: $APP_DIR"
fi
echo ""

# 2. Usuário
info "2️⃣  Verificando usuário '$USER'..."
if id "$USER" &>/dev/null; then
    echo "  ✓ Usuário existe"
    echo "    $(id "$USER")"
else
    error "Usuário não existe: $USER"
fi
echo ""

# 3. Venv
info "3️⃣  Verificando virtualenv..."
if [[ -d "$APP_DIR/venv" ]]; then
    echo "  ✓ Diretório venv existe"
    ls -la "$APP_DIR/venv/bin/python"* 2>/dev/null | head -3
else
    error "  ✗ Diretório venv NÃO existe"
fi
echo ""

# 4. Gunicorn
info "4️⃣  Verificando Gunicorn..."
if [[ -f "$APP_DIR/venv/bin/gunicorn" ]]; then
    echo "  ✓ Executável encontrado: $APP_DIR/venv/bin/gunicorn"
    if su - "$USER" -c "source $APP_DIR/venv/bin/activate && gunicorn --version" 2>/dev/null; then
        echo "  ✓ Gunicorn funcional para o usuário '$USER'"
    else
        error "  ✗ Gunicorn não é executável para o usuário '$USER'"
    fi
else
    error "  ✗ Gunicorn NÃO encontrado em $APP_DIR/venv/bin/gunicorn"
fi
echo ""

# 5. Requirements instalados
info "5️⃣  Verificando pacotes instalados..."
if [[ -d "$APP_DIR/venv" ]]; then
    echo "  Pacotes críticos:"
    su - "$USER" -c "source $APP_DIR/venv/bin/activate && pip list | grep -E '(Flask|gunicorn|chromadb|openai|google-generativeai|pydantic)'" 2>/dev/null || warn "  ✗ Não conseguiu ler pacotes"
else
    error "  ✗ Venv não existe, não foi possível listar pacotes"
fi
echo ""

# 6. Arquivo .env
info "6️⃣  Verificando configuração .env..."
if [[ -f "$APP_DIR/.env" ]]; then
    echo "  ✓ Arquivo .env existe"
    ls -la "$APP_DIR/.env"
else
    warn "  ⚠️  .env não encontrado"
fi
echo ""

# 7. SHA256 de requirements (sinal de rebuild necessário)
info "7️⃣  Verificando histórico de instalação..."
if [[ -f "$APP_DIR/.requirements.sha256" ]]; then
    SHA_SAVED="$(cat "$APP_DIR/.requirements.sha256")"
    SHA_CURRENT="$(sha256sum "$APP_DIR/requirements.txt" | awk '{print $1}')"
    if [[ "$SHA_SAVED" == "$SHA_CURRENT" ]]; then
        echo "  ✓ requirements.txt não mudou desde última instalação"
    else
        warn "  ⚠️  requirements.txt mudou"
        warn "    Último hash: ${SHA_SAVED:0:16}..."
        warn "    Hash atual:  ${SHA_CURRENT:0:16}..."
    fi
else
    warn "  ⚠️  Sem histórico de hash (primeira instalação?)"
fi
echo ""

# 8. Service systemd
info "8️⃣  Verificando serviço systemd..."
if systemctl is-active --quiet "$SERVICE_NAME"; then
    echo "  ✅ Serviço está ATIVO"
else
    echo "  ❌ Serviço está INATIVO"
fi

if [[ -f "/etc/systemd/system/${SERVICE_NAME}.service" ]]; then
    echo "  ✓ Arquivo de serviço existe"
    echo "    ExecStart: $(grep '^ExecStart=' /etc/systemd/system/${SERVICE_NAME}.service || echo '[not found]')"
else
    error "  ✗ Arquivo de serviço não existe"
fi
echo ""

# 9. Logs
info "9️⃣  Últimos logs do serviço (últimas 20 linhas)..."
echo ""
journalctl -u "$SERVICE_NAME" -n 20 --no-pager || true
echo ""

# 10. Nginx
info "🔟 Verificando Nginx..."
if nginx -t 2>&1 | grep -q "successful"; then
    echo "  ✓ Nginx configuração OK"
    if systemctl is-active --quiet nginx; then
        echo "  ✓ Nginx está rodando"
    else
        warn "  ⚠️  Nginx não está rodando"
    fi
else
    error "  ✗ Nginx com problemas na configuração"
    nginx -t 2>&1 | sed 's/^/    /'
fi
echo ""

echo "======================================="
echo "🏁 Diagnóstico completo"
echo "======================================="
