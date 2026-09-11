#!/usr/bin/env bash
#
# Fake restic for the tests. Mounted over /bin/restic to simulate hanging or failing restic commands.
# Behaviour is controlled by environment variables:
#   FAKE_HANG="backup forget"   commands that hang until they are killed
#   FAKE_IGNORE_TERM=1          hanging commands ignore SIGTERM (forces the SIGKILL of timeout -k)
#   FAKE_RC_backup=3            exit code of a command (default 0)

cmd=$1
echo "fake restic $*" >&2

if [[ " ${FAKE_HANG:-} " == *" ${cmd} "* ]]; then
    echo "fake restic ${cmd}: hanging"
    [ "${FAKE_IGNORE_TERM:-0}" = "1" ] && trap '' TERM
    while true; do sleep 1; done
fi

case "$cmd" in
    backup) echo "snapshot 0123abcd saved";;
    unlock) echo "successfully removed 1 locks";;
    ls)     # one snapshot with one file, enough for the restore test to pick a candidate
            echo '{"message_type":"snapshot","short_id":"0123abcd"}'
            echo '{"message_type":"node","type":"file","path":"/data/compose/file.txt","size":6,"mtime":"2020-01-01T00:00:00Z"}';;
esac

rc_var="FAKE_RC_${cmd}"
exit "${!rc_var:-0}"
