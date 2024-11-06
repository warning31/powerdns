#!/bin/bash

set -euo pipefail

# Değişkenler - Kendi ortamınıza göre güncelleyin
PDNS_DB_ROOT_PASSWORD="123456"
PDNS_DB_NAME="powerdns"
PDNS_DB_USER="powerdns"
PDNS_DB_PASSWORD="123456"
POWERADMIN_DB_USER="poweradmin"
POWERADMIN_DB_PASSWORD="123456"
NGINX_SERVER_NAME="deneme.avciweb.site"
EMAIL="your-email@example.com"  # Let's Encrypt için e-posta adresiniz

# Sistem güncelleme ve temel bağımlılıkların kurulumu
echo "Sistem güncelleniyor..."
sudo apt update && sudo apt upgrade -y

echo "Gerekli paketler kuruluyor..."
sudo apt install -y software-properties-common curl gnupg2 lsb-release git

# MariaDB kurulumu
echo "MariaDB kuruluyor..."
sudo apt install -y mariadb-server mariadb-client

echo "MariaDB servisi başlatılıyor ve etkinleştiriliyor..."
sudo systemctl start mariadb
sudo systemctl enable mariadb

# MariaDB Güvenli Kurulum (otomatikleştirilmiş)
echo "MariaDB güvenli kurulumu yapılıyor..."
sudo mysql <<EOF
ALTER USER 'root'@'localhost' IDENTIFIED BY '${PDNS_DB_ROOT_PASSWORD}';
DROP USER IF EXISTS ''@'localhost';
DROP USER IF EXISTS 'test'@'localhost';
DROP DATABASE IF EXISTS test;
FLUSH PRIVILEGES;
EOF

# PowerDNS deposunun eklenmesi ve yapılandırılması
echo "PowerDNS deposu ekleniyor..."

# Anahtarların ve dizinlerin oluşturulması
sudo install -d /etc/apt/keyrings

# PowerDNS Auth Master anahtarının indirilmesi
curl https://repo.powerdns.com/CBC8B383-pub.asc | sudo tee /etc/apt/keyrings/auth-master-pub.asc > /dev/null

# PowerDNS deposu eklenmesi
sudo tee /etc/apt/sources.list.d/pdns.list > /dev/null <<EOL
deb [signed-by=/etc/apt/keyrings/auth-master-pub.asc] http://repo.powerdns.com/ubuntu jammy-auth-master main
EOL

# Paket önceliklerinin ayarlanması
sudo tee /etc/apt/preferences.d/auth-master > /dev/null <<EOL
Package: auth*
Pin: origin repo.powerdns.com
Pin-Priority: 600
EOL

# Paket listelerinin güncellenmesi
sudo apt-get update

# PowerDNS kurulumu
echo "PowerDNS kuruluyor..."
sudo apt-get install -y pdns-server

# PowerDNS backend (MySQL) kurulumu
echo "PowerDNS MySQL backend kuruluyor..."
sudo apt-get install -y pdns-backend-mysql

# PowerDNS veritabanının oluşturulması
echo "PowerDNS veritabanı oluşturuluyor..."
sudo mysql -u root -p"${PDNS_DB_ROOT_PASSWORD}" -e "CREATE DATABASE ${PDNS_DB_NAME} CHARACTER SET utf8 COLLATE utf8_general_ci;"
sudo mysql -u root -p"${PDNS_DB_ROOT_PASSWORD}" -e "CREATE USER '${PDNS_DB_USER}'@'localhost' IDENTIFIED BY '${PDNS_DB_PASSWORD}';"
sudo mysql -u root -p"${PDNS_DB_ROOT_PASSWORD}" -e "GRANT ALL PRIVILEGES ON ${PDNS_DB_NAME}.* TO '${PDNS_DB_USER}'@'localhost';"
sudo mysql -u root -p"${PDNS_DB_ROOT_PASSWORD}" -e "FLUSH PRIVILEGES;"

# PowerDNS şemasının yüklenmesi
echo "PowerDNS şeması yükleniyor..."
sudo mysql -u root -p"${PDNS_DB_ROOT_PASSWORD}" ${PDNS_DB_NAME} < /usr/share/doc/pdns-backend-mysql/schema.mysql.sql

# PowerDNS konfigürasyonu
echo "PowerDNS konfigürasyonu yapılıyor..."
sudo tee /etc/powerdns/pdns.conf > /dev/null <<EOL
launch=gmysql
gmysql-host=127.0.0.1
gmysql-user=${PDNS_DB_USER}
gmysql-password=${PDNS_DB_PASSWORD}
gmysql-dbname=${PDNS_DB_NAME}
api=yes
api-key=your_api_key_here
webserver=yes
webserver-address=0.0.0.0
webserver-port=8081
EOL

# PowerDNS servisini yeniden başlatma
echo "PowerDNS servisi yeniden başlatılıyor..."
sudo systemctl restart pdns
sudo systemctl enable pdns

# Nginx ve PHP kurulumu
echo "Nginx ve PHP kuruluyor..."
sudo apt install -y nginx php-fpm php-mysql php-gd php-xml php-mbstring php-zip

# PowerAdmin kurulumu
echo "PowerAdmin kuruluyor..."
cd /var/www/html
sudo git clone https://github.com/ngoduykhanh/PowerDNS-Admin.git poweradmin
cd poweradmin
sudo cp config.py.example config.py

# PowerAdmin konfigürasyonu
echo "PowerAdmin konfigürasyonu yapılıyor..."
sudo sed -i "s/SECRET_KEY = .*/SECRET_KEY = '$(openssl rand -base64 32)'/" config.py
sudo sed -i "s/'user': .*/'user': '${PDNS_DB_USER}',/" config.py
sudo sed -i "s/'password': .*/'password': '${PDNS_DB_PASSWORD}',/" config.py
sudo sed -i "s/'database': .*/'database': '${PDNS_DB_NAME}',/" config.py
sudo sed -i "s/'host': .*/'host': '127.0.0.1',/" config.py

# Nginx sanal sunucusu yapılandırması
echo "Nginx sanal sunucusu yapılandırılıyor..."
PHP_VERSION=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')
sudo tee /etc/nginx/sites-available/poweradmin > /dev/null <<EOL
server {
    listen 80;
    server_name ${NGINX_SERVER_NAME};

    root /var/www/html/poweradmin;
    index index.php index.html index.htm;

    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php${PHP_VERSION}-fpm.sock;
    }

    location ~ /\.ht {
        deny all;
    }

    error_log /var/log/nginx/poweradmin_error.log;
    access_log /var/log/nginx/poweradmin_access.log;
}
EOL

# Nginx yapılandırmasını etkinleştirme
sudo ln -s /etc/nginx/sites-available/poweradmin /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx

# Dosya izinlerinin ayarlanması
echo "Dosya izinleri ayarlanıyor..."
sudo chown -R www-data:www-data /var/www/html/poweradmin
sudo find /var/www/html/poweradmin -type d -exec chmod 755 {} \;
sudo find /var/www/html/poweradmin -type f -exec chmod 644 {} \;

# Let's Encrypt ile HTTPS kurulumu
echo "Let's Encrypt kurulumu yapılıyor..."
sudo apt install -y certbot python3-certbot-nginx

echo "SSL sertifikası alınıyor..."
sudo certbot --nginx -d ${NGINX_SERVER_NAME} --non-interactive --agree-tos -m ${EMAIL} --redirect

# Sertifika yenileme testi
sudo certbot renew --dry-run

# Firewall ayarları (isteğe bağlı)
echo "Firewall ayarları yapılıyor..."
sudo ufw allow 'Nginx Full'
sudo ufw allow 8081/tcp
sudo ufw reload

# Fail2Ban kurulumu
echo "Fail2Ban kuruluyor..."
sudo apt install -y fail2ban
sudo systemctl enable fail2ban
sudo systemctl start fail2ban

echo "Kurulum tamamlandı! PowerAdmin'ı tarayıcınızda https://${NGINX_SERVER_NAME} adresinden erişebilirsiniz."
