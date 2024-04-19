#!/usr/bin/env bash
#
# description of the script

set -eo pipefail

#

echo "Starting container ..."

restic snapshots ${RESTIC_INIT_ARGS} &>/dev/null
status=$?
echo "Check Repo status $status"

if [ $status != 0 ]; then
    echo "Restic repository '${RESTIC_REPOSITORY}' does not exists. Running restic init."
    restic init ${RESTIC_INIT_ARGS}

    init_status=$?
    echo "Repo init status $init_status"

    if [ $init_status != 0 ]; then
        echo "Failed to init the repository: '${RESTIC_REPOSITORY}'"
        exit 1
    fi
fi

echo "Setup backup cron job with cron expression BACKUP_CRON: ${BACKUP_CRON}"
echo "${BACKUP_CRON} /usr/bin/flock -n /var/run/backup.lock /bin/backup >> /var/log/cron.log 2>&1" > /var/spool/cron/crontabs/root

# If CHECK_CRON is set, automatic backup checking is enabled
if [ -n "${CHECK_CRON}" ]; then
    echo "Setup check cron job with cron expression CHECK_CRON: ${CHECK_CRON}"
    echo "${CHECK_CRON} /usr/bin/flock -n /var/run/backup.lock /bin/check >> /var/log/cron.log 2>&1" >> /var/spool/cron/crontabs/root
fi

# Make sure the file exists before we start tail
touch /var/log/cron.log

# start the cron daemon
cron

echo "Container started."

exec "$@"
