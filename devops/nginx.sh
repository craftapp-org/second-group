set -e

# Vars
PROJECT_NAME=$1
FRONTEND_PORT=$2
BACKEND_PORT=$3
DOMAIN=$4  # optional, default to EC2 IP
PROJECT_DIR="/home/ubuntu/app/$PROJECT_NAME"
SSL_DIR="/etc/nginx/ssl/$PROJECT_NAME"
NGINX_CONF="/etc/nginx/sites-enabled/$PROJECT_NAME.conf"

# Check
if [[ -z "$PROJECT_NAME" || -z "$FRONTEND_PORT" || -z "$BACKEND_PORT" ]]; then
  echo "Usage: ./auto-deploy.sh <project-name> <frontend-port> <backend-port> [domain]"
  exit 1
fi

DOMAIN=${DOMAIN:-$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)}

echo "Deploying $PROJECT_NAME on ports FE:$FRONTEND_PORT, BE:$BACKEND_PORT, domain: $DOMAIN"

# 1. Create directories
sudo mkdir -p "$PROJECT_DIR"
sudo mkdir -p "$SSL_DIR"

# 2. Generate SSL
echo "Generating SSL certificate..."
if ! sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout "$SSL_DIR/privkey.pem" \
  -out "$SSL_DIR/fullchain.pem" \
  -subj "/CN=$DOMAIN" \
  -addext "subjectAltName=DNS:$DOMAIN"; then
  echo "⚠️ Failed to generate SSL cert. Skipping..."
fi

sudo chmod 600 "$SSL_DIR"/* || true

# 3. Generate NGINX config
echo "Writing nginx config..."
sudo tee "$NGINX_CONF" > /dev/null <<EOF
server {
    listen 443 ssl;
    server_name $DOMAIN;

    ssl_certificate $SSL_DIR/fullchain.pem;
    ssl_certificate_key $SSL_DIR/privkey.pem;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers 'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256';
    ssl_prefer_server_ciphers on;

    location /api/ {
        proxy_pass http://localhost:$BACKEND_PORT/;
        proxy_set_header Host \$host;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }

    location / {
        proxy_pass http://localhost:$FRONTEND_PORT/;
        proxy_set_header Host \$host;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}

server {
    listen 80;
    server_name $DOMAIN;
    return 301 https://\$host\$request_uri;
}
EOF

# 4. Reload NGINX
echo "Reloading nginx..."
sudo nginx -t && sudo systemctl reload nginx

# 5. Allow firewall
echo "Opening firewall..."
sudo ufw allow 443/tcp
sudo ufw allow 80/tcp

echo "✅ $PROJECT_NAME deployed successfully with HTTPS!"