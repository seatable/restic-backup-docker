#!/usr/bin/env bash
#
# Entry script of this docker container.
# - initializes the repository
# - creates cronjobs for backup and checks

set -eo pipefail

source /bin/log.sh

if ! [[ "$LOG_LEVEL" =~ ^(INFO|WARNING|DEBUG|ERROR)$ ]]; then
    $LOG_LEVEL="ERROR"
    log "ERROR" "Invalid value for LOG_LEVEL found. Allowed values are INFO, WARNING, DEBUG or ERROR."
    exit 1
 fi

log "INFO" "Starting the restic-backup container ..."
log "DEBUG" "LIST OF ENVIRONMENT VARIABLES"
log "DEBUG" "RESTIC_REPOSITORY: ${RESTIC_REPOSITORY}"
log "DEBUG" "RESTIC_PASSWORD: ${RESTIC_PASSWORD}"
log "DEBUG" "BACKUP_CRON: ${BACKUP_CRON}"
log "DEBUG" "CHECK_CRON: ${CHECK_CRON}"

# check for empty environment variables
if [ -z "$RESTIC_REPOSITORY" ] || [ -z "$RESTIC_PASSWORD" ] || [ -z "$BACKUP_CRON" ]; then
    log "ERROR" "Either RESTIC_REPOSITORY, RESTIC_PASSWORD or BACKUP_CRON is empty. Please correct that."
    exit 1
fi

log "DEBUG" "Check if restic repository exists, otherwise initialize."

set +e
restic snapshots ${RESTIC_INIT_ARGS} &>/dev/null
status=$?
set -e
log "DEBUG" "<restic snapshot> returned the status: $status"

if [ $status != 0 ]; then
    log "INFO" "Restic repository '${RESTIC_REPOSITORY}' does not exists. Running restic init."
    set +e
    restic init ${RESTIC_INIT_ARGS}
    init_status=$?
    set -e
    log "DEBUG" "<restic init> returned the status: $init_status"

    if [ $init_status != 0 ]; then
        log "ERROR" "Failed to init the repository: ${RESTIC_REPOSITORY}"
        exit 1
    fi
fi

log "INFO" "Setup backup cron job with cron expression BACKUP_CRON: ${BACKUP_CRON}"
echo "${BACKUP_CRON} /usr/bin/flock -n /var/run/backup.lock /bin/backup >> /var/log/cron.log 2>&1" > /var/spool/cron/crontabs/root

# If CHECK_CRON is set, automatic backup checking is enabled
if [ -n "${CHECK_CRON}" ]; then
    log "INFO" "Setup check cron job with cron expression CHECK_CRON: ${CHECK_CRON}"
    echo "${CHECK_CRON} /usr/bin/flock -n /var/run/backup.lock /bin/check >> /var/log/cron.log 2>&1" >> /var/spool/cron/crontabs/root
else
    log "DEBUG" "NO CHECK_CRON defined"
fi

log "DEBUG" "try to create /var/log/cron.log, to make sure the file exist"
touch /var/log/cron.log

log "DEBUG" "start the cron daemon"
cron

log "INFO" "Container start successful. The restic repository is initialized, cron daemon runs... Ready for backup!"

exec "$@"
