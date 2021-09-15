#!/bin/bash

# Check OS
[ -f /etc/os-release ] && eval "$(egrep '^(ID|VERSION_ID)=' /etc/os-release)" || exit 1
if [ $ID != "centos" ] || [ $VERSION_ID != 7 ]; then
    echo "Current OS is not supported. CentOS Linux 7 required" >&2
    exit 1
fi

sudo mkdir /var/run/cloud-sql-proxy
sudo mkdir /var/local/cloud-sql-proxy
sudo chown root:root /var/run/cloud-sql-proxy
sudo chown root:root /var/local/cloud-sql-proxy

sudo curl -o /usr/local/bin/cloud_sql_proxy -0 https://dl.google.com/cloudsql/cloud_sql_proxy.linux.amd64
sudo chmod +x /usr/local/bin/cloud_sql_proxy

sudo bash -c 'cat <<EOF > /lib/systemd/system/cloud-sql-proxy.service
[Install]
WantedBy=multi-user.target

[Unit]
Description=Google Cloud SQL Proxy
Requires=network.target
After=network.target

[Service]
Type=simple
RuntimeDirectory=cloud-sql-proxy
WorkingDirectory=/usr/local/bin
ExecStart=/usr/local/bin/cloud_sql_proxy -dir=/var/run/cloud-sql-proxy -instances=mg-cops-prd:us-central1:pmua-prd-01-mysql-main-replica=tcp:3306 -credential_file=/var/local/cloud-sql-proxy/credential.json
Restart=always
StandardOutput=journal
EOF'

sudo systemctl daemon-reload

echo "Put a service account key (credential.json) to /var/local/cloud-sql-proxy/ and then run 'sudo systemctl start cloud-sql-proxy'."
# scp ~/Downloads/credential.json vagrant@192.168.100.41:/home/vagrant/credential.json
# vagrant ssh
# sudo mv credential.json /var/local/cloud-sql-proxy/
# sudo chmod 400 /var/local/cloud-sql-proxy/credential.json && sudo chown root:root /var/local/cloud-sql-proxy/credential.json
# sudo systemctl enable cloud-sql-proxy && sudo systemctl start cloud-sql-proxy 
# mysql -u root -p --host 127.0.0.1 --port 3306
read -p "Press any key to exit... "