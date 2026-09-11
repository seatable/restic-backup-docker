# Shared functions for the backup, check and prune jobs.
# Expects log.sh to be sourced before.

mkdir -p /var/log/restic
lastLogfile="/var/log/restic/lastrun.log"

# Report to the healthcheck server. Suffix is /start, /0 or /fail.
healthcheck() {
    suffix=$1
    if [ -n "$HEALTHCHECK_URL" ]; then
        log "INFO" "Reporting healthcheck $suffix ..."
        [[ ${1} == "/start" ]] && m="" || m=$(cat ${lastLogfile} | tail -n 300)
        # --max-time makes sure an unresponsive healthcheck server can never block the job
        curl -fSsL --retry 3 --max-time 30 -X POST \
            --user-agent ${USER_AGENT} \
            --data-raw "$m" "${HEALTHCHECK_URL}${suffix}"
        if [ $? != 0 ]; then
            # A failed ping must never abort the job itself. Just log it and go on.
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

# Log a warning and add it to lastrun.log, so it is part of healthcheck and mail reports.
report_warning() {
    log "WARNING" "$1"
    echo "WARNING: $1" >> $lastLogfile
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

# Send lastrun.log via mail, if MSMTP_ARGS is set. $1 is the subject.
send_mail() {
    subject=$1
    if [ -n "${MSMTP_ARGS}" ]; then
        log "INFO" "Executing mail command"
        echo -e "Subject: ${subject} \n\n$(cat ${lastLogfile})" | msmtp ${MSMTP_ARGS}
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
