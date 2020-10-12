#!/bin/bash
#Keepwalking86
#Setup LEMP - Linux Enginx MongoDB/MariaDB PHP7 on CentOS 7

#Defining variables
nginx_ver=nginx-1.14.1
mongodb_version=4.0
mariadb_version=10.4

#Text color variables
txtred=$(tput setaf 1)    # Red
txtgreen=$(tput setaf 2)  # Green
txtyellow=$(tput setaf 3) # Yellow
txtreset=$(tput sgr0)     # Text reset

###Disable SELinux Temporarily
setenforce 0
###Disable SELinux Permanently after restart OS
sed -i 's/^SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config

####INSTALLING NGINX
echo "${txtyellow}***Check OS and install essential package to compile nginx***${txtreset}"
sleep 2
sudo yum -y install make gcc gcc-c++ pcre-devel zlib-devel openssl-devel curl wget

echo "Create nginx user"
useradd -d /dev/null -c "nginx user" -s /sbin/nologin nginx

# Download & unpack latest stable nginx & nginx-rtmp version
echo "${txtyellow}***Download and unpack latest stable nginx***${txtreset}"
sleep 3
cd /opt
wget http://nginx.org/download/${nginx_ver}.tar.gz
sudo tar xzf ${nginx_ver}.tar.gz
mv ${nginx_ver} nginx
cd nginx
echo "Build nginx"
./configure --prefix=/etc/nginx \
--pid-path=/var/run/nginx.pid \
--conf-path=/etc/nginx/nginx.conf \
--sbin-path=/usr/sbin/nginx \
--user=nginx \
--group=nginx \
--with-pcre --with-file-aio \
--with-http_realip_module \
--with-http_gzip_static_module \
--with-http_ssl_module \
--with-http_gzip_static_module \
--with-http_stub_status_module
make
make install

# Run Nginx with systemd
#Create nginx.service file
cat >/lib/systemd/system/nginx.service<<EOF
[Unit]
Description=nginx - The nginx HTTP and reverse proxy server
Documentation=http://nginx.org/en/docs/
After=network-online.target remote-fs.target nss-lookup.target
Wants=network-online.target
[Service]
Type=forking
ExecStartPre=/usr/bin/rm -f /var/run/nginx.pid
ExecStartPre=/usr/sbin/nginx -t
ExecStart=/usr/sbin/nginx
ExecReload=/bin/kill -s HUP \$MAINPID
KillSignal=SIGQUIT
TimeoutStopSec=5
KillMode=process
PrivateTmp=true
[Install]
WantedBy=multi-user.target
EOF

#Start Nginx service
systemctl enable nginx.service
systemctl start nginx.service

########SETUP NGINX###########
###Create many virtualhosts
[ ! -d /etc/nginx/sites-available ] && mkdir /etc/nginx/sites-available
[ ! -d /etc/nginx/sites-enabled ] && mkdir /etc/nginx/sites-enabled
[ ! -d /var/log/nginx ] && mkdir /var/log/nginx

#Nginx configuration file
cat >/etc/nginx/nginx.conf<<EOF
user nginx;
pid /var/run/nginx.pid;
worker_processes auto;
worker_rlimit_nofile 65535;

events {
	multi_accept on;
	worker_connections 65535;
}

http {
	charset utf-8;
	sendfile on;
	tcp_nopush on;
	tcp_nodelay on;
	server_tokens off;
	log_not_found off;
	types_hash_max_size 2048;
	client_max_body_size 16M;

	# MIME
	include mime.types;
	default_type application/octet-stream;

	# logging
	access_log /var/log/nginx/access.log;
	error_log /var/log/nginx/error.log warn;

	# load configs
	include /etc/nginx/conf.d/*.conf;
	include /etc/nginx/sites-enabled/*;
}
EOF

#Nginx general settings about security, cached, compress
cat >/etc/nginx/general.conf<<EOF
# security headers
add_header X-Frame-Options "SAMEORIGIN" always;
add_header X-XSS-Protection "1; mode=block" always;
add_header X-Content-Type-Options "nosniff" always;
add_header Referrer-Policy "same-origin" always;
add_header Content-Security-Policy "default-src * data: 'unsafe-eval' 'unsafe-inline'" always;

# . files
location ~ /\.(?!well-known) {
	deny all;
}

# assets, media
location ~* \.(?:css(\.map)?|js(\.map)?|jpe?g|png|gif|ico|cur|heic|webp|tiff?|mp3|m4a|aac|ogg|midi?|wav|mp4|mov|webm|mpe?g|avi|ogv|flv|wmv)$ {
	expires 30d;
	access_log off;
}

# svg, fonts
location ~* \.(?:svgz?|ttf|ttc|otf|eot|woff2?)$ {
	add_header Access-Control-Allow-Origin "*";
	expires 30d;
	access_log off;
}

#enable gzip compression to reduce the data that sent over network
gzip on;
gzip_vary on;
gzip_proxied any;
gzip_comp_level 6; #choose level 2-3 to redue CPU load
gzip_types
    text/plain
    text/css
    text/js
    text/xml
    text/javascript
    application/javascript
    application/x-javascript
    application/json
    application/xml
    application/rss+xml
    application/atom+xml
    image/svg+xml;
EOF

###########INSTALLING PHP7######################
echo "${txtyellow}***Installing repo epel, webstatic***${txtreset}"
sleep 2
yum -y install epel-release
rpm -Uvh https://mirror.webtatic.com/yum/el7/webtatic-release.rpm

echo "${txtyellow}***Installing PHP7***${txtreset}"
sleep 3
yum install -y php72w php72w-common php72w-gd php72w-phar php72w-xml php72w-cli php72w-mbstring php72w-tokenizer \
php72w-openssl php72w-pdo php72w-devel php72w-opcache php72w-fpm

echo "Starting php-fpm"
systemctl start php-fpm
systemctl enable php-fpm

echo "${txtyellow}***Installing PHP Composer***${txtreset}"
curl -sS https://getcomposer.org/installer |php -- --install-dir=/usr/bin --filename=composer


##########FUNCTION MONGODB#####################
mongodb () {
#Create mongodb repo
cat >/etc/yum.repos.d/mongodb.repo<<EOF
[mongodb-org-${mongodb_version}]
name=MongoDB Repository
baseurl=https://repo.mongodb.org/yum/redhat/\$releasever/mongodb-org/${mongodb_version}/x86_64/
gpgcheck=1
enabled=1
gpgkey=https://www.mongodb.org/static/pgp/server-${mongodb_version}.asc
EOF
    yum install mongodb-org -y
    #Start MongoDB
    systemctl start mongod
    systemctl enable mongod
}

###############FUNCTION MARIADB#####################
mariadb () {
    wget https://downloads.mariadb.com/MariaDB/mariadb_repo_setup
    chmod +x mariadb_repo_setup
    ./mariadb_repo_setup --mariadb-server-version="mariadb-${mariadb_version}"
    yum -y install MariaDB-server
    systemctl start mariadb
    systemctl enable mariadb
}

###########INSTALLING DATABASE SERVER#################
#Declare choice variable and assign value is 4
echo "${txtyellow}***Installing DB***${txtreset}"
choice=4
#print stdout
 echo "1. MongoDB"
 echo "2. MariaDB"
 echo "3. Don't install DB"
 echo -n "Please choice one value [1 or 2 or 3]: "
#loop while
while [ $choice -eq 4 ]; do
read choice
if [ $choice == 1 ]; then
    echo "${txtyellow}***Preparing to install MongoDB3***${txtreset}"
		sleep 3
		mongodb
    yum install php72w-pear php72w-pecl-mongodb -y
else
  if [ $choice -eq 2 ]; then
      echo "${txtyellow}***Preparing to install MariaDB***${txtreset}"
			sleep 3
			mariadb
      yum install php72w-mysql -y
  else
			if [ $choice -eq 3 ]; then
				echo "${txtyellow}***You don't install DB***${txtreset}"
			else
		        echo -n "${txtyellow}***Please choice one value [1 or 2 or 3]***${txtreset}"
                choice=4 #repeat if don't choice 1|2|3
			fi
  fi
fi
done