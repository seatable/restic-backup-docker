#!/usr/bin/env bash
#
# Removes unreferenced data from the repository (execute manually or by PRUNE_CRON schedule)
# - restic prune
#
# Use this job instead of --prune in RESTIC_FORGET_ARGS. Prune is the most expensive restic
# operation (downloads and rewrites pack files), it does not need to run with every backup.

source /bin/log.sh
source /bin/functions.sh

start=`date +%s`

# /hooks/pre-prune.sh
if [ -f "/hooks/pre-prune.sh" ]; then
    log "INFO" "Starting pre-prune script"
    /hooks/pre-prune.sh
else
    log "DEBUG" "Pre-prune script not found"
fi


log "INFO" "Starting Prune"
echo "Starting Prune at $(date +"%Y-%m-%d %H:%M:%S")" > $lastLogfile
log "DEBUG" "PRUNE_CRON: ${PRUNE_CRON}"
log "DEBUG" "RESTIC_PRUNE_ARGS: ${RESTIC_PRUNE_ARGS}"
log "DEBUG" "RESTIC_REPOSITORY: ${RESTIC_REPOSITORY}"
log "DEBUG" "RESTIC_TIMEOUT: ${RESTIC_TIMEOUT}"

log "DEBUG" "Healthcheck start"
healthcheck /start


run_restic prune ${RESTIC_PRUNE_ARGS} >> $lastLogfile 2>&1
pruneRC=$?

if [[ $pruneRC == 0 ]]; then
    log "INFO" "Prune finished Successful"
    healthcheck /0
else
    report_restic_error "prune" $pruneRC
    unlock
    healthcheck /fail
fi

end=`date +%s`
log "INFO" "Finished Prune after $((end-start)) seconds"
echo "Finished Prune at $(date +"%Y-%m-%d %H:%M:%S") after $((end-start)) seconds" >> $lastLogfile

send_mail "Restic-Prune"

# /hooks/post-prune.sh
if [ -f "/hooks/post-prune.sh" ]; then
    log "INFO" "Starting post-prune script"
    /hooks/post-prune.sh $pruneRC
else
    log "DEBUG" "Post-prune script not found"
fi

# exit with the restic status, so that a manual run (docker exec ... prune) reports the failure
exit $pruneRC
