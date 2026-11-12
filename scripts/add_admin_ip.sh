#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════
# BUS CONECTADO • GESTIONAR IPS AUTORIZADAS PARA EL PANEL ADMINISTRADOR
# Uso: 
#   ./scripts/add_admin_ip.sh <IP_DEL_COMPAÑERO>
#   ./scripts/add_admin_ip.sh --list
# ═══════════════════════════════════════════════════════════════════════
set -e

SERVER_USER="admin"
SERVER_IP="34.44.71.179"
SSH_KEY="${HOME}/.ssh/id_buses"
IPS_FILE="/etc/nginx/admin_allowed_ips.conf"

TARGET="$1"

if [ -z "$TARGET" ]; then
  echo "❌ Error: Debes especificar la dirección IP o '--list'."
  echo "👉 Uso: $0 <IP>"
  echo "   Ejemplo: $0 190.235.45.12"
  echo "   Listar autorizadas: $0 --list"
  exit 1
fi

# Listar IPs autorizadas
if [ "$TARGET" == "--list" ] || [ "$TARGET" == "-l" ]; then
  echo "📋 Consultando IPs autorizadas en el servidor cloud ($SERVER_IP)..."
  ssh -i "$SSH_KEY" "$SERVER_USER@$SERVER_IP" "cat $IPS_FILE"
  exit 0
fi

# Validar formato IPv4 básico
if ! [[ "$TARGET" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
  echo "❌ Error: '$TARGET' no parece una dirección IPv4 válida (ejemplo: 190.235.45.12)."
  exit 1
fi

echo "🔐 Autorizando IP: $TARGET en el servidor cloud ($SERVER_IP)..."

ssh -i "$SSH_KEY" "$SERVER_USER@$SERVER_IP" bash -s << REMOTE_EOF
set -e
if [ ! -f "$IPS_FILE" ]; then
  sudo tee "$IPS_FILE" > /dev/null << 'EOF'
allow 127.0.0.1;
allow 38.250.158.151; # Aron
deny all;
EOF
fi

if grep -q "allow $TARGET;" "$IPS_FILE"; then
  echo "ℹ️ La IP $TARGET ya estaba en la lista de permitidas."
else
  # Insertar allow antes de 'deny all;'
  sudo sed -i "/deny all;/i allow $TARGET;" "$IPS_FILE"
  echo "✅ Regla 'allow $TARGET;' agregada a $IPS_FILE."
fi

# Validar sintaxis y recargar Nginx
sudo nginx -t
sudo systemctl reload nginx
echo "🔄 Nginx recargado con éxito."
REMOTE_EOF

echo ""
echo "🎉 ¡IP $TARGET autorizada exitosamente!"
echo "📋 Lista actual en el servidor:"
ssh -i "$SSH_KEY" "$SERVER_USER@$SERVER_IP" "cat $IPS_FILE"
echo ""
echo "🔗 Pasa estos datos a tu compañero:"
echo "   • URL:      http://$SERVER_IP"
echo "   • Usuario:  admin2"
echo "   • Clave:    TacnaAdmin2_2026!"
