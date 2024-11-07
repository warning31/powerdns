#!/bin/bash

# BIND kurulumu ve yapılandırması
echo "BIND kurulumu başlıyor..."

# Sistem paketlerini güncelle
sudo apt update && sudo apt upgrade -y

# BIND paketi kur
sudo apt install -y bind9 bind9utils bind9-doc

# BIND yapılandırma dizinleri ve dosyaları
BIND_DIR="/etc/bind"
NAMED_CONF_OPTIONS="$BIND_DIR/named.conf.options"

# named.conf.options yapılandırması
echo "named.conf.options dosyası oluşturuluyor..."
sudo bash -c "cat > $NAMED_CONF_OPTIONS <<EOF
options {
    directory "/var/cache/bind";

    // DNS sunucusunu external network olarak yapılandırma
    recursion no; // Sadece tanımlı alan adları için yanıt verir
    allow-query { any; };

    // Forwarder ayarları (örneğin Google DNS)
    forwarders {
        8.8.8.8;
        8.8.4.4;
        1.1.1.1;
    };

    // DNS'nin çalışacağı IP
    listen-on { any; };
    listen-on-v6 { any; };

    dnssec-validation auto;
};
EOF"

# BIND servisini yeniden başlat
echo "BIND servisi yeniden başlatılıyor..."
sudo systemctl restart bind9

# BIND servisini otomatik başlatma
sudo systemctl enable bind9

echo "BIND kurulumu ve yapılandırması tamamlandı."
