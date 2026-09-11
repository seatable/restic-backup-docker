#!/usr/bin/env bash
#
# Backup script to save backup to repository and forgets old snapshots (execute manually or by BACKUP_CRON schedule)
# - restic backup
# - restic forget

# shellcheck source=log.sh
source /bin/log.sh
# shellcheck source=functions.sh
source /bin/functions.sh

backup_dir="/data"
start=`date +%s`

# Abort the backup run before restic was started: report via healthcheck and mail, then exit.
abort() {
    report_error "$1"
    healthcheck /fail
    send_mail "Restic-Backup"
    exit 1
}

log "INFO" "Starting Backup"
echo "Starting Backup at $(date +"%Y-%m-%d %H:%M:%S")" > $lastLogfile
log "DEBUG" "BACKUP_CRON: ${BACKUP_CRON}"
log "DEBUG" "RESTIC_TAG: ${RESTIC_TAG}"
log "DEBUG" "RESTIC_FORGET_ARGS: ${RESTIC_FORGET_ARGS}"
log "DEBUG" "RESTIC_JOB_ARGS: ${RESTIC_JOB_ARGS}"
log "DEBUG" "RESTIC_REPOSITORY: ${RESTIC_REPOSITORY}"
log "DEBUG" "RESTIC_TIMEOUT: ${RESTIC_TIMEOUT}"

# /start is reported before the pre-scripts, so that a hanging database dump is
# detected by the healthcheck server as well (no /0 or /fail within the grace time).
log "DEBUG" "Healthcheck start"
healthcheck /start

# always execute /bin/pre-default.sh
log "DEBUG" "Starting pre-default.sh"
/bin/pre-default.sh
if [ $? -ne 0 ]; then
    abort "pre-default.sh was not successful."
fi

# /hooks/pre-backup.sh
if [ -f "/hooks/pre-backup.sh" ]; then
    log "INFO" "Starting pre-backup script"
    /hooks/pre-backup.sh
    if [ $? -ne 0 ]; then
        abort "pre-backup.sh was not successful."
    fi
else
    log "DEBUG" "Pre-backup script not found"
fi

log "DEBUG" "Save directory tree:"
tree -a -P *.gz -P *.dump -P .exclude_from_backup -L 3 ${backup_dir} >> $lastLogfile

log "INFO" "Start the restic backup"
run_restic backup ${backup_dir} ${RESTIC_JOB_ARGS} --tag=${RESTIC_TAG} >> $lastLogfile 2>&1
backupRC=$?
# backupOK: the snapshot exists, forget may run and success is reported
backupOK=0
if [[ $backupRC == 0 ]]; then
    log "INFO" "Backup Successful"
    backupOK=1
elif [[ $backupRC == 3 ]]; then
    # restic exit code 3: snapshot was created, but some source files could not be read
    report_warning "Backup finished with warnings (status 3): snapshot was created, but some files could not be read. See lastrun.log for details."
    backupOK=1
else
    report_restic_error "backup" $backupRC
    unlock
    healthcheck /fail
fi

forgetRC=0
if [[ $backupOK == 1 ]] && [ -n "${RESTIC_FORGET_ARGS}" ]; then
    log "INFO" "Forget old snapshots based on RESTIC_FORGET_ARGS = ${RESTIC_FORGET_ARGS}"
    run_restic forget ${RESTIC_FORGET_ARGS} >> $lastLogfile 2>&1
    forgetRC=$?
    if [[ $forgetRC == 0 ]]; then
        log "INFO" "Finished restic forget"
    else
        report_restic_error "forget" $forgetRC
        unlock
        healthcheck /fail
    fi
fi

# success is only reported after backup AND forget are done
if [[ $backupOK == 1 && $forgetRC == 0 ]]; then
    healthcheck /0
fi

end=`date +%s`
log "INFO" "Finished Backup after $((end-start)) seconds"
echo "Finished Backup at $(date +"%Y-%m-%d %H:%M:%S") after $((end-start)) seconds" >> $lastLogfile

send_mail "Restic-Backup"

# /hooks/post-backup.sh (receives the restic exit code: 0 ok, 3 ok with unreadable files, 124/137 timeout, other = failed)
if [ -f "/hooks/post-backup.sh" ]; then
    log "INFO" "Starting post-backup script"
    /hooks/post-backup.sh $backupRC
    if [ $? -ne 0 ]; then
        log "ERROR" "post-backup.sh was not successful."
        exit 1
    fi
else
    log "DEBUG" "Post-backup script not found"
fi

# exit with the restic status, so that a manual run (docker exec ... backup) reports the failure
[[ $backupOK == 0 ]] && exit $backupRC
[[ $forgetRC != 0 ]] && exit $forgetRC
exit 0
