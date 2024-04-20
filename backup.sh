#!/usr/bin/env bash
#
# Backup script to save backup to repository and forgets old snapshots (execute manually or by CHECK_CRON schedule)
# - restic backup
# - restic forget

set -eo pipefail

source /bin/log.sh

lastLogfile="/var/log/restic-backup.log"
backup_dir="/data"


healthcheck() {
    suffix=$1
    if [ -n "$HEALTHCHECK_URL" ]; then
        log "INFO" "Reporting healthcheck $suffix ..."
        [[ ${1} == "/start" ]] && m="" || m=$(cat ${lastLogfile} | tail -n 100)
        curl -fSsL --retry 3 -X POST \
            --user-agent "seatable-restic/1.0.0" \
            --data-raw "$m" "${HEALTHCHECK_URL}${suffix}"
        if [ $? != 0 ]; then
            echo "HEALTHCHECK_URL seems to be wrong..."
            exit 1
        fi
    else
        log "DEBUG" "No HEALTHCHECK_URL provided. Skipping healthcheck."
    fi
}

# always execute /bin/pre-default.sh
log "DEBUG" "Starting pre-default.sh"
/bin/pre-default.sh

# /hooks/pre-backup.sh
if [ -f "/hooks/pre-backup.sh" ]; then
    log "INFO" "Starting pre-backup script"
    /hooks/pre-backup.sh
else
    log "DEBUG" "Pre-backup script not found"
fi

start=`date +%s`
log "INFO" "Starting Backup"
log "DEBUG" "BACKUP_CRON: ${BACKUP_CRON}"
log "DEBUG" "RESTIC_TAG: ${RESTIC_TAG}"
log "DEBUG" "RESTIC_FORGET_ARGS: ${RESTIC_FORGET_ARGS}"
log "DEBUG" "RESTIC_JOB_ARGS: ${RESTIC_JOB_ARGS}"
log "DEBUG" "RESTIC_REPOSITORY: ${RESTIC_REPOSITORY}"

log "INFO" "Directory tree:"
tree -a -P .exclude_from_backup -L 4 ${backup_dir}

log "DEBUG" "Healthcheck start"
healthcheck /start

log "INFO" "Start the restic backup"
restic backup ${backup_dir} ${RESTIC_JOB_ARGS} --tag=${RESTIC_TAG}
backupRC=$?
log "INFO" "Finished restic backup"
if [[ $backupRC == 0 ]]; then
    echo "Backup Successful"
    healthcheck /0
else
    echo "Backup Failed with Status ${backupRC}"
    restic unlock
    healthcheck /fail
fi

if [[ $backupRC == 0 ]] && [ -n "${RESTIC_FORGET_ARGS}" ]; then
    log "INFO" "Forget old snapshots based on RESTIC_FORGET_ARGS = ${RESTIC_FORGET_ARGS}"
    restic forget ${RESTIC_FORGET_ARGS}
    rc=$?
    if [[ $rc == 0 ]]; then
        log "INFO" "Finished restic forget"
    else
        log "ERROR" "Forget Failed with Status: ${rc}"
        restic unlock
        healthcheck /fail
    fi
fi

end=`date +%s`
log "INFO" "Finished Backup at $(date +"%Y-%m-%d %H:%M:%S") after $((end-start)) seconds"

if [ -n "${MAILX_ARGS}" ]; then
    log "INFO" "Executing mail command"
    sh -c "mail -v -S sendwait ${MAILX_ARGS}" 2>&1 | while IFS= read -r line; do
        log "INFO" "$line"
    done
    if [ $? == 0 ]; then
        log "INFO" "Mail notification successfully sent."
    else
        log "ERROR" "Sending mail notification FAILED."
    fi
else
    log "DEBUG" "MAILX_ARGS not defined. Therefore no mail notification"
fi

# /hooks/post-backup.sh
if [ -f "/hooks/post-backup.sh" ]; then
    log "INFO" "Starting post-backup script"
    /hooks/post-backup.sh $backupRC
else
    log "DEBUG" "Post-backup script not found"
fi
