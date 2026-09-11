#!/usr/bin/env bash
#
# Entry script of this docker container.
# - initializes the repository
# - creates cronjobs for backup and checks

# shellcheck source=log.sh
source /bin/log.sh

# check for valid LOG_LEVEL
if ! [[ "$LOG_LEVEL" =~ ^(INFO|WARNING|DEBUG|ERROR)$ ]]; then
    LOG_LEVEL="ERROR";
    log "ERROR" "Invalid value for LOG_LEVEL found. Allowed values are INFO, WARNING, DEBUG or ERROR. Exiting"
    exit 1
fi

# check for valid RESTIC_TIMEOUT (a duration for the timeout command like 48h, 90m or 3600s; 0 disables the timeout)
if [ -n "$RESTIC_TIMEOUT" ] && ! [[ "$RESTIC_TIMEOUT" =~ ^[0-9]+(\.[0-9]+)?[smhd]?$ ]]; then
    log "ERROR" "Invalid value for RESTIC_TIMEOUT found. Allowed is a number with optional suffix s, m, h or d (e.g. 48h) or 0 to disable. Exiting"
    exit 1
fi

# check for valid RESTIC_DATA_SUBSET in the rotate form (rotate:N with N >= 1); other forms are validated by restic
if [[ "$RESTIC_DATA_SUBSET" == rotate:* ]] && ! [[ "$RESTIC_DATA_SUBSET" =~ ^rotate:[1-9][0-9]*$ ]]; then
    log "ERROR" "Invalid value for RESTIC_DATA_SUBSET found. The rotate form must be rotate:N with N >= 1 (e.g. rotate:10). Exiting"
    exit 1
fi

# check for mandatory input (RESTIC_REPOSITORY, RESTIC_PASSWORD)
[ -z "$RESTIC_REPOSITORY" ] && { log "ERROR" "RESTIC_REPOSITORY is not set. Exiting."; exit 1; }
[ -z "$RESTIC_PASSWORD" ] && { log "ERROR" "RESTIC_PASSWORD is not set. Exiting."; exit 1; }

log "INFO" "Starting the restic-backup container (version ${VERSION}) ..."

# make environment variables and path available to cron
env >> /etc/environment

# output environment variables (debug only)
log "DEBUG" "LIST OF ENVIRONMENT VARIABLES:"
log "DEBUG" "RESTIC_REPOSITORY: ${RESTIC_REPOSITORY}"
log "DEBUG" "RESTIC_PASSWORD: ${RESTIC_PASSWORD}"
log "DEBUG" "BACKUP_CRON: ${BACKUP_CRON}"
log "DEBUG" "CHECK_CRON: ${CHECK_CRON}"
log "DEBUG" "PRUNE_CRON: ${PRUNE_CRON}"
log "DEBUG" "LOG_LEVEL: ${LOG_LEVEL}"
log "DEBUG" "LOG_TYPE: ${LOG_TYPE}"
log "DEBUG" "RESTIC_TAG: ${RESTIC_TAG}"
log "DEBUG" "RESTIC_DATA_SUBSET: ${RESTIC_DATA_SUBSET}"
log "DEBUG" "RESTORE_TEST: ${RESTORE_TEST}"
log "DEBUG" "RESTIC_FORGET_ARGS: ${RESTIC_FORGET_ARGS}"
log "DEBUG" "RESTIC_JOB_ARGS: ${RESTIC_JOB_ARGS}"
log "DEBUG" "RESTIC_PRUNE_ARGS: ${RESTIC_PRUNE_ARGS}"
log "DEBUG" "RESTIC_SKIP_INIT: ${RESTIC_SKIP_INIT}"
log "DEBUG" "RESTIC_TIMEOUT: ${RESTIC_TIMEOUT}"
log "DEBUG" "DATABASE_DUMP: ${DATABASE_DUMP}"
log "DEBUG" "DATABASE_HOST: ${DATABASE_HOST}"
log "DEBUG" "DATABASE_USER: ${DATABASE_USER}"
log "DEBUG" "DATABASE_LIST: ${DATABASE_LIST}"
log "DEBUG" "DATABASE_DUMP_COMPRESSION: ${DATABASE_DUMP_COMPRESSION}"
log "DEBUG" "SEATABLE_BIGDATA_DUMP: ${SEATABLE_BIGDATA_DUMP}"
log "DEBUG" "SEATABLE_BIGDATA_HOST: ${SEATABLE_BIGDATA_HOST}"
log "DEBUG" "MSMTP_ARGS: ${MSMTP_ARGS}"
log "DEBUG" "HEALTHCHECK_URL: ${HEALTHCHECK_URL}"
log "DEBUG" "USER_AGENT: ${USER_AGENT}"

if [ "${RESTIC_SKIP_INIT}" = "true" ]; then
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
echo "${BACKUP_CRON} root /bin/cron-run backup >/proc/1/fd/1 2>/proc/1/fd/2" > /etc/crontab

# If CHECK_CRON is set, automatic backup checking is enabled
if [ -n "${CHECK_CRON}" ]; then
    log "INFO" "Setup check cron job with cron expression CHECK_CRON: ${CHECK_CRON}"
    echo "${CHECK_CRON} root /bin/cron-run check >/proc/1/fd/1 2>/proc/1/fd/2" >> /etc/crontab
else
    log "DEBUG" "NO CHECK_CRON defined"
fi

# If PRUNE_CRON is set, a separate prune job is scheduled (use without --prune in RESTIC_FORGET_ARGS)
if [ -n "${PRUNE_CRON}" ]; then
    log "INFO" "Setup prune cron job with cron expression PRUNE_CRON: ${PRUNE_CRON}"
    echo "${PRUNE_CRON} root /bin/cron-run prune >/proc/1/fd/1 2>/proc/1/fd/2" >> /etc/crontab
else
    log "DEBUG" "NO PRUNE_CRON defined"
    # forget without prune only removes snapshot references, the data stays in the repository forever
    if [ -n "${RESTIC_FORGET_ARGS}" ] && [[ "${RESTIC_FORGET_ARGS}" != *"--prune"* ]]; then
        log "WARNING" "RESTIC_FORGET_ARGS is set without --prune and PRUNE_CRON is empty: forgotten snapshots are never removed from the repository and it will grow. Set PRUNE_CRON or add --prune to RESTIC_FORGET_ARGS."
    fi
fi
echo '
# An empty line is required at the end of this file for a valid cron file.
' >> /etc/crontab

log "DEBUG" "start the cron daemon now."

log "INFO" "Container started successful. The restic repository is initialized, cron daemon runs... Ready for backup!"
exec "$@"
