#!/usr/bin/env bash
#
# Wrapper for the cron jobs (backup, check and prune).
# Runs the job under a lock, so that backup, check and prune never run at the same time.
# flock itself skips silently if the lock is held - this wrapper makes the skip visible in the log.

source /bin/log.sh

job=$1
if [[ ! "$job" =~ ^(backup|check|prune)$ ]]; then
    log "ERROR" "cron-run: unknown job '${job}'. Allowed values are backup, check or prune."
    exit 1
fi

/usr/bin/flock -n -E 99 /var/run/backup.lock /bin/${job}
rc=$?
if [ $rc -eq 99 ]; then
    log "ERROR" "Scheduled ${job} SKIPPED: the previous backup, check or prune is still running. If this persists, check for a hanging restic process (docker exec <container> ps aux)."
fi
exit $rc
