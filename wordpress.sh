if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root"
   exit 1
fi
LOG=script.log
ERROR=script.err

mysql_secure_installation () {
  echo -e "Removing Insecure Details From MySQL"
  mysql -u$adminuser -p$adminpass -e "DELETE FROM mysql.user WHERE User='';"
  mysql -u$adminuser -p$adminpass -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"
  mysql -u$adminuser -p$adminpass -e "DROP DATABASE IF EXISTS test;"
  mysql -u$adminuser -p$adminpass -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';"
  mysql -u$adminuser -p$adminpass -e "FLUSH PRIVILEGES;"
}

mysql_setup () {
  echo -e "${BLUE}Setting up mysql-server...${NC}"
  echo -e "${CAYAN}"
  ct=0
    while [ $ct -eq 0 ]
    do
      read -p  "Enter User for MYSQL Admin: " adminuser
      echo
      read -sp "Enter the password for MYSQL Admin: " adminpass
      echo
      read -sp "Re-enter the password for MYSQL Admin: " re_adminpass
      echo

          if [ $adminpass == $re_adminpass ];
          then
              echo -e "${GREEN}Password will be set for MySQL Admin.${NC}"
              echo "mysql-server mysql-server/root_password password $adminpass" | sudo debconf-set-selections
              echo "mysql-server mysql-server/root_password_again password $adminpass" | sudo debconf-set-selections
              ct=1
          else
              echo -e "${RED}Password did not match... Try again${NC}"
          fi
    done
  echo -e "${NC}"
}

apt update
RED='\033[0;31m'       GREEN='\033[0;32m'       NC='\033[0m'          CAYAN='\033[0;36m'
BLUE='\033[0;34m'      HBLK='\033[1;94m'        YELLOW='\033[1;93m'

echo -e "------------------------------------"
echo -e "${BLUE}Checking if Nginx is installed${NC}"
dpkg -l | grep nginx
if [ "$?" -eq 0 ];
then
   echo
   echo -e "${GREEN}NGINX is already Installed...${NC}";
   service nginx start
   echo -e "------------------------------------"
else
   echo -e "------------------------------------"
   echo -e "${BLUE}Installing NGINX...${NC}"
       apt install nginx -y >>$LOG 2>>$ERROR
       service nginx start
   echo -e "${GREEN}Nginx is Installed.${NC}";
   echo -e "------------------------------------"
fi

echo -e "${BLUE}Checking if Mysql is installed${NC}"
dpkg -l | grep mysql-server
if [ "$?" -eq 0 ];
then
   echo
   echo -e "${GREEN}MySQL-Server is already Installed...${NC}";
   service mysql start
   echo -e "${CAYAN}"
   read -p  "Enter the user name of MYSQL Admin: " adminuser
   read -sp "Enter the pasword of MYSQL Admin: " adminpass
   echo -e "${NC}"
   mysql_secure_installation
else
  mysql_setup
  echo -e "------------------------------------"
  echo -e "${BLUE}Installing mysql-server... ${NC}"
  apt install mysql-server -y >>$LOG 2>>$ERROR
   service mysql start
  mysql_secure_installation
  echo -e "${GREEN}Mysql Setup is complete. ${NC}"
  echo -e "------------------------------------"
fi

echo -e "${CAYAN}"
read -p "Enter domain name: www." domain
echo
echo -e "Your Domain name is www.$domain "
echo -e "Making entry for www.$domain"
echo "127.0.0.1	$domain www.$domain" >> /etc/hosts
echo -e "${NC}"

ct=0
dbname="$domain"_db
  echo
  echo -e "${CAYAN}"
  read -p "Enter the user for $dbname database: " wpuser
  while [ $ct -eq 0 ]
  do
      echo -e "${CAYAN}"
      read -sp "Enter the password for $dbname database: " wppass
      echo
      read -sp "Re-enter the password for $dbname database: " re_wppass
      echo -e "${NC}"
      echo
      echo
      if [ $wppass == $re_wppass ];
      then
          echo -e "${GREEN}Password set for wordpress database.${NC}"
          mysql -u$adminuser -p$adminpass -e "CREATE DATABASE \`$dbname\`"
          mysql -u$adminuser -p$adminpass -e "GRANT ALL PRIVILEGES ON \`$dbname\`.* TO '$wpuser'@"localhost" IDENTIFIED BY '$wppass';"
          mysql -u$adminuser -p$adminpass -e "FLUSH PRIVILEGES;"
          ct=1
      else
          echo -e "${RED}Password did not match... Try again${NC}"

      fi
  done
echo -e "${NC}"

for i in curl php7.0-fpm php7.0-mysql mysql-client php-curl php-gd php-mbstring php-mcrypt php-xml php-xmlrpc;
do
    echo -e "------------------------------------"
    echo -e "${GREEN}Checking if $i is installed${NC}";
    dpkg -l | grep $i
    if [ "$?" -eq 0 ];
    then
      echo -e "${GREEN}$i is Installed${NC}"
      echo -e "-----------------------------------"
    else
      echo -e "-----------------------------------"
      echo -e "${RED}$i is not Installed.${NC}"
      echo -e "${BLUE}Installing $i ...${NC}"
      export DEBIAN_FRONTEND=noninteractive
      apt install $i -y >>$LOG 2>>$ERROR
      echo -e "${GREEN}$i Package is installed..${NC} "
      echo -e "----------------------------------"
    fi
done
  service php7.0-fpm start
cat <<eof > /etc/nginx/sites-available/default
server {

    listen 80;
    listen [::]:80;

    root /var/www/$domain/html;
    index index.php index.html index.htm index.nginx-debian.html;

    server_name $domain;

    location / {
        try_files \$uri \$uri/ /index.php$is_args$args;

    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php7.0-fpm.sock;
    }

    location ~ /\.ht {
        deny all;
    }

}
eof
service nginx reload
service nginx restart

echo -e "Cleaning old files and Setting up new files..."
rm /etc/nginx/sites-available/$domain
cp /etc/nginx/sites-available/default /etc/nginx/sites-available/$domain

 #Nginx php configuration
sed -i 's/^;\?cgi\.fix\_pathinfo=.*$/cgi.fix_pathinfo=0/' /etc/php/7.0/fpm/php.ini
service php7.0-fpm reload
service php7.0-fpm restart
echo
echo -e "${HBLK}Downloading wordpress...${NC}"

cd /tmp
curl -O https://wordpress.org/latest.tar.gz
tar xzvf latest.tar.gz

cp /tmp/wordpress/wp-config-sample.php /tmp/wordpress/wp-config.php

rm -f /etc/nginx/sites-enabled/$domain
ln -s /etc/nginx/sites-available/$domain /etc/nginx/sites-enabled/

mkdir -p /var/www/$domain/html
cp -a /tmp/wordpress/. /var/www/$domain/html
chown -R $USER:www-data /var/www/$domain/html
find /var/www/$domain/html -type d -exec chmod g+s {} \;
chmod g+w /var/www/$domain/html/wp-content
chmod -R g+w /var/www/$domain/html/wp-content/themes
chmod -R g+w /var/www/$domain/html/wp-content/plugins
curl https://api.wordpress.org/secret-key/1.1/salt/ -o salt.txt
sed -i '49,56d;57r salt.txt' /var/www/$domain/html/wp-config.php

sed -i "s/database_name_here/$dbname/" /var/www/$domain/html/wp-config.php
sed -i "s/username_here/$wpuser/" /var/www/$domain/html/wp-config.php
sed -i "s/password_here/$wppass/" /var/www/$domain/html/wp-config.php

service nginx restart
service php7.0-fpm restart

rm /etc/nginx/sites-available/default
rm /etc/nginx/sites-enabled/default

echo -e "Visit the site at ${YELLOW} www.$domain ${NC}"
#echo -e "WordPress Database name:${YELLOW} $dbname ${NC}"
#echo -e "WordPress Database user:${YELLOW} $wpuser ${NC}"
# echo -e "WordPress Database password:${YELLOW} $wppass ${NC}"
