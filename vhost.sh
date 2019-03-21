#!/bin/bash
#keepwalking86
#Scripting for creating vhost

if [ -z $1 ]; then
        echo "Please enter your domain to create site"
	echo "$0 your_domain"
        exit 1
fi
DOMAIN=$1

# check the domain is valid!
PATTERN="^([[:alnum:]]([[:alnum:]\-]{0,61}[[:alnum:]])?\.)+[[:alpha:]]{2,6}$"
if [[ "$DOMAIN" =~ $PATTERN ]]; then
        DOMAIN=`echo $DOMAIN | tr '[A-Z]' '[a-z]'`
else
        echo "Invalid domain. Please enter your domain as example.com"
        exit 1
fi

#Create base directory for $DOMAIN
mkdir -p /var/www/$DOMAIN/public

#Create configuration file for $DOMAIN
cat >/etc/nginx/sites-available/$DOMAIN.conf<<EOF
server {
	listen 80;
	listen [::]:80;

	server_name $DOMAIN;
	set \$base /var/www/$DOMAIN;
	root \$base/public;

	# index.php
	index index.php;

	# index.php fallback
	location / {
		try_files \$uri \$uri/ /index.php?\$query_string;
	}
	# handle .php
	location ~ \.php$ {
		# 404
		try_files \$fastcgi_script_name =404;
		
		# default fastcgi_params
		include /etc/nginx/fastcgi_params;
		
		# fastcgi settings
		fastcgi_pass			127.0.0.1:9000;
		fastcgi_index			index.php;
		fastcgi_buffers			8 16k;
		fastcgi_buffer_size		32k;

	}
}
EOF

# Create symbolic link
ln -s /etc/nginx/sites-available/$DOMAIN.conf /etc/nginx/sites-enabled
