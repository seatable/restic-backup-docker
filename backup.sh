#!/usr/bin/env bash
#
# Backup script to save backup to repository and forgets old snapshots (execute manually or by CHECK_CRON schedule)
# - restic backup
# - restic forget

source /bin/log.sh

mkdir -p /var/log/restic
lastLogfile="/var/log/restic/lastrun.log"
backup_dir="/data"
start=`date +%s`

healthcheck() {
    suffix=$1
    if [ -n "$HEALTHCHECK_URL" ]; then
        log "INFO" "Reporting healthcheck $suffix ..."
        [[ ${1} == "/start" ]] && m="" || m=$(cat ${lastLogfile} | tail -n 300)
        # --max-time makes sure an unresponsive healthcheck server can never block the backup
        curl -fSsL --retry 3 --max-time 30 -X POST \
            --user-agent ${USER_AGENT} \
            --data-raw "$m" "${HEALTHCHECK_URL}${suffix}"
        if [ $? != 0 ]; then
            # A failed ping must never abort the backup itself. Just log it and go on.
            log "WARNING" "Reporting healthcheck $suffix failed (HEALTHCHECK_URL wrong or unreachable). Continuing anyway."
        fi
    else
        log "DEBUG" "No HEALTHCHECK_URL provided. Skipping healthcheck."
    fi
}

# Run a restic command, limited by RESTIC_TIMEOUT (0 disables the limit).
# Exit code is the one of restic, or 124 (SIGTERM) / 137 (SIGKILL) if the timeout was hit.
run_restic() {
    if [ -n "${RESTIC_TIMEOUT}" ]; then
        timeout -k 60 "${RESTIC_TIMEOUT}" restic "$@"
    else
        restic "$@"
    fi
}

# Remove the repository lock left behind by a failed or killed restic process.
# Always limited, a hanging unlock must not block the next scheduled run.
unlock() {
    timeout -k 30 10m restic unlock >> $lastLogfile 2>&1
}

# Log an error and add it to lastrun.log, so it is part of healthcheck and mail reports.
report_error() {
    log "ERROR" "$1"
    echo "ERROR: $1" >> $lastLogfile
}

# Log the failure of a restic command. Timeouts are reported explicitly.
report_restic_error() {
    cmd=$1
    rc=$2
    if [[ $rc == 124 || $rc == 137 ]]; then
        report_error "restic ${cmd} aborted by RESTIC_TIMEOUT (${RESTIC_TIMEOUT}): process was hanging and got killed, repository lock will be removed."
    else
        report_error "restic ${cmd} failed with status ${rc}"
    fi
}

send_mail() {
    if [ -n "${MSMTP_ARGS}" ]; then
        log "INFO" "Executing mail command"
        echo -e "Subject: Restic-Backup \n\n$(cat ${lastLogfile})" | msmtp ${MSMTP_ARGS}
        ms=$?
        if [[ $ms == 0 ]]; then
            log "INFO" "Mail notification successfully sent."
        else
            log "ERROR" "Sending mail notification FAILED."
        fi
    else
        log "DEBUG" "MSMTP_ARGS not defined. Therefore no mail notification."
    fi
}

# Abort the backup run before restic was started: report via healthcheck and mail, then exit.
abort() {
    report_error "$1"
    healthcheck /fail
    send_mail
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
if [[ $backupRC == 0 ]]; then
    log "INFO" "Backup Successful"
else
    report_restic_error "backup" $backupRC
    unlock
    healthcheck /fail
fi

forgetRC=0
if [[ $backupRC == 0 ]] && [ -n "${RESTIC_FORGET_ARGS}" ]; then
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
if [[ $backupRC == 0 && $forgetRC == 0 ]]; then
    healthcheck /0
fi

end=`date +%s`
log "INFO" "Finished Backup after $((end-start)) seconds"
echo "Finished Backup at $(date +"%Y-%m-%d %H:%M:%S") after $((end-start)) seconds" >> $lastLogfile

send_mail

# /hooks/post-backup.sh
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
[[ $backupRC != 0 ]] && exit $backupRC
[[ $forgetRC != 0 ]] && exit $forgetRC
exit 0
