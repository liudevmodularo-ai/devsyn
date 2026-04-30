#!/bin/bash
# DevSyn Deployment Fix Script v1.0
# Executa reparações específicas após diagnóstico

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

if [[ $EUID -ne 0 ]]; then
    error "Este script precisa rodar como root (use: sudo ./fix_deployment.sh)"
    exit 1
fi

info "🔧 Iniciando reparo da instalação DevSyn..."
echo ""

# ---------- Parar o serviço ----------
info "Parando o serviço..."
systemctl stop "$SERVICE_NAME" || true
sleep 2

# ---------- Remover venv existente (forçar recriação) ----------
info "Removendo venv existente (preparando para recriação)..."
if [[ -d "$APP_DIR/venv" ]]; then
    rm -rf "$APP_DIR/venv"
    info "  ✓ Venv removido"
else
    info "  (venv não existia)"
fi

# ---------- Recriar venv do zero ----------
info "Recriando virtual environment..."
sudo -u "$USER" bash -c "
    set -e
    cd '$APP_DIR'
    python3 -m venv venv
    source venv/bin/activate
    
    # Upgrade pip, wheel, setuptools
    pip install --upgrade pip wheel setuptools
    
    # Instalar requirements
    pip install -r requirements.txt
    
    # Instalar gunicorn explicitamente
    pip install gunicorn==22.0.0
    
    # Verificação final
    echo '[VERIFY] Gunicorn version:' 
    gunicorn --version
    
    deactivate
" || {
    error "Falha ao recriar venv. Verifique as mensagens acima."
    exit 1
}

# ---------- Validar instalação ----------
info "Validando instalação..."
if [[ ! -f "$APP_DIR/venv/bin/gunicorn" ]]; then
    error "Gunicorn ainda não foi instalado corretamente em $APP_DIR/venv/bin/gunicorn"
    exit 1
fi

# Testar que o user pode executar
if ! su - "$USER" -c "source $APP_DIR/venv/bin/activate && gunicorn --version" >/dev/null; then
    error "Usuário '$USER' não consegue executar gunicorn"
    exit 1
fi

info "  ✓ Gunicorn instalado e validado"

# ---------- Fix permissões ----------
info "Corrigindo permissões..."
chown -R "$USER:$USER" "$APP_DIR"
chmod 755 "$APP_DIR/venv/bin/gunicorn"

# ---------- Reload systemd e reiniciar serviço ----------
info "Recarregando systemd e reiniciando serviço..."
systemctl daemon-reload
systemctl start "$SERVICE_NAME"
sleep 3

# ---------- Validação final ----------
if systemctl is-active --quiet "$SERVICE_NAME"; then
    echo ""
    echo "============================================="
    echo -e "${GREEN}✅ Serviço restaurado com sucesso!${NC}"
    echo "============================================="
    echo "Status: $(systemctl is-active "$SERVICE_NAME")"
    echo ""
    info "Primeiros logs:"
    journalctl -u "$SERVICE_NAME" -n 10 --no-pager
else
    echo ""
    echo "============================================="
    echo -e "${RED}❌ Serviço ainda não está ativo${NC}"
    echo "============================================="
    echo ""
    error "Últimos logs:"
    journalctl -u "$SERVICE_NAME" -n 30 --no-pager || true
    exit 1
fi
