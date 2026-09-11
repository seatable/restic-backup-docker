# shellcheck shell=bash
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

# Log an info message and add it to lastrun.log, so it is part of healthcheck and mail reports.
report_info() {
    log "INFO" "$1"
    echo "INFO: $1" >> $lastLogfile
}

# Print the --read-data-subset argument for restic check, derived from RESTIC_DATA_SUBSET.
# "rotate:N" reads a different 1/N part of the repository in every calendar week (ISO week number),
# so that all data is verified once every N weeks. "none" checks the structure only. Everything
# else (e.g. 1G, 10%, 2/5) is passed to restic unchanged.
data_subset_arg() {
    local subset="${RESTIC_DATA_SUBSET}"
    if [[ "$subset" =~ ^rotate:([0-9]+)$ ]]; then
        local total=${BASH_REMATCH[1]}
        local week=$((10#$(date +%V)))
        local part=$(( (week - 1) % total + 1 ))
        log "INFO" "Check reads part ${part}/${total} of the repository data (RESTIC_DATA_SUBSET=${subset}, week ${week})"
        echo "--read-data-subset=${part}/${total}"
    elif [ -z "$subset" ] || [ "$subset" = "none" ]; then
        echo ""
    else
        echo "--read-data-subset=${subset}"
    fi
}

# Restore test: restore a random file of the latest snapshot and compare it with the original below /data.
# Proves that the restore path works end to end. Returns 0 on success, 1 on failure.
restore_test() {
    local target="/tmp/restore-test"
    local max_size=$((100 * 1024 * 1024))
    rm -rf "$target"

    # list the latest snapshot: regular files, 0 < size <= max_size, no glob characters in the path
    local listing snapshot candidates
    listing=$(run_restic ls latest --json 2>> "$lastLogfile")
    if [ $? -ne 0 ] || [ -z "$listing" ]; then
        report_error "Restore test FAILED: could not list the latest snapshot (see lastrun.log)"
        return 1
    fi
    snapshot=$(echo "$listing" | jq -r 'select(.message_type=="snapshot") | .short_id' | head -n1)
    candidates=$(echo "$listing" | jq -r --argjson max "$max_size"         'select(.message_type=="node" and .type=="file" and .size>0 and .size<=$max)
         | select(.path | test("[*?\\[\\]\\\\]") | not)
         | [.path, .size, .mtime] | @tsv' | shuf -n 3)
    if [ -z "$candidates" ]; then
        report_warning "Restore test skipped: no regular file up to 100 MiB found in snapshot ${snapshot}"
        return 0
    fi

    # prefer a file that is unchanged since the snapshot, so that the checksum can be compared
    local path size mtime chosen="" chosen_size="" compare=0
    while IFS=$'\t' read -r path size mtime; do
        [ -z "$chosen" ] && { chosen="$path"; chosen_size="$size"; }
        if [ -f "$path" ] && [ "$(stat -c %s "$path")" = "$size" ] && [ "$(stat -c %Y "$path")" = "$(date -d "$mtime" +%s)" ]; then
            chosen="$path"; chosen_size="$size"; compare=1
            break
        fi
    done <<< "$candidates"
    local human
    human=$(numfmt --to=iec-i --suffix=B "$chosen_size")

    run_restic restore latest --include "$chosen" --target "$target" >> "$lastLogfile" 2>&1
    local rc=$?
    if [ $rc -ne 0 ]; then
        report_error "Restore test FAILED: restic restore of ${chosen} exited with status ${rc} (see lastrun.log)"
        rm -rf "$target"
        return 1
    fi
    if [ ! -f "${target}${chosen}" ]; then
        report_error "Restore test FAILED: restic restore succeeded but ${chosen} was not written to the target"
        rm -rf "$target"
        return 1
    fi

    if [ $compare = 1 ]; then
        local sum_restored sum_original
        sum_restored=$(sha256sum "${target}${chosen}" | cut -d' ' -f1)
        sum_original=$(sha256sum "$chosen" | cut -d' ' -f1)
        if [ "$sum_restored" != "$sum_original" ]; then
            report_error "Restore test FAILED: checksum of restored ${chosen} differs from the original"
            rm -rf "$target"
            return 1
        fi
        report_info "Restore test: restored ${chosen} (${human}) from snapshot ${snapshot}, checksum matches the original"
    else
        report_info "Restore test: restored ${chosen} (${human}) from snapshot ${snapshot}, original changed since the snapshot, checksum not compared"
    fi
    rm -rf "$target"
    return 0
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
