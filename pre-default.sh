#!/usr/bin/env bash
#
# SeaTable specific pre-backup script.
# - It dumps the mariadb database
# - It forces backup of big data

set -eo pipefail

source /bin/log.sh

if [ "${SEATABLE_DATABASE_DUMP}" == true ]; then
    log "INFO" "Dump the database"
    mkdir -p /data/seatable-dumps
    /usr/local/bin/docker exec ${SEATABLE_DATABASE_HOST} mysqldump -u${SEATABLE_DATABASE_USER} -p${SEATABLE_DATABASE_PASSWORD} --opt ccnet_db > /data/seatable-dumps/ccnet.dump
    /usr/local/bin/docker exec ${SEATABLE_DATABASE_HOST} mysqldump -u${SEATABLE_DATABASE_USER} -p${SEATABLE_DATABASE_PASSWORD} --opt seafile_db > /data/seatable-dumps/seafile.dump
    /usr/local/bin/docker exec ${SEATABLE_DATABASE_HOST} mysqldump -u${SEATABLE_DATABASE_USER} -p${SEATABLE_DATABASE_PASSWORD} --opt dtable_db > /data/seatable-dumps/dtable.dump
    log "INFO" "Dump finished"
else
    log "DEBUG" "Skip database dump"
fi

if [ "${SEATABLE_BIGDATA_DUMP}" == true ]; then
    log "INFO" "Dump big data"
    /usr/local/bin/docker exec ${SEATABLE_BIGDATA_HOST} /opt/seatable/scripts/seatable.sh backup-all
    log "INFO" "Dump finished"
else
    log "DEBUG" "Skip big data dump"
fi
