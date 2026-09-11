#!/usr/bin/env bash
#
# Test suite for the restic-backup container. Tests the job scripts (backup, check, prune, cron-run, entry.sh)
# against the built image: success paths with the real restic and a local repository, failure paths with a
# fake restic (tests/fake-restic.sh) and a mock healthcheck server (tests/healthcheck-mock.py).
#
# Usage:
#   tests/run.sh                          build the image from the repository and test it
#   IMAGE=my/image:tag tests/run.sh       test an existing image (no build)
#
# Requirements on the host: docker, python3, curl

set -u
cd "$(dirname "$0")/.." || exit 1

BUILD_IMAGE="restic-backup-test:local"
IMAGE="${IMAGE:-}"
HC_PORT="${HC_PORT:-18765}"
HC_URL="http://127.0.0.1:${HC_PORT}/ping"
TMP=$(mktemp -d)
HC_LOG="$TMP/hc.log"
FAKE="$PWD/tests/fake-restic.sh"
PASS=0
FAIL=0
FAILED_TESTS=()

# ---------------------------------------------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------------------------------------------

cleanup() {
    [ -n "${HC_PID:-}" ] && kill "$HC_PID" 2>/dev/null
    docker ps -aq --filter "name=rbt-" | xargs -r docker rm -f >/dev/null 2>&1
    # files created by root inside the containers
    docker run --rm -v "$TMP:/t" --entrypoint /bin/rm "$IMAGE" -rf /t/data /t/repo /t/hooks /t/dump >/dev/null 2>&1
    rm -rf "$TMP"
}
trap cleanup EXIT

# run_in_image <name> <time limit in s> [docker run options...] -- <bash command>
# Runs a bash command inside the image (bypassing entry.sh). Output goes to $OUT.
# The time limit is a safety net of the test itself: a hanging container must never block the suite
# (--init makes sure the container reacts to the signal, -k kills the docker client if it does not).
run_in_image() {
    local name="rbt-$1" limit=$2
    shift 2
    local args=()
    while [ "$1" != "--" ]; do args+=("$1"); shift; done
    shift
    OUT=$(timeout -k 5 "$limit" docker run --init --name "$name" --network host \
        -e RESTIC_REPOSITORY=/local -e RESTIC_PASSWORD=test -e HEALTHCHECK_URL="$HC_URL" \
        "${args[@]}" --entrypoint /bin/bash "$IMAGE" -c "$*" 2>&1)
    docker rm -f "$name" >/dev/null 2>&1
}

# exit code of the command inside the container ("EXIT=<n>" printed by the command), "none" if it never finished
exit_code() {
    local code
    code=$(echo "$OUT" | grep -oE 'EXIT=[0-9]+' | tail -n1 | cut -d= -f2)
    echo "${code:-none}"
}

# the healthcheck pings received so far, in order, e.g. "/ping/start /ping/0"
pings() {
    cut -d' ' -f1 "$HC_LOG" | tr '\n' ' ' | sed 's/ $//'
}

assert_eq() {           # assert_eq <what> <actual> <expected>
    [ "$2" == "$3" ] && return 0
    echo "  $1: expected '$3', got '$2'"
    return 1
}
assert_contains() {     # assert_contains <what> <haystack> <needle>
    [[ "$2" == *"$3"* ]] && return 0
    echo "  $1: missing '$3'"
    return 1
}
assert_not_contains() { # assert_not_contains <what> <haystack> <needle>
    [[ "$2" != *"$3"* ]] && return 0
    echo "  $1: must not contain '$3'"
    return 1
}

# test_case <description> <function>
test_case() {
    : > "$HC_LOG"
    printf '%-75s' "* $1"
    local out
    if out=$($2 2>&1); then
        PASS=$((PASS + 1))
        echo "PASS"
    else
        FAIL=$((FAIL + 1))
        FAILED_TESTS+=("$1")
        echo "FAIL"
        echo "$out" | sed 's/^/    /'
    fi
}

# called by a test after a failed assertion: show the container output and return 1
show_output() {
    echo "  --- container output (last 25 lines):"
    echo "$OUT" | tail -n 25 | sed 's/^/  | /'
    return 1
}

# ---------------------------------------------------------------------------------------------------------------
# tests
# ---------------------------------------------------------------------------------------------------------------

test_real_run() {
    mkdir -p "$TMP/repo/real"
    run_in_image real 120 -v "$TMP/data:/data:ro" -v "$TMP/repo/real:/local" \
        -e RESTIC_FORGET_ARGS="--keep-last 1" -e RESTIC_PRUNE_ARGS="--max-unused 0" -- '
        restic init -q >/dev/null 2>&1
        /bin/backup || exit 10
        /bin/backup || exit 11
        /bin/prune  || exit 12
        /bin/check  || exit 13
        echo "SNAPSHOTS=$(restic snapshots --json | grep -o short_id | wc -l)"
        echo "EXIT=0"'
    local ok=0
    assert_eq "exit code" "$(exit_code)" "0" || ok=1
    assert_contains "output" "$OUT" "Finished restic forget" || ok=1
    assert_contains "output" "$OUT" "Prune finished Successful" || ok=1
    assert_contains "output" "$OUT" "Check finished Successful" || ok=1
    assert_contains "output" "$OUT" "SNAPSHOTS=1" || ok=1
    assert_eq "pings" "$(pings)" "/ping/start /ping/0 /ping/start /ping/0 /ping/start /ping/0 /ping/start /ping/0" || ok=1
    [ $ok = 0 ] || show_output
}

test_hanging_forget_timeout() {
    run_in_image hang-forget 40 -v "$FAKE:/bin/restic:ro" -e FAKE_HANG=forget \
        -e RESTIC_TIMEOUT=3s -e RESTIC_FORGET_ARGS="--prune" -- '/bin/backup; echo "EXIT=$?"'
    local ok=0
    assert_eq "exit code" "$(exit_code)" "124" || ok=1
    assert_contains "output" "$OUT" "restic forget aborted by RESTIC_TIMEOUT (3s)" || ok=1
    assert_eq "pings" "$(pings)" "/ping/start /ping/fail" || ok=1
    assert_contains "fail body" "$(cat "$HC_LOG")" "/ping/fail | successfully removed 1 locks" || ok=1
    [ $ok = 0 ] || show_output
}

test_hanging_backup_ignores_sigterm() {
    run_in_image hang-kill 120 -v "$FAKE:/bin/restic:ro" -e FAKE_HANG=backup -e FAKE_IGNORE_TERM=1 \
        -e RESTIC_TIMEOUT=2s -- '/bin/backup; echo "EXIT=$?"'
    local ok=0 code
    code=$(exit_code)
    [[ "$code" == "124" || "$code" == "137" ]] || { echo "  exit code: expected 124 or 137, got '$code'"; ok=1; }
    assert_contains "output" "$OUT" "restic backup aborted by RESTIC_TIMEOUT (2s)" || ok=1
    assert_eq "pings" "$(pings)" "/ping/start /ping/fail" || ok=1
    [ $ok = 0 ] || show_output
}

test_prehook_failure_is_reported() {
    mkdir -p "$TMP/hooks"
    printf '#!/usr/bin/env bash\necho "simulated hook failure"\nexit 1\n' > "$TMP/hooks/pre-backup.sh"
    chmod +x "$TMP/hooks/pre-backup.sh"
    run_in_image prehook 30 -v "$FAKE:/bin/restic:ro" -v "$TMP/hooks:/hooks:ro" -- '/bin/backup; echo "EXIT=$?"'
    local ok=0
    assert_eq "exit code" "$(exit_code)" "1" || ok=1
    assert_contains "output" "$OUT" "pre-backup.sh was not successful" || ok=1
    assert_not_contains "output" "$OUT" "Start the restic backup" || ok=1
    assert_eq "pings" "$(pings)" "/ping/start /ping/fail" || ok=1
    assert_contains "fail body" "$(cat "$HC_LOG")" "/ping/fail | ERROR: pre-backup.sh was not successful" || ok=1
    [ $ok = 0 ] || show_output
}

test_unreachable_healthcheck_does_not_abort() {
    mkdir -p "$TMP/repo/hc"
    run_in_image hc-down 60 -v "$TMP/data:/data:ro" -v "$TMP/repo/hc:/local" \
        -e HEALTHCHECK_URL="http://127.0.0.1:1/ping" -- '
        restic init -q >/dev/null 2>&1
        /bin/backup; echo "EXIT=$?"
        echo "SNAPSHOTS=$(restic snapshots --json | grep -o short_id | wc -l)"'
    local ok=0
    assert_eq "exit code" "$(exit_code)" "0" || ok=1
    assert_contains "output" "$OUT" "[WARNING] Reporting healthcheck /start failed" || ok=1
    assert_contains "output" "$OUT" "Backup Successful" || ok=1
    assert_contains "output" "$OUT" "SNAPSHOTS=1" || ok=1
    [ $ok = 0 ] || show_output
}

test_skipped_job_is_logged() {
    run_in_image lock 40 -v "$FAKE:/bin/restic:ro" -e FAKE_HANG=backup -e RESTIC_TIMEOUT=5s -- '
        /bin/cron-run backup >/dev/null 2>&1 &
        sleep 1
        /bin/cron-run check; echo "EXIT=$?"
        wait'
    local ok=0
    assert_eq "exit code" "$(exit_code)" "99" || ok=1
    assert_contains "output" "$OUT" "[ERROR] Scheduled check SKIPPED" || ok=1
    [ $ok = 0 ] || show_output
}

test_backup_exit_3_is_warning() {
    run_in_image exit3 30 -v "$FAKE:/bin/restic:ro" -e FAKE_RC_backup=3 \
        -e RESTIC_FORGET_ARGS="--keep-last 1" -- '/bin/backup; echo "EXIT=$?"'
    local ok=0
    assert_eq "exit code" "$(exit_code)" "0" || ok=1
    assert_contains "output" "$OUT" "[WARNING] Backup finished with warnings (status 3)" || ok=1
    assert_contains "output" "$OUT" "Finished restic forget" || ok=1
    assert_eq "pings" "$(pings)" "/ping/start /ping/0" || ok=1
    [ $ok = 0 ] || show_output
}

test_backup_failure_exit_code() {
    run_in_image fail 30 -v "$FAKE:/bin/restic:ro" -e FAKE_RC_backup=1 \
        -e RESTIC_FORGET_ARGS="--keep-last 1" -- '/bin/backup; echo "EXIT=$?"'
    local ok=0
    assert_eq "exit code" "$(exit_code)" "1" || ok=1
    assert_contains "output" "$OUT" "restic backup failed with status 1" || ok=1
    assert_not_contains "output" "$OUT" "Forget old snapshots" || ok=1
    assert_eq "pings" "$(pings)" "/ping/start /ping/fail" || ok=1
    [ $ok = 0 ] || show_output
}

test_entry_rejects_invalid_timeout() {
    OUT=$(timeout 30 docker run --rm --name rbt-entry-invalid -e RESTIC_REPOSITORY=/local -e RESTIC_PASSWORD=test \
        -e RESTIC_TIMEOUT="48 hours" "$IMAGE" true 2>&1; echo "EXIT=$?")
    local ok=0
    assert_eq "exit code" "$(exit_code)" "1" || ok=1
    assert_contains "output" "$OUT" "Invalid value for RESTIC_TIMEOUT" || ok=1
    [ $ok = 0 ] || show_output
}

test_entry_crontab_and_version() {
    OUT=$(timeout 30 docker run --rm --name rbt-entry-cron -e RESTIC_REPOSITORY=/local -e RESTIC_PASSWORD=test \
        -e RESTIC_TIMEOUT=0 -e PRUNE_CRON="45 3 * * 0" "$IMAGE" cat /etc/crontab 2>&1; echo "EXIT=$?")
    local ok=0
    assert_eq "exit code" "$(exit_code)" "0" || ok=1
    assert_contains "output" "$OUT" "Starting the restic-backup container (version " || ok=1
    assert_contains "crontab" "$OUT" "20 2 * * * root /bin/cron-run backup" || ok=1
    assert_contains "crontab" "$OUT" "40 3 * * 6 root /bin/cron-run check" || ok=1
    assert_contains "crontab" "$OUT" "45 3 * * 0 root /bin/cron-run prune" || ok=1
    [ $ok = 0 ] || show_output
}

test_cron_runs_backup_with_environment() {
    mkdir -p "$TMP/repo/cron"
    docker run -d --name rbt-cron --network host --init -v "$TMP/data:/data:ro" -v "$TMP/repo/cron:/local" \
        -e RESTIC_REPOSITORY=/local -e RESTIC_PASSWORD=test -e HEALTHCHECK_URL="$HC_URL" \
        -e LOG_LEVEL=DEBUG -e RESTIC_TIMEOUT=12h -e BACKUP_CRON="* * * * *" "$IMAGE" >/dev/null

    for _ in $(seq 1 90); do
        docker logs rbt-cron 2>&1 | grep -q "Finished Backup" && break
        sleep 1
    done
    OUT=$(docker logs rbt-cron 2>&1)
    docker rm -f rbt-cron >/dev/null 2>&1
    local ok=0
    assert_contains "output" "$OUT" "Finished Backup" || ok=1
    # the DEBUG line of the backup job proves that the environment reached the cron job
    assert_contains "output" "$(echo "$OUT" | sed -n '/Starting Backup/,$p')" "RESTIC_TIMEOUT: 12h" || ok=1
    assert_eq "pings" "$(pings)" "/ping/start /ping/0" || ok=1
    [ $ok = 0 ] || show_output
}

test_database_dump() {
    docker run -d --name rbt-mariadb -e MARIADB_ROOT_PASSWORD=s3cret -e MARIADB_DATABASE=testdb mariadb:11 >/dev/null

    for _ in $(seq 1 60); do
        docker exec rbt-mariadb mariadb -uroot -ps3cret -e "select 1" >/dev/null 2>&1 && break
        sleep 1
    done
    docker exec rbt-mariadb mariadb -uroot -ps3cret testdb -e "create table t(id int); insert into t values (1),(2);"
    mkdir -p "$TMP/dump"
    run_in_image dump 60 -v /var/run/docker.sock:/var/run/docker.sock -v "$TMP/dump:/data" \
        -e DATABASE_DUMP=true -e DATABASE_HOST=rbt-mariadb -e DATABASE_PASSWORD=s3cret -e DATABASE_LIST=testdb -- '
        /bin/pre-default.sh; echo "EXIT=$?"
        echo "INSERTS=$(grep -c "INSERT INTO" /data/database-dumps/testdb.dump)"'
    docker rm -f rbt-mariadb >/dev/null 2>&1
    local ok=0
    assert_eq "exit code" "$(exit_code)" "0" || ok=1
    assert_contains "output" "$OUT" "Dump finished" || ok=1
    assert_contains "output" "$OUT" "INSERTS=1" || ok=1
    [ $ok = 0 ] || show_output
}

# ---------------------------------------------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------------------------------------------

if [ -z "$IMAGE" ]; then
    IMAGE="$BUILD_IMAGE"
    echo "Building image $IMAGE ..."
    docker build -q -t "$IMAGE" . >/dev/null || { echo "BUILD FAILED"; exit 1; }
fi
echo "Testing image: $IMAGE"
echo

mkdir -p "$TMP/data/compose"
echo "hello" > "$TMP/data/compose/file.txt"

python3 tests/healthcheck-mock.py "$HC_PORT" "$HC_LOG" &
HC_PID=$!
for _ in $(seq 1 20); do curl -s -m 1 -o /dev/null "http://127.0.0.1:${HC_PORT}/" && break; sleep 0.5; done
: > "$HC_LOG"

test_case "backup, forget, prune and check with real restic"            test_real_run
test_case "hanging forget is killed by RESTIC_TIMEOUT, /0 is not sent"  test_hanging_forget_timeout
test_case "hanging backup ignoring SIGTERM is killed with SIGKILL"      test_hanging_backup_ignores_sigterm
test_case "failing pre-backup hook reports /fail"                       test_prehook_failure_is_reported
test_case "unreachable healthcheck server does not abort the backup"    test_unreachable_healthcheck_does_not_abort
test_case "job scheduled while another one runs is logged as skipped"   test_skipped_job_is_logged
test_case "backup exit code 3 is a warning, forget runs, /0 is sent"    test_backup_exit_3_is_warning
test_case "failed backup skips forget, sends /fail, exits non-zero"     test_backup_failure_exit_code
test_case "entry.sh rejects an invalid RESTIC_TIMEOUT"                  test_entry_rejects_invalid_timeout
test_case "entry.sh logs the version and writes the crontab"            test_entry_crontab_and_version
test_case "cron executes the backup with the container environment"     test_cron_runs_backup_with_environment
test_case "database dump via docker exec"                               test_database_dump

echo
echo "$PASS passed, $FAIL failed"
if [ $FAIL -gt 0 ]; then
    printf '  - %s\n' "${FAILED_TESTS[@]}"
    exit 1
fi
