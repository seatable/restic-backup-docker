#!/usr/bin/env bash
#
# Checks data integrity (execute manually or by CHECK_CRON schedule)
# - restic check

set -eo pipefail

source /bin/log.sh

lastLogfile="/var/log/restic/lastrun.log"
start=`date +%s`

healthcheck() {
    suffix=$1
    if [ -n "$HEALTHCHECK_URL" ]; then
        log "INFO" "Reporting healthcheck $suffix ..."
        [[ ${1} == "/start" ]] && m="" || m=$(cat ${lastLogfile} | tail -n 100)
        set +e
        curl -fSsL --retry 3 -X POST \
            --user-agent "seatable-restic/1.0.0" \
            --data-raw "$m" "${HEALTHCHECK_URL}${suffix}"
        if [ $? != 0 ]; then
            log "ERROR" "HEALTHCHECK_URL seems to be wrong..."
            exit 1
        fi
        set -e
    else
        log "DEBUG" "No HEALTHCHECK_URL provided. Skipping healthcheck."
    fi
}

# /hooks/pre-check.sh
if [ -f "/hooks/pre-check.sh" ]; then
    log "INFO" "Starting pre-check script"
    /hooks/pre-check.sh
else
    log "DEBUG" "Pre-check script not found"
fi


log "INFO" "Starting Check"
echo "Starting Check" > $lastLogfile
log "DEBUG" "BACKUP_CRON: ${BACKUP_CRON}"
log "DEBUG" "RESTIC_TAG: ${RESTIC_TAG}"
log "DEBUG" "RESTIC_FORGET_ARGS: ${RESTIC_FORGET_ARGS}"
log "DEBUG" "RESTIC_JOB_ARGS: ${RESTIC_JOB_ARGS}"
log "DEBUG" "RESTIC_REPOSITORY: ${RESTIC_REPOSITORY}"

log "DEBUG" "Healthcheck start"
healthcheck /start


# Do not save full check log to logfile but to check-last.log
if [ -n "${RESTIC_DATA_SUBSET}" ]; then
    set +e
    restic check --read-data-subset=${RESTIC_DATA_SUBSET} >> $lastLogfile 2>&1
    checkRC=$?
    set -e
else
    set +e
    restic check >> ${lastLogfile} 2>&1
    checkRC=$?
    set -e
fi

if [[ $checkRC == 0 ]]; then
    log "INFO" "Check finished Successful"
    healthcheck /0
else
    log "ERROR" "Check Failed with Status ${checkRC}"
    restic unlock >> $lastLogfile 2>&1
    healthcheck /fail
fi

end=`date +%s`
log "INFO" "Finished Check after $((end-start)) seconds"

if [ -n "${MAILX_ARGS}" ]; then
    log "INFO" "Executing mail command"
    set +e
    sh -c "mail -v -S sendwait ${MAILX_ARGS} < $(cat ${lastLogfile} | tail -n 100) "
    $ms=$?
    set -e
    if [ $ms == 0 ]; then
        log "INFO" "Mail notification successfully sent."
    else
        log "ERROR" "Sending mail notification FAILED."
    fi
else
    log "DEBUG" "MAILX_ARGS not defined. Therefore no mail notification"
fi

# /hooks/post-check.sh
if [ -f "/hooks/post-check.sh" ]; then
    log "INFO" "Starting post-check script"
    /hooks/post-check.sh $backupRC
else
    log "DEBUG" "Post-check script not found"
fi
