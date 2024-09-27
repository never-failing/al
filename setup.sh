#!/bin/sh

# Обновление системы
apk update
apk upgrade

# Установка необходимых пакетов
apk add alpine-sdk autoconf libtool cmake make gcc g++ curl wget bash tar openssl-dev libxml2-dev bzip2-dev oniguruma-dev libressl-dev pcre-dev zlib-dev

# Разметка и форматирование диска (предположим, диск - /dev/sda)
DISK='/dev/sda'

echo "Начало разметки диска $DISK"
# Удалим все существующие разделы
sfdisk --delete $DISK
# Создание нового раздела на весь диск
echo "type=83" | sfdisk $DISK
# Форматирование в ext4
mkfs.ext4 ${DISK}1
# Монтирование диска
mount ${DISK}1 /mnt

# Перемещаем корневую файловую систему на новый раздел
cp -ax / /mnt
mount --bind /dev /mnt/dev
mount --bind /proc /mnt/proc
mount --bind /sys /mnt/sys
chroot /mnt /bin/bash

# Установка и сборка Nginx
echo "Установка Nginx 1.27.1"
wget https://nginx.org/download/nginx-1.27.1.tar.gz
tar -xvf nginx-1.27.1.tar.gz
cd nginx-1.27.1
./configure --sbin-path=/usr/sbin/nginx --conf-path=/etc/nginx/nginx.conf --pid-path=/var/run/nginx.pid --with-http_ssl_module --with-http_v2_module --with-http_gzip_static_module
make && make install

# Создание службы для Nginx
cat > /etc/init.d/nginx <<EOL
#!/sbin/openrc-run

name="Nginx"
description="Nginx Web Server"

command="/usr/sbin/nginx"
command_args="-g 'daemon off;'"
pidfile="/var/run/nginx.pid"

depend() {
  use net
  after firewall
}
EOL
chmod +x /etc/init.d/nginx
rc-update add nginx

# Установка и сборка PHP 8.3
echo "Установка PHP 8.3"
wget https://www.php.net/distributions/php-8.3.12.tar.gz
tar -xvf php-8.3.12.tar.gz
cd php-8.3.12
./configure --prefix=/usr/local/php --with-openssl --with-zlib --enable-bcmath --enable-mbstring --enable-fpm --with-fpm-systemd --enable-pdo --with-mysqli
make && make install

# Создание службы для PHP-FPM
cat > /etc/init.d/php-fpm <<EOL
#!/sbin/openrc-run

name="PHP-FPM"
description="PHP FastCGI Process Manager"

command="/usr/local/php/sbin/php-fpm"
pidfile="/usr/local/php/var/run/php-fpm.pid"

depend() {
  use net
  after firewall
}
EOL
chmod +x /etc/init.d/php-fpm
rc-update add php-fpm

# Установка и настройка MariaDB 11.4.3
echo "Установка MariaDB 11.4.3"
wget https://downloads.mariadb.com/MariaDB/mariadb-11.4.3/linux-systemd-x86_64/mariadb-11.4.3-linux-systemd-x86_64.tar.gz
tar -xvf mariadb-11.4.3-linux-systemd-x86_64.tar.gz -C /usr/local/
ln -s /usr/local/mariadb-11.4.3-linux-systemd-x86_64 /usr/local/mariadb

# Инициализация MariaDB
/usr/local/mariadb/scripts/mysql_install_db --user=mysql --datadir=/var/lib/mysql

# Генерация root-пароля для MariaDB
MYSQL_ROOT_PASSWORD=$(openssl rand -base64 16)
echo "Root пароль для MariaDB: $MYSQL_ROOT_PASSWORD"

# Создание конфигурационного файла для MariaDB
cat > /etc/my.cnf <<EOL
[mysqld]
datadir=/var/lib/mysql
socket=/var/lib/mysql/mysql.sock
log-error=/var/log/mysqld.log
pid-file=/var/run/mysqld/mysqld.pid

[client-server]
!includedir /etc/my.cnf.d
EOL

# Запуск MariaDB
/usr/local/mariadb/bin/mysqld_safe --datadir=/var/lib/mysql &

# Установка root-пароля
/usr/local/mariadb/bin/mysqladmin -u root password "$MYSQL_ROOT_PASSWORD"

# Добавляем MariaDB в автозагрузку
cat > /etc/init.d/mariadb <<EOL
#!/sbin/openrc-run

name="MariaDB"
description="MariaDB Database Server"

command="/usr/local/mariadb/bin/mysqld_safe"
pidfile="/var/run/mysqld/mysqld.pid"

depend() {
  use net
  after firewall
}
EOL
chmod +x /etc/init.d/mariadb
rc-update add mariadb

# Запуск всех служб
rc-service nginx start
rc-service php-fpm start
rc-service mariadb start

echo "Установка завершена! Root пароль для MariaDB: $MYSQL_ROOT_PASSWORD"
