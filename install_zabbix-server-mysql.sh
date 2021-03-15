#!/bin/bash

ZBX_CONF="/etc/zabbix/zabbix_server.conf"
PHP_CONF="/etc/httpd/conf.d/zabbix.conf"
WEB_CONF="/etc/zabbix/web/zabbix.conf.php"
SQL_DATA="/usr/share/doc/zabbix-server-mysql*/create.sql.gz"

TIMEZONE="Europe/Minsk"
ZBX_SERVER='localhost'
DB_HOST="localhost"
DB_NAME="zabbix"
DB_USER="zabbix"
DB_PASS="Z@bb1X"

# Check OS
[ -f /etc/os-release ] && eval "$(egrep '^(ID|VERSION_ID)=' /etc/os-release)" || exit 1
if [ $ID != "centos" ] || [ $VERSION_ID != 7 ]; then
    echo "Current OS is not supported. CentOS Linux 7 required" >&2
    exit 1
fi

# Check user
if [ `whoami` != root ]; then
    echo "Please run this script as root or using sudo" >&2
    exit 1
fi

# Install the repository configuration package
echo "Adding Zabbix repository"
rpm -Uvh https://repo.zabbix.com/zabbix/4.4/rhel/7/x86_64/zabbix-release-4.4-1.el7.noarch.rpm
yum-config-manager --enable rhel-7-server-optional-rpms

# Install apache and mariadb
echo "Installing Apache and MariaDB"
yum install -y -q httpd mariadb-server mariadb

# Configure MariaDB
echo "Starting MariaDB"
systemctl start mariadb && echo "MariaDB has started"
systemctl enable mariadb.service


echo "Creating zabbix database and zabbix db user"
mysql -e "CREATE DATABASE $DB_NAME CHARACTER SET utf8 COLLATE utf8_bin;"
mysql -e "CREATE USER '$DB_USER'@localhost IDENTIFIED BY '$DB_PASS';"
mysql -e "GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@localhost IDENTIFIED BY '$DB_PASS';"
mysql -e "FLUSH PRIVILEGES;"

# Trobleshoot:
# mysql -e "SELECT User FROM mysql.user;"
# mysql -e "SET PASSWORD FOR 'zabbix'@localhost = PASSWORD('$DB_PASS');"

# Delete:
# DROP USER zabbix@localhost;
# DROP DATABASE zabbix;


# Install Zabbix
# yum clean all
echo "Installing Zabbix Server"
yum install -y -q zabbix-server-mysql zabbix-web-mysql zabbix-agent

# Import SQL data
if [ -f $SQL_DATA ]; then
    echo "Importing SQL data"
    zcat $SQL_DATA | sudo mysql -u $DB_USER -p"$DB_PASS" zabbix
else
    echo "SQL data file $SQL_DATA not found. Installation canceled"
    exit 1
fi

# Configure Zabbix Server
if [ -f $ZBX_CONF ]; then
    echo "Changing Zabbix Server configuration"
    egrep '^DBHost=' $ZBX_CONF >/dev/null \
        && sed -i '/^DBHost=/c DBHost='"$DB_HOST"'' $ZBX_CONF \
        || sed -i '/^#.*DBHost=/a DBHost='"$DB_HOST"'' $ZBX_CONF
    egrep '^DBName=' $ZBX_CONF >/dev/null \
        && sed -i '/^DBName=/c DBName='"$DB_NAME"'' $ZBX_CONF \
        || sed -i '/^#.*DBName=/a DBName='"$DB_NAME"'' $ZBX_CONF
    egrep '^DBUser=' $ZBX_CONF >/dev/null \
        && sed -i '/^DBUser=/c DBUser='"$DB_USER"'' $ZBX_CONF \
        || sed -i '/^#.*DBUser=/a DBUser='"$DB_USER"'' $ZBX_CONF
    egrep '^DBPassword=' $ZBX_CONF >/dev/null \
        && sed -i '/^DBPassword=/c DBPassword='"$DB_PASS"'' $ZBX_CONF \
        || sed -i '/^#.*DBPassword=/a DBPassword='"$DB_PASS"'' $ZBX_CONF
    # sudo egrep '^DB(Host|Name|User|Password)=' $ZBX_CONF
else
    echo "Configuration of Zabbix Server not found. Installation canceled" >&2
    exit 1
fi

# Configure PHP
if [ -f $PHP_CONF ]; then
    echo "Changing timezone to $TIMEZONE for PHP"
    egrep '#* *php_value *date.timezone.*' $PHP_CONF >/dev/null && \
        sed -i 's!#* *php_value *date.timezone.*!php_value date.timezone '"$TIMEZONE"'!' $PHP_CONF
    # sudo egrep '#* *php_value *date.timezone.*' $PHP_CONF
fi

# Configure Zabbix Frontend
echo "Creating Zabbix Frontend configuration"
cat << EOF > $WEB_CONF
<?php
// Zabbix GUI configuration file.
global \$DB;

\$DB['TYPE']     = 'MYSQL';
\$DB['SERVER']   = '$DB_HOST';
\$DB['PORT']     = '0';
\$DB['DATABASE'] = '$DB_NAME';
\$DB['USER']     = '$DB_USER';
\$DB['PASSWORD'] = '$DB_PASS';

// Schema name. Used for IBM DB2 and PostgreSQL.
\$DB['SCHEMA'] = '';

\$ZBX_SERVER      = '$ZBX_SERVER';
\$ZBX_SERVER_PORT = '10051';
\$ZBX_SERVER_NAME = 'Zabbix';

\$IMAGE_FORMAT_DEFAULT = IMAGE_FORMAT_PNG;
EOF

chmod 644 $WEB_CONF
chcon system_u:object_r:httpd_sys_rw_content_t:s0 $WEB_CONF
chown apache:apache $WEB_CONF
# ls -Z $WEB_CONF

# Configure SELinux
if selinuxenabled; then
    echo "Configuring SELinux"
    yum install -y -q policycoreutils-python
    setsebool -P httpd_can_connect_zabbix on
    setsebool -P zabbix_can_network=1

    # Create SELinux policy module
    cat << EOF > zabbix_server_add.te
module zabbix_server_add 1.1;

require {
        type zabbix_var_run_t;
        type tmp_t;
        type zabbix_t;
        class sock_file { create unlink write };
        class unix_stream_socket connectto;
        class process setrlimit;
}

#============= zabbix_t ==============
#!!!! This avc is allowed in the current policy
allow zabbix_t self:process setrlimit;

#!!!! This avc is allowed in the current policy
allow zabbix_t self:unix_stream_socket connectto;

#!!!! This avc is allowed in the current policy
allow zabbix_t tmp_t:sock_file { create unlink write };

#!!!! This avc is allowed in the current policy
allow zabbix_t zabbix_var_run_t:sock_file { create unlink write };
EOF
    
    # Install SELinux module
    if  [ -f zabbix_server_add.te ]; then
        echo "Installing SELinux policy module"
        checkmodule -M -m -o zabbix_server_add.mod zabbix_server_add.te
        semodule_package -m zabbix_server_add.mod -o zabbix_server_add.pp
        semodule -i zabbix_server_add.pp
        rm -f zabbix_server_add*
    fi
fi

# Configure Firewall
if firewall-cmd --state &>/dev/null; then
    echo "Configuring Firewall"
    firewall-cmd --permanent --add-port=10050/tcp
    firewall-cmd --permanent --add-port=10051/tcp
    firewall-cmd --permanent --add-port=80/tcp
    firewall-cmd --reload
fi

# Start Zabbix Server
echo "Starting Apache, Zabbix Server and Zabbix Agent"
systemctl start httpd zabbix-server zabbix-agent && echo "Zabbix Server has started"
systemctl enable httpd zabbix-server zabbix-agent

[ $? -eq 0 ] && echo 'Installation has completed!'

# Troubleshoot:
# cat /var/log/zabbix/zabbix_server.log
# cat /var/log/audit/audit.log | grep zabbix
# cat /var/log/audit/audit.log | grep avc.*denied.*zabbix
# curl http://$ZBX_SERVER/zabbix/
# Web user: Admin , Password: zabbix
