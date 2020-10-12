#Script for installing Nginx + PHP7 + MongoDB/MariaDB on Ubuntu 16.04
#Declare
nginx_version=1.18.0
mongodb_version=4.0
mariadb_version=10.4
#Download the latest version of NGINX source code
function install_nginx() {
    echo "${txtyellow}***Check OS and install essential package to compile nginx***${txtreset}"
    sleep 2
    apt-get install libpcre3 libpcre3-dev libssl-dev zlib1g-dev -y
    echo "Create nginx user"
    useradd -d /dev/null -c "nginx user" -s /sbin/nologin nginx

    # Download & unpack latest stable nginx & nginx-rtmp version
    echo "${txtyellow}***Download and unpack latest stable nginx***${txtreset}"
    sleep 3
    cd /opt
    wget http://nginx.org/download/nginx-${nginx_version}.tar.gz
    tar zxf nginx-${nginx_version}.tar.gz
    cd nginx-${nginx_version}
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
}

#Function for installing php72
function install_php72() {
    apt-get install software-properties-common python-software-properties -y
    add-apt-repository -y ppa:ondrej/php
    apt-get update -y
    apt-get install php7.2 php7.2-fpm php7.2-curl php7.2-gd php7.2-json php7.2-mbstring php7.2-intl php7.2-xml php7.2-zip php7.2-opcache -y
    echo "Starting php-fpm"
    systemctl start php7.2-fpm.service
    systemctl enable php7.2-fpm.service
}

##FUNCTION MONGODB##
mongodb () {
#Create mongodb repo
    apt-get install gnupg -y
    wget -qO - https://www.mongodb.org/static/pgp/server-${mongodb_version}.asc | sudo apt-key add -
    echo "deb http://repo.mongodb.org/apt/ubuntu xenial/mongodb-org/${mongodb_version} multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-org-${mongodb_version}.list
    apt-get update -y
    apt-get install mongodb-org mongodb-org-server mongodb-org-shell mongodb-org-mongos mongodb-org-tools -y
    #Start MongoDB
    systemctl start mongod
    systemctl enable mongod
}

##FUNCTION MARIADB##
mariadb () {
    wget https://downloads.mariadb.com/MariaDB/mariadb_repo_setup
    echo "2de6253842f230bc554d3f5ab0c0dbf717caffbf45ae6893740707961c8407b7 mariadb_repo_setup" | sha256sum -c -
    chmod +x mariadb_repo_setup
    ./mariadb_repo_setup --mariadb-server-version="mariadb-${mariadb_version}"
    apt update -y
    apt install mariadb-server mariadb-backup -y
    systemctl start mariadb
    systemctl enable mariadb
}

## Installing requirements packages
apt-get update -y
apt install build-essential wget -y
#### Setup Nginx
install_nginx
# Run Nginx with systemd
cat >/lib/systemd/system/nginx.service<<EOF
[Unit]
Description=nginx - The nginx HTTP and reverse proxy server
Documentation=http://nginx.org/en/docs/
After=network-online.target remote-fs.target nss-lookup.target
Wants=network-online.target
[Service]
Type=forking
ExecStartPre=/bin/rm -f /var/run/nginx.pid
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
#Create many virtualhosts
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
#Setup PHP
install_php72

##INSTALLING DATABASE SERVER
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
        apt-get install php7.2-mongodb -y
else
        if [ $choice -eq 2 ]; then
		    echo "${txtyellow}***Preparing to install MariaDB***${txtreset}"
			sleep 3
			mariadb
            apt-get install php7.2-mysql -y
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
