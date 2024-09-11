#!/usr/bin/env bash
#
# Entry script of this docker container.
# - initializes the repository
# - creates cronjobs for backup and checks

source /bin/log.sh

# check for valid LOG_LEVEL
if ! [[ "$LOG_LEVEL" =~ ^(INFO|WARNING|DEBUG|ERROR)$ ]]; then
    LOG_LEVEL="ERROR";
    log "ERROR" "Invalid value for LOG_LEVEL found. Allowed values are INFO, WARNING, DEBUG or ERROR. Exiting"
    exit 1
fi

# check for mandatory input (RESTIC_REPOSITORY, RESTIC_PASSWORD)
[ -z "$RESTIC_REPOSITORY" ] && { log "ERROR" "RESTIC_REPOSITORY is not set. Exiting."; exit 1; }
[ -z "$RESTIC_PASSWORD" ] && { log "ERROR" "RESTIC_PASSWORD is not set. Exiting."; exit 1; }

log "INFO" "Starting the restic-backup container ..."

# make environment variables and path available to cron
env >> /etc/environment

# output environment variables (debug only)
log "DEBUG" "LIST OF ENVIRONMENT VARIABLES:"
log "DEBUG" "RESTIC_REPOSITORY: ${RESTIC_REPOSITORY}"
log "DEBUG" "RESTIC_PASSWORD: ${RESTIC_PASSWORD}"
log "DEBUG" "BACKUP_CRON: ${BACKUP_CRON}"
log "DEBUG" "CHECK_CRON: ${CHECK_CRON}"
log "DEBUG" "LOG_LEVEL: ${LOG_LEVEL}"
log "DEBUG" "LOG_TYPE: ${LOG_TYPE}"
log "DEBUG" "RESTIC_TAG: ${RESTIC_TAG}"
log "DEBUG" "RESTIC_DATA_SUBSET: ${RESTIC_DATA_SUBSET}"
log "DEBUG" "RESTIC_FORGET_ARGS: ${RESTIC_FORGET_ARGS}"
log "DEBUG" "RESTIC_JOB_ARGS: ${RESTIC_JOB_ARGS}"
log "DEBUG" "RESTIC_SKIP_INIT: ${RESTIC_SKIP_INIT}"
log "DEBUG" "DATABASE_DUMP: ${DATABASE_DUMP}"
log "DEBUG" "DATABASE_HOST: ${DATABASE_HOST}"
log "DEBUG" "DATABASE_USER: ${DATABASE_USER}"
log "DEBUG" "DATABASE_LIST: ${DATABASE_LIST}"
log "DEBUG" "SEATABLE_BIGDATA_DUMP: ${SEATABLE_BIGDATA_DUMP}"
log "DEBUG" "SEATABLE_BIGDATA_HOST: ${SEATABLE_BIGDATA_HOST}"
log "DEBUG" "MSMTP_ARGS: ${MSMTP_ARGS}"
log "DEBUG" "HEALTHCHECK_URL": ${HEALTHCHECK_URL}"

if [ "${RESTIC_SKIP_INIT}" == true ]; then
    log "INFO" "Skip restic init"
else
    log "DEBUG" "Check if restic repository exists, otherwise initialize."
    restic snapshots ${RESTIC_INIT_ARGS} &>/dev/null
    status=$?
    log "DEBUG" "<restic snapshot> returned status: $status"

    if [ $status != 0 ]; then
        log "INFO" "Restic repository '${RESTIC_REPOSITORY}' does not exists. Running restic init."
        restic init ${RESTIC_INIT_ARGS}
        init_status=$?
        log "DEBUG" "<restic init> returned status: $init_status"

        if [ $init_status != 0 ]; then
            log "ERROR" "Failed to init the repository: ${RESTIC_REPOSITORY}"
            exit 1
        fi
    fi
fi

log "INFO" "Setup backup cron job with cron expression BACKUP_CRON: ${BACKUP_CRON}"
echo "${BACKUP_CRON} root /usr/bin/flock -n /var/run/backup.lock /bin/backup >/proc/1/fd/1 2>/proc/1/fd/2" > /etc/crontab

# If CHECK_CRON is set, automatic backup checking is enabled
if [ -n "${CHECK_CRON}" ]; then
    log "INFO" "Setup check cron job with cron expression CHECK_CRON: ${CHECK_CRON}"
    echo "${CHECK_CRON} root /usr/bin/flock -n /var/run/backup.lock /bin/check >/proc/1/fd/1 2>/proc/1/fd/2" >> /etc/crontab
else
    log "DEBUG" "NO CHECK_CRON defined"
fi
echo '
# An empty line is required at the end of this file for a valid cron file.
' >> /etc/crontab

log "DEBUG" "start the cron daemon now."

log "INFO" "Container started successful. The restic repository is initialized, cron daemon runs... Ready for backup!"
exec "$@"
