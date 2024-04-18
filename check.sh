#!/usr/bin/env bash
#
# description of the script

set -euo pipefail

#

lastLogfile="/var/log/check-last.log"
lastMailLogfile="/var/log/check-mail-last.log"

copyErrorLog() {
  cp ${lastLogfile} /var/log/check-error-last.log
}

logLast() {
  echo "$1" >> ${lastLogfile}
}

if [ -f "/hooks/pre-check.sh" ]; then
    echo "Starting pre-check script ..."
    /hooks/pre-check.sh
else
    echo "Pre-check script not found ..."
fi

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

start=`date +%s`
rm -f ${lastLogfile} ${lastMailLogfile}
echo "Starting Check at $(date +"%Y-%m-%d %H:%M:%S")"
echo "Starting Check at $(date)" >> ${lastLogfile}
logLast "CHECK_CRON: ${CHECK_CRON}"
logLast "RESTIC_DATA_SUBSET: ${RESTIC_DATA_SUBSET}"
logLast "RESTIC_REPOSITORY: ${RESTIC_REPOSITORY}"
healthcheck /start

# Do not save full check log to logfile but to check-last.log
if [ -n "${RESTIC_DATA_SUBSET}" ]; then
    restic check --read-data-subset=${RESTIC_DATA_SUBSET} >> ${lastLogfile} 2>&1
else
    restic check >> ${lastLogfile} 2>&1
fi
checkRC=$?
logLast "Finished check at $(date)"
if [[ $checkRC == 0 ]]; then
    echo "Check Successful"
    healthcheck /0
else
    echo "Check Failed with Status ${checkRC}"
    restic unlock
    copyErrorLog
    healthcheck /fail
fi

end=`date +%s`
echo "Finished Check at $(date +"%Y-%m-%d %H:%M:%S") after $((end-start)) seconds"

if [ -n "${MAILX_ARGS}" ]; then
    sh -c "mail -v -S sendwait ${MAILX_ARGS} < ${lastLogfile} > ${lastMailLogfile} 2>&1"
    if [ $? == 0 ]; then
        echo "Mail notification successfully sent."
    else
        echo "Sending mail notification FAILED. Check ${lastMailLogfile} for further information."
    fi
fi

if [ -f "/hooks/post-check.sh" ]; then
    echo "Starting post-check script ..."
    /hooks/post-check.sh $checkRC
else
    echo "Post-check script not found ..."
fi
