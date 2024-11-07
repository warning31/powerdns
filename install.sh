#!/bin/bash

# BIND9 Kurulum ve Yapılandırma Betiği
# Ubuntu 22.04 ve 24.04 için uygundur.

# Betiğin root olarak çalıştırıldığından emin olun
if [ "$EUID" -ne 0 ]; then
  echo "Lütfen bu betiği root olarak çalıştırın (sudo kullanarak)."
  exit 1
fi

# Değişkenler
DOMAIN="avciweb.site"
ZONE_FILE_PATH="/etc/bind/zones"
IP_ADDRESS="91.107.237.246"
REVERSE_IP_NETWORK="237.107.91"
EMAIL="admin.avciweb.site"  # Yönetici e-posta adresini buraya girin

# Sistem güncelleniyor
echo "Sistem güncelleniyor..."
apt update && apt upgrade -y

# BIND9 ve gerekli paketlerin kurulumu
echo "BIND9 kuruluyor..."
apt install bind9 bind9utils bind9-doc dnsutils -y

# Zone dizini oluşturuluyor
echo "Zone dizini oluşturuluyor..."
mkdir -p $ZONE_FILE_PATH

# named.conf.local dosyasını yedekleme
echo "named.conf.local yedekleniyor..."
cp /etc/bind/named.conf.local /etc/bind/named.conf.local.bak

# named.conf.local dosyasına zone eklemeleri yapılıyor
echo "Zone eklemeleri yapılıyor..."
cat <<EOL >> /etc/bind/named.conf.local

// Forward Zone
zone "$DOMAIN" {
    type master;
    file "$ZONE_FILE_PATH/db.$DOMAIN";
};

// Reverse Zone
zone "$REVERSE_IP_NETWORK.in-addr.arpa" {
    type master;
    file "$ZONE_FILE_PATH/db.$REVERSE_IP_NETWORK";
};
EOL

# Forward zone dosyasının oluşturulması
echo "Forward zone dosyası oluşturuluyor..."
cat <<EOL > $ZONE_FILE_PATH/db.$DOMAIN
\$TTL    604800
@       IN      SOA     ns1.$DOMAIN. $EMAIL. (
                              2         ; Serial
                         604800         ; Refresh
                          86400         ; Retry
                        2419200         ; Expire
                         604800 )       ; Negative Cache TTL
;
@       IN      NS      ns1.$DOMAIN.
@       IN      NS      ns2.$DOMAIN.
ns1     IN      A       $IP_ADDRESS
ns2     IN      A       $IP_ADDRESS
@       IN      A       $IP_ADDRESS
www     IN      A       $IP_ADDRESS
EOL

# Reverse zone dosyasının oluşturulması
echo "Reverse zone dosyası oluşturuluyor..."
cat <<EOL > $ZONE_FILE_PATH/db.$REVERSE_IP_NETWORK
\$TTL    604800
@       IN      SOA     ns1.$DOMAIN. $EMAIL. (
                              2         ; Serial
                         604800         ; Refresh
                          86400         ; Retry
                        2419200         ; Expire
                         604800 )       ; Negative Cache TTL
;
@       IN      NS      ns1.$DOMAIN.
246     IN      PTR     $DOMAIN.
EOL

# DNS yapılandırmasının kontrol edilmesi
echo "DNS yapılandırması kontrol ediliyor..."
named-checkconf
if [ $? -ne 0 ]; then
    echo "named.conf yapılandırma dosyası hatalı!"
    exit 1
fi

# Zone dosyalarının kontrol edilmesi
echo "Zone dosyaları kontrol ediliyor..."
named-checkzone $DOMAIN $ZONE_FILE_PATH/db.$DOMAIN
if [ $? -ne 0 ]; then
    echo "Forward zone dosyası hatalı!"
    exit 1
fi

named-checkzone $REVERSE_IP_NETWORK.in-addr.arpa $ZONE_FILE_PATH/db.$REVERSE_IP_NETWORK
if [ $? -ne 0 ]; then
    echo "Reverse zone dosyası hatalı!"
    exit 1
fi

# Firewall ayarlarının yapılması (UFW kullanılıyorsa)
echo "Firewall ayarları yapılıyor..."
ufw allow Bind9
ufw allow 53/tcp
ufw allow 53/udp

# BIND9 servisini yeniden başlatma
echo "BIND9 servisi yeniden başlatılıyor..."
systemctl restart bind9

# BIND9 servisi durumunun kontrolü
echo "BIND9 servisi durumu:"
systemctl status bind9 | grep Active

echo "BIND9 kurulumu ve yapılandırması tamamlandı."
