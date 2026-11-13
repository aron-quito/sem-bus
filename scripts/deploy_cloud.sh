#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════
# BUS CONECTADO • SCRIPT DE DESPLIEGUE EN SERVIDOR CLOUD
# ═══════════════════════════════════════════════════════════════════════
set -e

SERVER_USER="${SERVER_USER:-admin}"
SERVER_IP="${SERVER_IP:?Error: define SERVER_IP (ej. export SERVER_IP=tu.ip.del.servidor)}"
SSH_KEY="${SSH_KEY:-${HOME}/.ssh/id_ed25519}"
REMOTE_DIR="/home/admin/sem-bus"

echo "🚀 Iniciando despliegue en servidor cloud ($SERVER_IP)..."

# 1. Crear directorios remotos e instalar rsync si falta
echo "📦 Verificando dependencias en el servidor..."
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=accept-new "$SERVER_USER@$SERVER_IP" << 'INIT'
set -e
sudo apt-get update -qq
if ! command -v rsync >/dev/null 2>&1; then
  sudo apt-get install -y -qq rsync
fi
mkdir -p /home/admin/sem-bus/backend /home/admin/sem-bus/admin-web /home/admin/sem-bus/driver-web
INIT

# 2. Sincronizar archivos de backend, web admin y tablet chofer
echo "📦 Transfiriendo archivos del backend, panel web y tablet chofer..."
rsync -avz -e "ssh -i $SSH_KEY" \
  --exclude '__pycache__' \
  --exclude '*.pyc' \
  --exclude '.DS_Store' \
  backend/ "$SERVER_USER@$SERVER_IP:$REMOTE_DIR/backend/"

rsync -avz -e "ssh -i $SSH_KEY" \
  --exclude '.DS_Store' \
  admin-web/ "$SERVER_USER@$SERVER_IP:$REMOTE_DIR/admin-web/"

rsync -avz -e "ssh -i $SSH_KEY" \
  --exclude '.DS_Store' \
  driver-web/ "$SERVER_USER@$SERVER_IP:$REMOTE_DIR/driver-web/"

scp -i "$SSH_KEY" .env.example "$SERVER_USER@$SERVER_IP:$REMOTE_DIR/.env.example"

# 3. Configurar servicios Systemd y Nginx en la nube
echo "⚙️ Configurando Systemd y Nginx en el servidor..."
ssh -i "$SSH_KEY" "$SERVER_USER@$SERVER_IP" << 'EOF'
set -e

# Crear archivo .env si no existe
if [ ! -f /home/admin/sem-bus/.env ]; then
  cp /home/admin/sem-bus/.env.example /home/admin/sem-bus/.env
  chmod 600 /home/admin/sem-bus/.env
fi

# Instalar Nginx si no está instalado
if ! command -v nginx >/dev/null 2>&1; then
  echo "📦 Instalando Nginx..."
  sudo apt-get update -qq
  sudo apt-get install -y -qq nginx
fi

# Configurar servicio systemd para el Backend
sudo tee /etc/systemd/system/busconectado.service > /dev/null << 'SERVICE'
[Unit]
Description=Bus Conectado Backend & Transit API
After=network.target

[Service]
Type=simple
User=admin
WorkingDirectory=/home/admin/sem-bus
ExecStart=/usr/bin/python3 /home/admin/sem-bus/backend/local_server.py
Restart=always
RestartSec=3
Environment=PORT=8000
Environment=HOST=0.0.0.0

[Install]
WantedBy=multi-user.target
SERVICE

# Permisos para Nginx
chmod 755 /home/admin /home/admin/sem-bus /home/admin/sem-bus/admin-web /home/admin/sem-bus/driver-web

# Configurar lista de IPs autorizadas si no existe
if [ ! -f /etc/nginx/admin_allowed_ips.conf ]; then
  sudo tee /etc/nginx/admin_allowed_ips.conf > /dev/null << 'IPS'
# IPs Autorizadas para el Panel Administrador
allow 127.0.0.1;
deny all;
IPS
fi

# Configurar Nginx Reverse Proxy (Puerto 80/443 público hacia Web Admin + Backend + WebSockets + Gzip)
sudo tee /etc/nginx/sites-available/busconectado > /dev/null << 'NGINX'
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;

    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_min_length 256;
    gzip_types text/plain text/css application/json application/javascript text/javascript application/xml image/svg+xml;

    root /home/admin/sem-bus/admin-web;
    index index.html;

    # Panel Web de Administración (Protegido con IP + Contraseña)
    location / {
        include /etc/nginx/admin_allowed_ips.conf;
        auth_basic "Acceso Restringido • Panel Administrador Bus Conectado";
        auth_basic_user_file /etc/nginx/.htpasswd;

        try_files $uri $uri/ /index.html;
        add_header Cache-Control "no-cache";
    }

    # Terminal / Tablet Cabina Conductor (Protegido con Contraseña)
    location /chofer {
        alias /home/admin/sem-bus/driver-web;
        index index.html;
        auth_basic "Acceso Chofer Cabina • Bus Conectado";
        auth_basic_user_file /etc/nginx/.htpasswd;

        try_files $uri $uri/ /chofer/index.html;
        add_header Cache-Control "no-cache";
    }

    # Canal WebSocket para Colaboración en Tiempo Real (Estilo Google Docs)
    location /ws {
        include /etc/nginx/admin_allowed_ips.conf;
        proxy_pass http://127.0.0.1:8000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
    }

    # API REST de paraderos, rutas y telemetría (Abierta para app de pasajeros de iOS)
    location /api/ {
        proxy_pass http://127.0.0.1:8000/api/;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location /health {
        proxy_pass http://127.0.0.1:8000/health;
    }
}
NGINX

# Habilitar sitio en Nginx
sudo rm -f /etc/nginx/sites-enabled/default
sudo ln -sf /etc/nginx/sites-available/busconectado /etc/nginx/sites-enabled/busconectado

# Recargar servicios
sudo systemctl daemon-reload
sudo systemctl enable busconectado
sudo systemctl restart busconectado
sudo nginx -t
sudo systemctl restart nginx

echo "✅ Estado del servicio Bus Conectado:"
sudo systemctl status busconectado --no-pager -n 5
EOF

echo "🎉 ¡Despliegue en la nube finalizado con éxito!"
