#!/bin/bash

# Domain adı ve IP adresi kontrolü
if [ -z "$1" ] || [ -z "$2" ]; then
  echo "Lütfen eklemek istediğiniz domain adı ve IP adresini girin."
  echo "Kullanım: $0 example.com 192.0.2.1"
  exit 1
fi

DOMAIN_NAME=$1
IP_ADDRESS=$2
BIND_DIR="/etc/bind"
ZONE_FILE="$BIND_DIR/db.$DOMAIN_NAME"
NAMED_CONF_LOCAL="$BIND_DIR/named.conf.local"

# Zone dosyası oluşturuluyor
echo "$DOMAIN_NAME için zone dosyası $IP_ADDRESS IP adresiyle oluşturuluyor..."

sudo bash -c "cat > $ZONE_FILE <<EOF
\$TTL    604800
@       IN      SOA     ns1.$DOMAIN_NAME. admin.$DOMAIN_NAME. (
                              2         ; Serial
                         604800         ; Refresh
                          86400         ; Retry
                        2419200         ; Expire
                         604800 )       ; Negative Cache TTL

; Name Serverlar
@       IN      NS      ns1.$DOMAIN_NAME.
@       IN      NS      ns2.$DOMAIN_NAME.

; A kaydı
@       IN      A       $IP_ADDRESS

; Name Server IP adresleri
ns1     IN      A       $IP_ADDRESS
ns2     IN      A       $IP_ADDRESS
EOF"

# named.conf.local dosyasına yeni domain ekleniyor
echo "named.conf.local dosyasına $DOMAIN_NAME alan adı ekleniyor..."

sudo bash -c "echo 'zone \"$DOMAIN_NAME\" {
    type master;
    file \"$ZONE_FILE\";
};' >> $NAMED_CONF_LOCAL"

# BIND servisini yeniden başlat
echo "BIND servisi yeniden başlatılıyor..."
sudo systemctl restart bind9

echo "$DOMAIN_NAME başarıyla $IP_ADDRESS IP adresiyle eklendi ve BIND servisi yeniden başlatıldı."
