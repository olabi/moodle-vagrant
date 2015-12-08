#!/bin/bash
export DEBIAN_FRONTEND=noninteractive
echo "Running operating system updates..."
sudo apt-add-repository ppa:zabuch/ppa
apt-get update
apt-get -y upgrade
echo "Installing required packages..."
apt-get -y install \
	apache2 \
	libapache2-mod-php5 \
	postgresql \
	postgresql-client \
	php5-pgsql \
	php5-intl \
	php5-curl \
	php5-xmlrpc \
	php-soap \
	php5-gd \
	php5-json \
	php5-cli \
	php5-mcrypt \
	php-pear \
	php5-xsl \
	git \
	moosh \
	mimetex \
	texlive-base \
	texlive-extra-utils \
	imagemagick \
	texi2html \
	texinfo \
	gnuplot \
	clisp
echo "Configuring Apache..."
rm -rf /etc/apache2/sites-enabled
rm -rf /etc/apache2/sites-available
cat <<EOF > /etc/apache2/apache2.conf
Mutex file:\${APACHE_LOCK_DIR} default
PidFile \${APACHE_PID_FILE}
Timeout 300
KeepAlive On
MaxKeepAliveRequests 100
KeepAliveTimeout 5
User \${APACHE_RUN_USER}
Group \${APACHE_RUN_GROUP}
HostnameLookups Off
ErrorLog \${APACHE_LOG_DIR}/error.log
LogLevel warn
IncludeOptional mods-enabled/*.load
IncludeOptional mods-enabled/*.conf
Include ports.conf
AccessFileName .htaccess
<FilesMatch "^\.ht">
	Require all denied
</FilesMatch>
LogFormat "%v:%p %h %l %u %t \"%r\" %>s %O \"%{Referer}i\" \"%{User-Agent}i\"" vhost_combined
LogFormat "%h %l %u %t \"%r\" %>s %O \"%{Referer}i\" \"%{User-Agent}i\"" combined
LogFormat "%h %l %u %t \"%r\" %>s %O" common
LogFormat "%{Referer}i -> %U" referer
LogFormat "%{User-agent}i" agent
IncludeOptional conf-enabled/*.conf
<VirtualHost *:80>
	ServerName moodle.local
	DocumentRoot /var/www/moodle/html
	<Directory /var/www/moodle/html>
		Order allow,deny
		Allow from All
	</Directory>
</VirtualHost>
EOF

cd /tmp
echo "set up stack latest code"
git clone https://github.com/maths/moodle-qtype_stack/ /var/www/moodle/html/question/type/stack
echo "download and build maxima 5.36.0 source code"
wget -q -O maxima_source.tar.gz http://sourceforge.net/projects/maxima/files/Maxima-source/5.36.0-source/maxima-5.36.0.tar.gz/download
tar zxvf maxima_source.tar.gz
cd maxima-5.36.0
./configure
make --quiet
make install --quiet
sudo updatedb
echo "completed building maxima and stack"

echo "Creating database..."
PGHBAFILE=$(find /etc/postgresql -name pg_hba.conf | head -n 1)
cat <<EOF > "${PGHBAFILE}"
local   all             postgres                                peer
# TYPE  DATABASE        USER            ADDRESS                 METHOD
local   all             all                                     peer
host    moodle          moodle          127.0.0.1/32            trust
host    all             all             127.0.0.1/32            md5
host    all             all             ::1/128                 md5
EOF
service postgresql restart
sudo -u postgres createuser -SRDU postgres moodle
sudo -u postgres createdb -E UTF-8 -O moodle -U postgres moodle
echo "Creating Moodle directories..."
mkdir -p /var/www/moodle/html
mkdir -p /var/www/moodle/data
mkdir -p /var/www/moodle/check
cd /var/www/moodle/check
echo "Retrieving latest stable Moodle version..."
git init > /dev/null
git remote add origin https://github.com/moodle/moodle.git
LATEST_VERSION=$(git ls-remote --tags | awk '{print $2}' | grep -v '}$' | grep -v 'beta' | grep -v 'rc' | sed 's/refs\/tags\/v//' | sort -t. -k 1,1n -k 2,2n -k 3,3n | tail -n1)
cd /var/www/moodle
rm -rf /var/www/moodle/check
cd /var/www/moodle/html
echo "Retrieving Moodle version ${LATEST_VERSION}..."
curl -s -o moodle.tgz "https://codeload.github.com/moodle/moodle/tar.gz/v${LATEST_VERSION}"
tar --strip-components 1 -zxf moodle.tgz
rm -f moodle.tgz
echo "Installing Moodle..."
php admin/cli/install.php \
	--lang="en" \
	--wwwroot="http://moodle.local" \
	--dataroot="/var/www/moodle/data" \
	--dbtype="pgsql" \
	--dbname="moodle" \
	--dbuser="moodle" \
	--fullname="Moodle" \
	--shortname="moodle" \
	--adminpass="Admin1!" \
	--agree-license \
	--non-interactive
chown www-data:www-data -R /var/www/moodle
echo "Restarting Apache..."
service apache2 restart
cat <<EOF
Service installed at http://moodle.local/

You will need to add a hosts file entry for:

moodle.local points to 192.168.33.10

username: admin
password: Admin1!

EOF
cat <<EOF > /etc/cron.d/moodle
* * * * * www-data /usr/bin/env php /var/www/moodle/html/admin/cli/cron.php
EOF
