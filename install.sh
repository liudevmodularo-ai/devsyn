#!/bin/bash
# DevSyn VPS Auto-Installer v2
# Ubuntu 22.04 LTS | Nginx | SSL | Python | Systemd

set -e

echo "🚀 DevSyn Platform - Auto Installer v2"
echo "=================================="

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Configurações
DOMAIN=${DOMAIN:-"devsyn.yourdomain.com"}
APP_DIR="/opt/devsyn"
USER="devsyn"
SERVICE_NAME="devsyn"

# Fix dpkg conflicts first
info "Fixing dpkg conflicts..."
dpkg --configure -a || true
apt-get install -f -y || true

# 1. Update System
info "Updating system..."
apt update && apt upgrade -y

# 2. Create user
if ! id "$USER" &>/dev/null; then
    info "Creating $USER user..."
    adduser --disabled-password --gecos "" $USER
fi

# 3. Install dependencies (Python 3.10 padrão Ubuntu 22.04)
info "Installing system dependencies..."
apt install -y \
    python3 python3-venv python3-pip \
    nginx certbot python3-certbot-nginx git sqlite3 ufw

# 4. Python virtualenv
info "Setting up Python environment..."
if [ ! -d $APP_DIR ]; then
  git clone https://github.com/usuario/devsyn.git $APP_DIR
else
  cd $APP_DIR && git pull
fi
chown -R $USER:$USER $APP_DIR
cd $APP_DIR

su - $USER -c "
if [ ! -f venv/bin/activate ]; then
  python3 -m venv venv
fi
source venv/bin/activate &&
pip install --upgrade pip &&
pip install -r requirements.txt &&
deactivate
"

# 5. Nginx config
info "Configuring Nginx..."
cat > /etc/nginx/sites-available/$SERVICE_NAME << 'EOF'
server {
    listen 80;
    server_name DOMAIN_PLACEHOLDER;
    
    location / {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
EOF

sed -i "s/DOMAIN_PLACEHOLDER/$DOMAIN/g" /etc/nginx/sites-available/$SERVICE_NAME

ln -sf /etc/nginx/sites-available/$SERVICE_NAME /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
nginx -t

# 6. Systemd service
info "Creating systemd service..."
cat > /etc/systemd/system/$SERVICE_NAME.service << EOF
[Unit]
Description=DevSyn Platform
After=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=$APP_DIR
Environment=PATH=/opt/devsyn/venv/bin
ExecStart=/opt/devsyn/venv/bin/python run.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable $SERVICE_NAME

# 7. Firewall
ufw allow 'Nginx Full'
ufw allow ssh
ufw --force enable

# 8. SSL
info "Configuring SSL..."
certbot --nginx -d $DOMAIN --noninteractive --agree-tos -m admin@$DOMAIN || {
    warn "SSL needs manual setup: certbot --nginx -d $DOMAIN"
}

# 9. Final setup
info "Creating .env..."
cp $APP_DIR/.env.example $APP_DIR/.env
chown $USER:$USER $APP_DIR/.env

systemctl start $SERVICE_NAME

echo ""
echo "🎉 DevSyn instalada com sucesso!"
echo "🌐 Acesse: https://$DOMAIN"
echo "🔧 .env: $APP_DIR/.env (edite com API keys)"
echo "📊 Logs: journalctl -u $SERVICE_NAME -f"
echo "🔄 Restart: systemctl restart $SERVICE_NAME"
