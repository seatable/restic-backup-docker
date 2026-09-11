#!/usr/bin/env bash
#
# Wrapper for the cron jobs (backup and check).
# Runs the job under a lock, so that backup and check never run at the same time.
# flock itself skips silently if the lock is held - this wrapper makes the skip visible in the log.

source /bin/log.sh

job=$1
if [[ ! "$job" =~ ^(backup|check)$ ]]; then
    log "ERROR" "cron-run: unknown job '${job}'. Allowed values are backup or check."
    exit 1
fi

/usr/bin/flock -n -E 99 /var/run/backup.lock /bin/${job}
rc=$?
if [ $rc -eq 99 ]; then
    log "ERROR" "Scheduled ${job} SKIPPED: the previous backup or check is still running. If this persists, check for a hanging restic process (docker exec <container> ps aux)."
fi
exit $rc
