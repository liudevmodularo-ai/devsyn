#!/bin/bash
# DevSyn VPS Auto-Installer v4.2 (non-destructive, iterative auto-fix, cert recovery)
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

# ---------- Coleta de dados ----------
echo ""
echo "============ CONFIGURAÇÃO ============"

if [[ -z "${DOMAIN:-}" ]]; then
    while true; do
        ask "Informe o domínio (ex: devsyn.seudominio.com):"
        read -r DOMAIN
        DOMAIN="$(echo "$DOMAIN" | tr -d '[:space:]')" # Remove todos os caracteres de espaço em branco (incluindo \n, \r, etc.)
        if [[ -z "$DOMAIN" ]]; then
            warn "Domínio não pode ser vazio."
        elif [[ ! "$DOMAIN" =~ ^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$ ]]; then
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

# ---------- Health-check do Nginx (genérico, com auto-fix iterativo) ----------
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

        # Auto-fix A: arquivos de configuração SSL referenciados mas faltando
        while IFS= read -r missing; do
            local missing_file
            missing_file="$(echo "$missing" | sed -nE 's/.*open\(\) "([^"]+)" failed.*/\1/p')"
            [[ -z "$missing_file" || -f "$missing_file" ]] && continue

            case "$missing_file" in
                */options-ssl-nginx.conf)
                    warn "  Auto-fix: criando $missing_file (padrão certbot)..."
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
                    warn "  Auto-fix: gerando $missing_file (2048 bits, ~30s)..."
                    mkdir -p "$(dirname "$missing_file")"
                    openssl dhparam -out "$missing_file" 2048 2>/dev/null
                    fixed_this_round=true
                    ;;
            esac
        done < <(grep -E 'open\(\) ".*" failed.*No such file' "$err_log" || true)

        # Auto-fix B: certificado Let's Encrypt referenciado mas inexistente
        # Padrão: /etc/letsencrypt/live/<dominio>/fullchain.pem
        while IFS= read -r cert_err; do
            local cert_path cert_domain
            cert_path="$(echo "$cert_err" | sed -nE 's/.*"(\/etc\/letsencrypt\/live\/[^"/]+\/[^"]+)".*/\1/p')"
            [[ -z "$cert_path" || -f "$cert_path" ]] && continue
            cert_domain="$(echo "$cert_path" | sed -nE 's|/etc/letsencrypt/live/([^/]+)/.*|\1|p')"
            [[ -z "$cert_domain" ]] && continue

            warn "  Detectado: certificado SSL faltando para domínio '$cert_domain'."
            warn "  Tentando re-emitir via certbot --standalone (porta 80 será usada brevemente)..."

            # Garante que temos certbot funcional
            local CB
            if command -v certbot >/dev/null && certbot --version >/dev/null 2>&1; then
                CB="$(command -v certbot)"
            elif [[ -x /snap/bin/certbot ]]; then
                CB="/snap/bin/certbot"
            else
                warn "  Sem certbot funcional disponível. Pulei a re-emissão."
                break
            fi

            # Para nginx temporariamente para liberar porta 80
            local nginx_was_up=false
            if systemctl is-active --quiet nginx; then
                nginx_was_up=true
                systemctl stop nginx
            fi

            local cb_email="${ADMIN_EMAIL:-admin@$cert_domain}"
            if "$CB" certonly --standalone \
                -d "$cert_domain" \
                --non-interactive --agree-tos \
                -m "$cb_email" 2>&1 | sed 's/^/    /'; then
                info "  Certificado re-emitido para $cert_domain."
                fixed_this_round=true
            else
                warn "  Falha ao re-emitir cert para $cert_domain."
                warn "  Verifique se o DNS de $cert_domain ainda aponta para este servidor."
                warn "  Você pode rodar manualmente:"
                warn "    sudo certbot certonly --standalone -d $cert_domain -m SEU_EMAIL --agree-tos"
            fi

            # Religa nginx (mesmo se cert falhou, para tentar próximas iterações)
            $nginx_was_up && systemctl start nginx 2>/dev/null || true
        done < <(grep -E 'cannot load certificate.*"\/etc\/letsencrypt\/live\/' "$err_log" || true)

        if ! $fixed_this_round; then
            error "Nginx ainda inválido e não há mais auto-fixes aplicáveis."
            error "Saída de 'nginx -t':"
            nginx -t 2>&1 | sed 's/^/    /' >&2
            error "Resolva os problemas acima e rode novamente."
            rm -f "$err_log"
            return 1
        fi
    done

    error "Health-check do Nginx atingiu o limite de $max_iter iterações."
    rm -f "$err_log"
    return 1
}

# ---------- Detecção de conflito de domínio (genérica) ----------
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
        error "O domínio '$DOMAIN' já está reivindicado pelo site Nginx: $CONFLICT_SITE"
        error "Edite /etc/nginx/sites-available/$CONFLICT_SITE e remova esse server_name antes de continuar."
        exit 1
    fi
    info "  Nenhum conflito de server_name detectado."
fi # <--- Adicionado para fechar o bloco 'if'

# ---------- Detecção automática de porta livre ----------
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

APP_PORT=""
if [[ -f "$PORT_FILE" ]]; then
    SAVED_PORT="$(cat "$PORT_FILE" 2>/dev/null | tr -dc '0-9')"
    if [[ -n "$SAVED_PORT" ]]; then
        if ! ss -tlnH "sport = :$SAVED_PORT" 2>/dev/null | grep -q LISTEN; then
            APP_PORT="$SAVED_PORT"
            info "  Reusando porta salva: $APP_PORT"
        elif systemctl is-active --quiet "$SERVICE_NAME"; then
            CURRENT_PID="$(systemctl show -p MainPID --value "$SERVICE_NAME" 2>/dev/null || echo 0)"
            if [[ "$CURRENT_PID" -gt 0 ]] && ss -tlnpH "sport = :$SAVED_PORT" 2>/dev/null | grep -q "pid=$CURRENT_PID"; then
                APP_PORT="$SAVED_PORT"
                info "  Reusando porta atual do serviço: $APP_PORT"
            fi
        fi
    fi
}

if [[ -z "$APP_PORT" ]]; then
    info "  Procurando porta livre a partir de $DEFAULT_PORT..."
    APP_PORT="$(find_free_port "$DEFAULT_PORT")" || {
        error "Não foi possível encontrar uma porta livre entre $DEFAULT_PORT e $((DEFAULT_PORT + 100))."
        exit 1
    }
}

echo ""
info "Domínio:    $DOMAIN"
info "E-mail:     $ADMIN_EMAIL"
info "SSL:        $ENABLE_SSL"
info "Porta app:  $APP_PORT"
echo ""
ask "Confirmar e prosseguir? (S/n):"
read -r CONFIRM
if [[ "$CONFIRM" =~ ^[nN]$ ]]; then
    error "Instalação abortada pelo usuário."
    exit 1
fi

# ---------- Fix dpkg ----------
info "Corrigindo conflitos do dpkg (se houver)..."
dpkg --configure -a || true
apt-get install -f -y || true

# ---------- Update system ----------
info "Atualizando o sistema..."
DEBIAN_FRONTEND=noninteractive apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y

# ---------- Cria usuário do sistema ----------
if ! id "$USER" &>/dev/null; then
    info "Criando usuário '$USER'..."
    adduser --disabled-password --gecos "" "$USER"
else
    info "Usuário '$USER' já existe."
fi

# ---------- Dependências do sistema (NÃO REMOVE NADA) ----------
info "Instalando dependências do sistema..."
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    python3 python3-venv python3-pip \
    nginx sqlite3 ufw rsync curl snapd iproute2 openssl

# ---------- Health-check inicial do Nginx (com auto-fix) ----------
info "Verificando integridade da configuração Nginx atual..."
nginx_health_check "inicial" || exit 1

# ---------- Garante certbot funcional (sem remover o apt) ----------
info "Verificando certbot..."
CERTBOT_OK=false
if command -v certbot >/dev/null 2>&1; then
    if certbot --version >/dev/null 2>&1; then
        CERTBOT_OK=true
        info "  Certbot funcional: $(certbot --version 2>&1 | head -1)"
    else
        warn "  Certbot existe mas falha ao executar (provavelmente bug de OpenSSL/cryptography)."
    fi
fi

if ! $CERTBOT_OK; then
    info "  Instalando certbot via snap (sem mexer no apt)..."
    snap install core 2>/dev/null || true
    snap refresh core 2>/dev/null || true
    snap install --classic certbot 2>/dev/null || snap refresh certbot || true
    # Symlink só se não houver um certbot funcional já
    if [[ -x /snap/bin/certbot ]]; then
        ln -sf /snap/bin/certbot /usr/local/bin/certbot
        export PATH="/usr/local/bin:$PATH"
    fi
    if /snap/bin/certbot --version >/dev/null 2>&1; then
        CERTBOT_OK=true
        info "  Certbot snap pronto."
    fi
}

# ---------- Copia o projeto para /opt/devsyn ----------
info "Copiando arquivos do projeto para $APP_DIR..."
mkdir -p "$APP_DIR"

PRESERVED_ENV=""
if [[ -f "$APP_DIR/.env" ]]; then
    PRESERVED_ENV="$(mktemp)"
    cp "$APP_DIR/.env" "$PRESERVED_ENV"
    info "  .env existente preservado (será restaurado)."
fi

rsync -a --delete \
    --exclude 'venv/' \
    --exclude '__pycache__/' \
    --exclude '*.pyc' \
    --exclude '.git/' \
    --exclude '.env' \
    --exclude 'logs/*' \
    --exclude '.app_port' \
    --exclude '.requirements.sha256' \
    "$SOURCE_DIR/" "$APP_DIR/"

if [[ -n "$PRESERVED_ENV" ]]; then
    cp "$PRESERVED_ENV" "$APP_DIR/.env"
    rm -f "$PRESERVED_ENV"
elif [[ -f "$APP_DIR/.env.example" ]]; then
    cp "$APP_DIR/.env.example" "$APP_DIR/.env"
    info "  .env criado a partir de .env.example (lembre de editar com suas API keys)."
fi

mkdir -p "$APP_DIR/logs" "$APP_DIR/data"
echo "$APP_PORT" > "$PORT_FILE"
chown -R "$USER:$USER" "$APP_DIR"
chmod 600 "$APP_DIR/.env" || true

# ---------- Python venv + dependências ----------
info "Configurando virtualenv Python..."
REQ_HASH_FILE="$APP_DIR/.requirements.sha256"
NEW_HASH="$(sha256sum "$APP_DIR/requirements.txt" | awk '{print $1}')"
OLD_HASH=""
[[ -f "$REQ_HASH_FILE" ]] && OLD_HASH="$(cat "$REQ_HASH_FILE" 2>/dev/null)"
if [[ "$NEW_HASH" != "$OLD_HASH" ]]; then
    info "  requirements.txt mudou - recriando venv do zero..."
    rm -rf "$APP_DIR/venv"
fi

sudo -u "$USER" bash -c "
pip cache purge # Limpa o cache do pip para evitar problemas de dependência
set -e
cd '$APP_DIR'
if [ ! -f venv/bin/activate ]; then
    python3 -m venv venv
fi
source venv/bin/activate
pip install --upgrade pip wheel setuptools
pip install -r requirements.txt
pip install gunicorn
deactivate
"
echo "$NEW_HASH" > "$REQ_HASH_FILE"
chown "$USER:$USER" "$REQ_HASH_FILE"

# ---------- Nginx (devsyn site) ----------
info "Configurando Nginx (porta upstream: $APP_PORT)..."
NGINX_CONF="/etc/nginx/sites-available/$SERVICE_NAME"
cat > "$NGINX_CONF" <<NGINX_EOF
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;

    client_max_body_size 50M;

    access_log /var/log/nginx/${SERVICE_NAME}_access.log;
    error_log  /var/log/nginx/${SERVICE_NAME}_error.log;

    location / {
        proxy_pass http://127.0.0.1:${APP_PORT};
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 300s;
        proxy_send_timeout 300s;
    }
}
NGINX_EOF

ln -sf "$NGINX_CONF" "/etc/nginx/sites-enabled/$SERVICE_NAME"
# NÃO mexe em /etc/nginx/sites-enabled/default nem em outros sites

info "Validando configuração final do Nginx..."
nginx_health_check "final" || exit 1
systemctl reload nginx || systemctl restart nginx

# ---------- Systemd (Gunicorn em produção) ----------
info "Criando serviço systemd ($SERVICE_NAME) na porta $APP_PORT..."
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
cat > "$SERVICE_FILE" <<SVC_EOF
[Unit]
Description=DevSyn Platform (Gunicorn)
After=network.target

[Service]
Type=simple
User=$USER
Group=$USER
WorkingDirectory=$APP_DIR
EnvironmentFile=$APP_DIR/.env
Environment=PATH=$APP_DIR/venv/bin
Environment=PYTHONUNBUFFERED=1
Environment=FLASK_ENV=production
Environment=APP_PORT=$APP_PORT
ExecStart=$APP_DIR/venv/bin/gunicorn \\
    --workers 3 \\
    --worker-class sync \\
    --bind 127.0.0.1:${APP_PORT} \\
    --access-logfile $APP_DIR/logs/access.log \\
    --error-logfile $APP_DIR/logs/error.log \\
    --timeout 120 \\
    src.app:app
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
SVC_EOF

systemctl daemon-reload
systemctl enable "$SERVICE_NAME"
systemctl restart "$SERVICE_NAME"

sleep 3
SERVICE_OK=true
if ! systemctl is-active --quiet "$SERVICE_NAME"; then
    SERVICE_OK=false
    warn "Serviço $SERVICE_NAME não ficou ativo. Últimos logs:"
    journalctl -u "$SERVICE_NAME" -n 30 --no-pager || true
fi

# ---------- Firewall ----------
info "Configurando firewall (UFW)..."
ufw allow OpenSSH || ufw allow ssh || true
ufw allow 'Nginx Full' || true
ufw --force enable

# ---------- SSL (Let's Encrypt) ----------
SSL_OK="no"
if [[ "$ENABLE_SSL" == "yes" && "$SERVICE_OK" == "true" ]]; then
    info "Solicitando certificado SSL para $DOMAIN..."
    CERTBOT_BIN="$(command -v certbot || echo /snap/bin/certbot)"
    if "$CERTBOT_BIN" --nginx \
        -d "$DOMAIN" \
        --non-interactive \
        --agree-tos \
        --redirect \
        -m "$ADMIN_EMAIL"; then
        SSL_OK="yes"
        info "SSL configurado com sucesso."
    else
        warn "Falha ao emitir SSL automaticamente."
        warn "Verifique se o DNS de $DOMAIN aponta para este servidor e rode:"
        warn "  certbot --nginx -d $DOMAIN -m $ADMIN_EMAIL --agree-tos --redirect"
    fi
elif [[ "$ENABLE_SSL" == "yes" ]]; then
    warn "SSL pulado: serviço não está ativo. Corrija o app antes."
else
    info "SSL desativado pelo usuário (rode certbot manualmente quando quiser)."
fi

# ---------- Status final ----------
echo ""
echo "============================================="
echo "🎉 DevSyn instalada!"
echo "============================================="
SCHEME="http"
[[ "$SSL_OK" == "yes" ]] && SCHEME="https"
echo "🌐 URL:        ${SCHEME}://$DOMAIN"
echo "📁 App:        $APP_DIR"
echo "🔌 Porta:      $APP_PORT (interna, atrás do nginx)"
echo "🔧 .env:       $APP_DIR/.env  (edite com suas API keys)"
echo "📊 Logs app:   journalctl -u $SERVICE_NAME -f"
echo "📊 Logs nginx: /var/log/nginx/${SERVICE_NAME}_*.log"
echo "🔄 Restart:    systemctl restart $SERVICE_NAME"
echo "▶️  Status:     systemctl status $SERVICE_NAME"
echo "============================================="

if ! $SERVICE_OK; then
    echo ""
    warn "⚠️  Serviço $SERVICE_NAME não está rodando. Cheque o log acima."
fi

if grep -q "your_openai_api_key_here" "$APP_DIR/.env" 2>/dev/null; then
    echo ""
    warn "⚠️  Edite $APP_DIR/.env e adicione suas API keys, depois rode:"
    warn "    systemctl restart $SERVICE_NAME"
fi
