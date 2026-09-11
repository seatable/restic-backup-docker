#!/usr/bin/env bash
#
# Checks data integrity (execute manually or by CHECK_CRON schedule)
# - restic check

# shellcheck source=log.sh
source /bin/log.sh
# shellcheck source=functions.sh
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
log "DEBUG" "RESTORE_TEST: ${RESTORE_TEST}"
log "DEBUG" "RESTIC_REPOSITORY: ${RESTIC_REPOSITORY}"
log "DEBUG" "RESTIC_TIMEOUT: ${RESTIC_TIMEOUT}"

log "DEBUG" "Healthcheck start"
healthcheck /start


# shellcheck disable=SC2046  # the (possibly empty) argument must be word-split
run_restic check $(data_subset_arg) >> $lastLogfile 2>&1
checkRC=$?

if [[ $checkRC == 0 ]]; then
    log "INFO" "Check finished Successful"
else
    report_restic_error "check" $checkRC
    unlock
    healthcheck /fail
fi

# restore test: only after a successful check, a failure counts as failed check
jobRC=$checkRC
if [[ $checkRC == 0 ]] && [ "${RESTORE_TEST}" = "true" ]; then
    log "INFO" "Starting restore test"
    restore_test || jobRC=1
    [[ $jobRC != 0 ]] && healthcheck /fail
fi

if [[ $jobRC == 0 ]]; then
    healthcheck /0
fi

end=`date +%s`
log "INFO" "Finished Check after $((end-start)) seconds"
echo "Finished Check at $(date +"%Y-%m-%d %H:%M:%S") after $((end-start)) seconds" >> $lastLogfile

send_mail "Restic-Check"

# /hooks/post-check.sh (receives the exit code of restic check, or 1 if the restore test failed)
if [ -f "/hooks/post-check.sh" ]; then
    log "INFO" "Starting post-check script"
    /hooks/post-check.sh $jobRC
else
    log "DEBUG" "Post-check script not found"
fi

# exit with the job status, so that a manual run (docker exec ... check) reports the failure
exit $jobRC
