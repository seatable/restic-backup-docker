#!/usr/bin/env bash
#
# General pre-backup script for mysql/mariadb databases
# SeaTable specific pre-backup script to backup big data

set -eo pipefail

source /bin/log.sh

# DATABASE DUMP
if [ "${DATABASE_DUMP}" == true ] || [ "${SEATABLE_DATABASE_DUMP}" == true ]; then
    log "INFO" "Dump the database (mariadb or mysql)"
    mkdir -p /data/database-dumps
    if [ -n "${DATABASE_LIST}" ]; then
        log "DEBUG" "I will split this DATABASE_LIST ${DATABASE_LIST} and export all separately"
        IFS=',' read -r -a DATABASE_ARRAY <<< "${DATABASE_LIST}"
        for DATABASE in "${DATABASE_ARRAY[@]}"; do
            log "DEBUG" "Let's dump the database ${DATABASE}"
            /usr/local/bin/docker exec ${DATABASE_HOST} mysqldump -u${DATABASE_USER} -p${DATABASE_PASSWORD} --opt ${DATABASE} > /data/database-dumps/${DATABASE}.dump
        done
    else
        log "DEBUG" "Let's dump all databases"
        /usr/local/bin/docker exec ${DATABASE_HOST} mysqldump -u${DATABASE_USER} -p${DATABASE_PASSWORD} --all-databases > /data/database-dumps/all.dump
    fi
    log "INFO" "Dump finished"
else
    log "DEBUG" "Skip database dump"
fi

# BIG DATA DUMP
if [ "${SEATABLE_BIGDATA_DUMP}" == true ]; then
    log "INFO" "Dump big data"
    /usr/local/bin/docker exec ${SEATABLE_BIGDATA_HOST} /opt/seatable/scripts/seatable.sh backup-all
    log "INFO" "Dump finished"
else
    log "DEBUG" "Skip big data dump"
fi
