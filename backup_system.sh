#!/bin/bash

BACKUP_PATH="/media/backup/"
LIMITSIZE=5242880 # 5G = 5*1024*1024k
FREE=$(df -k --output=avail "$BACKUP_PATH" | tail -n1)
LOG_FILE=/tmp/backup.log

timestamp()
{
 date "+%Y-%m-%d %H:%M:%S"
}

# Writing outputs to log file and console
exec > >(tee ${LOG_FILE}) 2>&1
echo "$(timestamp) Starting Backup Job"

# Check user
if [ `whoami` != root ]; then
    echo "Root permission required"
    echo "$(timestamp) Backup canceled"
    exit 1
fi

# Copy script to /usr/local/bin/
if ! [ -f /usr/local/bin/backup.sh ]; then
    echo "Copy current script to /usr/local/bin/ as 'backup.sh'"
    cp $0 /usr/local/bin/backup.sh
fi

# Create daily backup job
if [ -f /etc/cron.d/backup ]; then
    echo "Cron Table file 'backup' found in /etc/cron.d"
    cat /etc/cron.d/backup
    echo
else
    echo "Creating Cron Table file 'backup' with content:"
    echo "0  0  *  *  * root  /usr/local/bin/backup.sh" | tee backup
    echo
    echo "Moving file 'backup' to /etc/cron.d"
    mv backup /etc/cron.d/ && echo "Backup Job has been successfully scheduled"
    echo
fi

# Check free space
if [ $FREE -lt $LIMITSIZE ]; then
    echo "Not enough free space on $BACKUP_PATH. Requires at least 5 GB of free space"
    echo "$(timestamp) Backup canceled"
    exit 1
fi

# Run backup
if [ -d $BACKUP_PATH ]; then
    archive_name="$(date "+%d-%m-%Y-%H-%M-%S").tar.gz"
    cd $BACKUP_PATH
    echo "Performing backup..."
    tar -zcpf $archive_name \
        --exclude=/proc \
        --exclude=/tmp \
        --exclude=/mnt \
        --exclude=/dev \
        --exclude=/sys \
        --exclude=/run \
        --exclude=/media \
        --exclude=/var/log \
        --exclude=/var/cache/yum \
        --exclude=/var/spool/postfix/private \
        --exclude=/var/spool/postfix/public \
        --exclude=/usr/src/linux-headers* \
        --exclude=/home/*/.gvfs \
        --exclude=/home/*/.cache \
        --exclude=/home/*/.local/share/Trash /
    [ $? -eq 0 ] && echo "$(timestamp) Backup $archive_name has created successfully"
else
    echo "No such directory: $BACKUP_PATH"
    echo "$(timestamp) Backup canceled"
    exit 1
fi

# Disable Backup Job
# sudo rm /usr/local/bin/backup.sh
# sudo rm /etc/cron.d/backup
