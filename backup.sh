#!/bin/sh

lastLogfile="/var/log/backup-last.log"
lastMailLogfile="/var/log/mail-last.log"
backup_dir="/data"

copyErrorLog() {
  cp ${lastLogfile} /var/log/backup-error-last.log
}

logLast() {
  echo "$1" >> ${lastLogfile}
}

healthcheck() {
    suffix=$1
    if [ -n "$HEALTHCHECK_URL" ]; then
        echo "Reporting healthcheck $suffix ..."
        [[ ${1} == "/start" ]] && m="" || m=$(cat ${lastLogfile} | tail -n 100)
        curl -fSsL --retry 3 -X POST \
            --user-agent "seatable-restic/1.0.0" \
            --data-raw "$m" "${HEALTHCHECK_URL}${suffix}"
        echo
        if [ $? != 0 ]; then
            echo "HEALTHCHECK_URL seems to be wrong..."
            exit 1
        fi
    else
        echo "No HEALTHCHECK_URL provided. Skipping healthcheck."
    fi
}

/bin/pre-default.sh

if [ -f "/hooks/pre-backup.sh" ]; then
    echo "Starting pre-backup script ..."
    /hooks/pre-backup.sh
else
    echo "Pre-backup script not found ..."
fi

start=`date +%s`
rm -f ${lastLogfile} ${lastMailLogfile}
echo "Starting Backup at $(date +"%Y-%m-%d %H:%M:%S")"
echo "Starting Backup at $(date)" >> ${lastLogfile}
logLast "BACKUP_CRON: ${BACKUP_CRON}"
logLast "RESTIC_TAG: ${RESTIC_TAG}"
logLast "RESTIC_FORGET_ARGS: ${RESTIC_FORGET_ARGS}"
logLast "RESTIC_JOB_ARGS: ${RESTIC_JOB_ARGS}"
logLast "RESTIC_REPOSITORY: ${RESTIC_REPOSITORY}"
logLast ""
logLast "Directory tree:"
tree -a -P .exclude_from_backup -L 4 ${backup_dir} | tee -a "${lastLogfile}"
healthcheck /start

# Do not save full backup log to logfile but to backup-last.log
restic backup ${backup_dir} ${RESTIC_JOB_ARGS} --tag=${RESTIC_TAG?"Missing environment variable RESTIC_TAG"} >> ${lastLogfile} 2>&1
backupRC=$?
logLast "Finished backup at $(date)"
if [[ $backupRC == 0 ]]; then
    echo "Backup Successful"
    healthcheck /0
else
    echo "Backup Failed with Status ${backupRC}"
    restic unlock
    healthcheck /fail    
fi

if [[ $backupRC == 0 ]] && [ -n "${RESTIC_FORGET_ARGS}" ]; then
    echo "Forget about old snapshots based on RESTIC_FORGET_ARGS = ${RESTIC_FORGET_ARGS}"
    restic forget ${RESTIC_FORGET_ARGS} >> ${lastLogfile} 2>&1
    rc=$?
    logLast "Finished forget at $(date)"
    if [[ $rc == 0 ]]; then
        echo "Forget Successful"
    else
        echo "Forget Failed with Status ${rc}"
        restic unlock
        copyErrorLog
        healthcheck /fail
    fi
fi

end=`date +%s`
echo "Finished Backup at $(date +"%Y-%m-%d %H:%M:%S") after $((end-start)) seconds"

if [ -n "${MAILX_ARGS}" ]; then
    sh -c "mail -v -S sendwait ${MAILX_ARGS} < ${lastLogfile} > ${lastMailLogfile} 2>&1"
    if [ $? == 0 ]; then
        echo "Mail notification successfully sent."
    else
        echo "Sending mail notification FAILED. Check ${lastMailLogfile} for further information."
    fi
fi

if [ -f "/hooks/post-backup.sh" ]; then
    echo "Starting post-backup script ..."
    /hooks/post-backup.sh $backupRC
else
    echo "Post-backup script not found ..."
fi