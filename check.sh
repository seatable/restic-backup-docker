#!/usr/bin/env bash
#
# Checks data integrity (execute manually or by CHECK_CRON schedule)
# - restic check

source /bin/log.sh
source /bin/functions.sh

start=`date +%s`

# /hooks/pre-check.sh
if [ -f "/hooks/pre-check.sh" ]; then
    log "INFO" "Starting pre-check script"
    /hooks/pre-check.sh
else
    log "DEBUG" "Pre-check script not found"
fi


log "INFO" "Starting Check"
echo "Starting Check at $(date +"%Y-%m-%d %H:%M:%S")" > $lastLogfile
log "DEBUG" "CHECK_CRON: ${CHECK_CRON}"
log "DEBUG" "RESTIC_DATA_SUBSET: ${RESTIC_DATA_SUBSET}"
log "DEBUG" "RESTIC_REPOSITORY: ${RESTIC_REPOSITORY}"
log "DEBUG" "RESTIC_TIMEOUT: ${RESTIC_TIMEOUT}"

log "DEBUG" "Healthcheck start"
healthcheck /start


if [ -n "${RESTIC_DATA_SUBSET}" ]; then
    run_restic check --read-data-subset=${RESTIC_DATA_SUBSET} >> $lastLogfile 2>&1
    checkRC=$?
else
    run_restic check >> ${lastLogfile} 2>&1
    checkRC=$?
fi

if [[ $checkRC == 0 ]]; then
    log "INFO" "Check finished Successful"
    healthcheck /0
else
    report_restic_error "check" $checkRC
    unlock
    healthcheck /fail
fi

end=`date +%s`
log "INFO" "Finished Check after $((end-start)) seconds"
echo "Finished Check at $(date +"%Y-%m-%d %H:%M:%S") after $((end-start)) seconds" >> $lastLogfile

send_mail "Restic-Check"

# /hooks/post-check.sh
if [ -f "/hooks/post-check.sh" ]; then
    log "INFO" "Starting post-check script"
    /hooks/post-check.sh $checkRC
else
    log "DEBUG" "Post-check script not found"
fi

# exit with the restic status, so that a manual run (docker exec ... check) reports the failure
exit $checkRC
