#!/bin/bash
# DevSyn VPS Auto-Installer v4.2 (Fixed)
# Ubuntu 22.04 LTS | Nginx | SSL | Gunicorn | Systemd

set -euo pipefail

echo "🚀 DevSyn Platform - Auto Installer v4.2"
echo "======================================"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC}  $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
ask()   { echo -e "${BLUE}[?]${NC}     $1"; }

# ---------- Pre-flight: privilégios e diretório ----------
if [[ $EUID -ne 0 ]]; then
    error "Este script precisa rodar como root (use: sudo ./install.sh)"
    exit 1
fi

SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="/opt/devsyn"
USER="devsyn"
SERVICE_NAME="devsyn"
DEFAULT_PORT="5000"
PORT_FILE="$APP_DIR/.app_port"

if [[ ! -f "$SOURCE_DIR/run.py" || ! -f "$SOURCE_DIR/requirements.txt" ]]; then
    error "Este script deve estar dentro do diretório do projeto DevSyn."
    error "Esperado: run.py e requirements.txt em $SOURCE_DIR"
    exit 1
fi

info "Diretório de origem: $SOURCE_DIR"
info "Diretório de destino: $APP_DIR"

# ---------- Coleta de Dados ----------
echo ""
echo "============ CONFIGURAÇÃO ============"

if [[ -z "${DOMAIN:-}" ]]; then
    while true; do
        ask "Informe o domínio (ex: devsyn.seudominio.com):"
        read -r DOMAIN
        DOMAIN="${DOMAIN// /}"
        if [[ -z "$DOMAIN" ]]; then
            warn "Domínio não pode ser vazio."
        elif [[ ! "$DOMAIN" =~ ^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-9])?\.)+[a-zA-Z]{2,}$ ]]; then
            warn "Domínio inválido. Use formato: subdominio.dominio.com"
        else
            break
        fi
    done
fi

if [[ -z "${ADMIN_EMAIL:-}" ]]; then
    ask "Informe o e-mail do admin (Let's Encrypt) [admin@$DOMAIN]:"
    read -r ADMIN_EMAIL
    ADMIN_EMAIL="${ADMIN_EMAIL:-admin@$DOMAIN}"
fi

if [[ -z "${ENABLE_SSL:-}" ]]; then
    ask "Ativar SSL via Let's Encrypt? (s/N):"
    read -r RESP
    if [[ "$RESP" =~ ^[sSyY]$ ]]; then
        ENABLE_SSL="yes"
    else
        ENABLE_SSL="no"
    fi
fi

# ---------- Funções de Suporte ----------

nginx_health_check() {
    local stage="$1"
    local max_iter=12
    local iter=0
    local err_log
    err_log="$(mktemp)"

    while (( iter < max_iter )); do
        iter=$((iter + 1))

        if nginx -t >"$err_log" 2>&1; then
            rm -f "$err_log"
            [[ "$iter" -gt 1 ]] && info "  Nginx OK após auto-fix."
            return 0
        fi

        if [[ "$iter" -eq 1 ]]; then
            warn "Configuração Nginx inválida ($stage):"
            sed 's/^/    /' "$err_log" >&2
        fi

        local fixed_this_round=false

        # Auto-fix A: Arquivos SSL faltando
        while IFS= read -r missing; do
            local missing_file
            missing_file="$(echo "$missing" | sed -nE 's/.*open\(\) "([^"]+)" failed.*/\1/p')"
            [[ -z "$missing_file" || -f "$missing_file" ]] && continue

            case "$missing_file" in
                */options-ssl-nginx.conf)
                    warn "  Auto-fix: criando $missing_file..."
                    mkdir -p "$(dirname "$missing_file")"
                    cat > "$missing_file" <<'SSL_EOF'
ssl_session_cache shared:le_nginx_SSL:10m;
ssl_session_timeout 1440m;
ssl_session_tickets off;
ssl_protocols TLSv1.2 TLSv1.3;
ssl_prefer_server_ciphers off;
ssl_ciphers "ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384";
SSL_EOF
                    fixed_this_round=true
                    ;;
                */ssl-dhparams.pem)
                    warn "  Auto-fix: gerando $missing_file..."
                    mkdir -p "$(dirname "$missing_file")"
                    openssl dhparam -out "$missing_file" 2048 2>/dev/null
                    fixed_this_round=true
                    ;;
            esac
        done < <(grep -E 'open\(\) ".*" failed.*No such file' "$err_log" || true)

        if ! $fixed_this_round; then
            error "Nginx ainda inválido e não há mais auto-fixes aplicáveis."
            rm -f "$err_log"
            return 1
        fi
    done
    rm -f "$err_log"
    return 1
}

find_free_port() {
    local start_port="${1:-5000}"
    local max_port=$((start_port + 100))
    local p="$start_port"
    while [[ "$p" -lt "$max_port" ]]; do
        if ! ss -tlnH "sport = :$p" 2>/dev/null | grep -q LISTEN; then
            if ! grep -rE "proxy_pass\s+http(s)?://127\.0\.0\.1:$p\b" /etc/nginx/sites-enabled/ 2>/dev/null | grep -v "/$SERVICE_NAME:" | grep -q .; then
                echo "$p"
                return 0
            fi
        fi
        p=$((p + 1))
    done
    return 1
}

# ---------- Verificação de Conflitos (CORRIGIDO) ----------
info "Verificando conflitos com outros sites Nginx..."
if [[ -d /etc/nginx/sites-enabled ]]; then
    CONFLICT_SITE=""
    for site in /etc/nginx/sites-enabled/*; do
        [[ -e "$site" ]] || continue
        site_name="$(basename "$site")"
        [[ "$site_name" == "$SERVICE_NAME" ]] && continue
        if grep -E "^\s*server_name\s+" "$site" 2>/dev/null | grep -qE "(^|[[:space:]])${DOMAIN}([[:space:]]|;)"; then
            CONFLICT_SITE="$site_name"
            break
        fi
    done
    if [[ -n "$CONFLICT_SITE" ]]; then
        error "O domínio '$DOMAIN' já está reivindicado pelo site: $CONFLICT_SITE"
        exit 1
    fi
    info "  Nenhum conflito de server_name detectado."
fi # <--- Fim do bloco que estava causando erro

# ---------- Porta do App ----------
APP_PORT=""
if [[ -f "$PORT_FILE" ]]; then
    SAVED_PORT="$(cat "$PORT_FILE" 2>/dev/null | tr -dc '0-9')"
    [[ -n "$SAVED_PORT" ]] && APP_PORT="$SAVED_PORT"
fi

if [[ -z "$APP_PORT" ]]; then
    info "  Procurando porta livre a partir de $DEFAULT_PORT..."
    APP_PORT="$(find_free_port "$DEFAULT_PORT")" || {
        error "Não foi possível encontrar porta livre."
        exit 1
    }
fi

echo ""
info "Domínio:    $DOMAIN"
info "E-mail:     $ADMIN_EMAIL"
info "SSL:        $ENABLE_SSL"
info "Porta app:  $APP_PORT"
echo ""
ask "Confirmar e prosseguir? (S/n):"
read -r CONFIRM
if [[ "$CONFIRM" =~ ^[nN]$ ]]; then
    error "Instalação abortada."
    exit 1
fi

# ---------- Execução ----------

info "Atualizando o sistema..."
apt-get update -y && apt-get install -f -y

if ! id "$USER" &>/dev/null; then
    info "Criando usuário '$USER'..."
    adduser --disabled-password --gecos "" "$USER"
fi

info "Instalando dependências..."
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    python3 python3-venv python3-pip \
    nginx sqlite3 ufw rsync curl snapd openssl iproute2

nginx_health_check "inicial" || exit 1

info "Configurando virtualenv e dependências Python..."
mkdir -p "$APP_DIR"
rsync -a --delete --exclude 'venv/' --exclude '.git/' "$SOURCE_DIR/" "$APP_DIR/"
chown -R "$USER:$USER" "$APP_DIR"

sudo -u "$USER" bash -c "
cd '$APP_DIR'
python3 -m venv venv
venv/bin/pip install --upgrade pip
venv/bin/pip install -r requirements.txt gunicorn
"

info "Configurando Nginx..."
NGINX_CONF="/etc/nginx/sites-available/$SERVICE_NAME"
cat > "$NGINX_CONF" <<NGINX_EOF
server {
    listen 80;
    server_name $DOMAIN;
    client_max_body_size 50M;
    location / {
        proxy_pass http://127.0.0.1:${APP_PORT};
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
NGINX_EOF

ln -sf "$NGINX_CONF" "/etc/nginx/sites-enabled/$SERVICE_NAME"
systemctl reload nginx

info "Configurando Systemd..."
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
cat > "$SERVICE_FILE" <<SVC_EOF
[Unit]
Description=DevSyn Platform
After=network.target

[Service]
User=$USER
WorkingDirectory=$APP_DIR
EnvironmentFile=$APP_DIR/.env
ExecStart=$APP_DIR/venv/bin/gunicorn --workers 3 --bind 127.0.0.1:${APP_PORT} src.app:app
Restart=always

[Install]
WantedBy=multi-user.target
SVC_EOF

systemctl daemon-reload
systemctl enable "$SERVICE_NAME"
systemctl restart "$SERVICE_NAME"

if [[ "$ENABLE_SSL" == "yes" ]]; then
    info "Configurando SSL..."
    snap install --classic certbot || true
    ln -sf /snap/bin/certbot /usr/bin/certbot || true
    certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos -m "$ADMIN_EMAIL" --redirect || warn "Falha no SSL automático."
fi

info "Instalação concluída com sucesso!"
echo "URL: http://$DOMAIN"