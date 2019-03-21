#!/bin/bash
#Keepwalking86
#Setup LEMP - Linux Enginx MongoDB/MariaDB PHP7 on CentOS 7

#Defining variables
nginx_ver=nginx-1.14.1

#Declare choice variable and assign value is 4
choice=4
#print stdout
 echo "1. MongoDB-3x"
 echo "2. MariaDB"
 echo "3. Don't install DB"
 echo -n "Please choice one value [1 or 2 or 3]: "
#loop while
while [ $choice -eq 4 ]; do
read choice
if [ $choice == 1 ]; then
        echo "Preparing to install stack with Enginx MongoDB3 PHP7"
	sleep 3
else
        if [ $choice -eq 2 ]; then
                echo "Preparing to install stack with Enginx MariaDB PHP7"
		sleep 3
        else
		if [ $choice -eq 3 ]; then
			echo "You don't install DB"
		else
		        echo -n "Please choice one value [1 or 2 or 3]"
                	choice=4 #repeat if don't choice 1|2|3
		fi
        fi
fi
done

####INSTALLING NGINX
echo "Check OS and install essential package to compile nginx"
sleep 2
sudo yum -y install make gcc gcc-c++ pcre-devel zlib-devel openssl-devel

echo "Create nginx user"
useradd -d /dev/null -c "nginx user" -s /sbin/nologin nginx

# Download & unpack latest stable nginx & nginx-rtmp version
echo "Download and unpack latest stable nginx"
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
Description=nginx - high performance web server
Documentation=http://nginx.org/en/docs/
After=network-online.target remote-fs.target nss-lookup.target
Wants=network-online.target
[Service]
Type=forking
ExecStartPre=/usr/sbin/nginx -t -c /etc/nginx/nginx.conf
ExecStart=/usr/sbin/nginx -c /etc/nginx/nginx.conf
ExecReload=/bin/kill -s HUP $MAINPID
ExecStop=/bin/kill -s QUIT $MAINPID
[Install]
WantedBy=multi-user.target
EOF

#Start Nginx service
systemctl enable nginx.service
systemctl start nginx.service

###########INSTALLING PHP7######################
echo "Installing repo epel, webstatic"
sleep 2
yum -y install epel-release
rpm -Uvh https://mirror.webtatic.com/yum/el7/webtatic-release.rpm

echo "Installing PHP7"
sleep 3
yum install -y php72w php72w-common php72w-gd php72w-phar \
php72w-xml php72w-cli php72w-mbstring php72w-tokenizer \
php72w-openssl php72w-pdo php72w-devel php72w-opcache \
php72w-pear php72w-fpm php72w-pecl-mongodb php71w-fpm

echo "Starting php-fpm"
systemctl start php-fpm
systemctl enable php-fpm

echo "Installing PHP Composer"
curl -sS https://getcomposer.org/installer |php -- --install-dir=/usr/bin --filename=composer


##########FUNCTION MONGODB#####################
mongodb () {
#Create mongodb repo
cat >/etc/yum.repos.d/mongodb.repo<<EOF
[mongodb-org-3.6]
name=MongoDB Repository
baseurl=https://repo.mongodb.org/yum/redhat/\$releasever/mongodb-org/3.6/x86_64/
gpgcheck=1
enabled=1
gpgkey=https://www.mongodb.org/static/pgp/server-3.6.asc
EOF
    yum install mongodb-org -y
    #Create DB storage
    mkdir -p /data/db && chown -R mongod:mongod /data
#Edit mongodb configuration file
cat >/etc/mongod.conf<<EOF
systemLog:
  destination: file
  logAppend: true
  path: /var/log/mongodb/mongod.log
# Where and how to store data.
storage:
  dbPath: /data/db
  journal:
    enabled: true
# how the process runs
processManagement:
  fork: true  # fork and run in background
  pidFilePath: /var/run/mongodb/mongod.pid  # location of pidfile
# network interfaces
net:
  port: 27017
  bindIp: 127.0.0.1  # Listen to local
EOF
    #Start MongoDB
    systemctl start mongod
    systemctl enable mongod
}

###############FUNCTION MARIADB#####################
mariadb () {
    yum -y install mariadb-server mariadb
    systemctl start mariadb
    systemctl enable mariadb
}

###########INSTALLING DATABASE SERVER#################
if [ $choice -eq 1 ]; then
	echo "Installing MongoDB-3x ..."
	sleep 3
        mongodb
else
	if [ $choice -eq 2 ]; then
		echo "Installing MariaDB ..."
		sleep 3
        	mariadb
	else
		echo "Don't install DB"
	fi
fi

########SETUP NGINX###########
###Create many virtualhosts, same server_name as apache
mkdir /etc/nginx/sites-available/
mkdir /etc/nginx/sites-enabled/

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
	expires 7d;
	access_log off;
}

# svg, fonts
location ~* \.(?:svgz?|ttf|ttc|otf|eot|woff2?)$ {
	add_header Access-Control-Allow-Origin "*";
	expires 7d;
	access_log off;
}

# gzip
gzip on;
gzip_vary on;
gzip_proxied any;
gzip_comp_level 6;
gzip_types text/plain text/css text/xml application/json application/javascript application/xml+rss application/atom+xml image/svg+xml;
EOF