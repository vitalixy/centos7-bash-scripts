#!/bin/bash

ZBX_AGENT_CONF="/etc/zabbix/zabbix_agentd.conf"
ZBX_SERVER_IP='192.168.100.32'

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

# Install Zabbix Agent
# yum clean all
echo "Installing Zabbix Agent"
yum install -y -q zabbix-agent

# Configure Zabbix Agent
if [ -f $ZBX_AGENT_CONF ]; then
    echo "Changing Zabbix Agent configuration"
    egrep '^Server=' $ZBX_AGENT_CONF >/dev/null \
        && sed -i '/^Server=/c Server='"$ZBX_SERVER_IP"'' $ZBX_AGENT_CONF \
        || sed -i '/^#.*Server=/a Server='"$ZBX_SERVER_IP"'' $ZBX_AGENT_CONF
    egrep '^ServerActive=' $ZBX_AGENT_CONF >/dev/null \
        && sed -i '/^ServerActive=/c ServerActive='"$ZBX_SERVER_IP"'' $ZBX_AGENT_CONF \
        || sed -i '/^#.*ServerActive=/a ServerActive='"$ZBX_SERVER_IP"'' $ZBX_AGENT_CONF
    egrep '^Hostname=' $ZBX_AGENT_CONF >/dev/null \
        && sed -i '/^Hostname=/c Hostname='"$HOSTNAME"'' $ZBX_AGENT_CONF \
        || sed -i '/^#.*Hostname=/a Hostname='"$HOSTNAME"'' $ZBX_AGENT_CONF
    # sudo egrep '^(Server.*|Hostname)=' $ZBX_AGENT_CONF
else
    echo "Configuration of Zabbix Agent not found. Installation canceled" >&2
    exit 1
fi

# Configure SELinux
if selinuxenabled; then
    echo "Configuring SELinux"
    yum install -y -q policycoreutils-python
    setsebool -P zabbix_can_network=1
    # semanage permissive -a zabbix_agent_t
fi

# Configure Firewall
if firewall-cmd --state &>/dev/null; then
    echo "Configuring Firewall"
    firewall-cmd --permanent --zone=public --add-rich-rule='rule family="ipv4" \
        source address="'$ZBX_SERVER_IP/32'" port protocol="tcp" port="10050" accept'
    firewall-cmd --reload
fi

# Start Zabbix Agent
echo "Starting Zabbix Agent"
systemctl start zabbix-agent && echo "Zabbix Agent has started"
systemctl enable zabbix-agent


[ $? -eq 0 ] && echo 'Installation has completed!'

# Troubleshoot:
# sudo egrep '^(Server.*|Hostname)=' $ZBX_AGENT_CONF
# cat /var/log/zabbix/zabbix_agentd.log
# cat /var/log/audit/audit.log | grep zabbix_agent
