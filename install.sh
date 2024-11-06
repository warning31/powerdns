#!/bin/bash

set -euo pipefail

# Değişkenler - Kendi ortamınıza göre güncelleyin
PDNS_DB_ROOT_PASSWORD="pdns_root_password"
PDNS_DB_NAME="powerdns"
PDNS_DB_USER="powerdns"
PDNS_DB_PASSWORD="powerdns_password"
POWERADMIN_DB_USER="poweradmin"
POWERADMIN_DB_PASSWORD="poweradmin_password"
APACHE_SERVER_NAME="poweradmin.example.com"

# Güncelleme ve temel bağımlılıkların kurulumu
echo "Sistem güncelleniyor..."
sudo apt update && sudo apt upgrade -y

echo "Gerekli paketler kuruluyor..."
sudo apt install -y software-properties-common curl gnupg2 lsb-release

# MariaDB kurulumu
echo "MariaDB kuruluyor..."
sudo apt install -y mariadb-server mariadb-client

echo "MariaDB servisi başlatılıyor ve etkinleştiriliyor..."
sudo systemctl start mariadb
sudo systemctl enable mariadb

# MariaDB Güvenli Kurulum (otomatikleştirilmiş)
echo "MariaDB güvenli kurulumu yapılıyor..."
sudo mysql -e "UPDATE mysql.user SET Password = PASSWORD('${PDNS_DB_ROOT_PASSWORD}') WHERE User = 'root';"
sudo mysql -e "DELETE FROM mysql.user WHERE User='';"
sudo mysql -e "DROP DATABASE IF EXISTS test;"
sudo mysql -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';"
sudo mysql -e "FLUSH PRIVILEGES;"

# PowerDNS deposunun eklenmesi
echo "PowerDNS deposu ekleniyor..."
curl https://repo.powerdns.com/FD380FBB-pub.asc | sudo gpg --dearmor -o /usr/share/keyrings/powerdns-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/powerdns-archive-keyring.gpg] https://repo.powerdns.com/ubuntu $(lsb_release -sc) main" | sudo tee /etc/apt/sources.list.d/powerdns.list

sudo apt update

# PowerDNS kurulumu
echo "PowerDNS ve gerekli modüller kuruluyor..."
sudo apt install -y pdns-server pdns-backend-mysql

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

# Apache ve PHP kurulumu
echo "Apache ve PHP kuruluyor..."
sudo apt install -y apache2 libapache2-mod-php php php-mysql php-gd php-xml php-mbstring php-zip

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

# Apache sanal sunucusu yapılandırması
echo "Apache sanal sunucusu yapılandırılıyor..."
sudo tee /etc/apache2/sites-available/poweradmin.conf > /dev/null <<EOL
<VirtualHost *:80>
    ServerName ${APACHE_SERVER_NAME}
    DocumentRoot /var/www/html/poweradmin

    <Directory /var/www/html/poweradmin>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/poweradmin_error.log
    CustomLog \${APACHE_LOG_DIR}/poweradmin_access.log combined
</VirtualHost>
EOL

sudo a2ensite poweradmin.conf
sudo a2enmod rewrite
sudo systemctl reload apache2

# Dosya izinlerinin ayarlanması
echo "Dosya izinleri ayarlanıyor..."
sudo chown -R www-data:www-data /var/www/html/poweradmin

# Firewall ayarları (isteğe bağlı)
echo "Firewall ayarları yapılıyor..."
sudo ufw allow 80/tcp
sudo ufw allow 8081/tcp
sudo ufw reload

echo "Kurulum tamamlandı! PowerAdmin'ı tarayıcınızda ${APACHE_SERVER_NAME} adresinden erişebilirsiniz."
