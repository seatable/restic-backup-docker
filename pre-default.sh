#!/usr/bin/env bash
#
# description of the script

set -eo pipefail

#

if [ ${SEATABLE_DATABASE_DUMP} == true ]; then
    echo "== Dump the database =="
    mkdir -p /data/seatable-dumps
    docker exec ${SEATABLE_DATABASE_HOST} mysqldump -u${SEATABLE_DATABASE_USER} -p${SEATABLE_DATABASE_PASSWORD} --opt ccnet_db > /data/seatable-dumps/ccnet.dump
    docker exec ${SEATABLE_DATABASE_HOST} mysqldump -u${SEATABLE_DATABASE_USER} -p${SEATABLE_DATABASE_PASSWORD} --opt seafile_db > /data/seatable-dumps/seafile.dump
    docker exec ${SEATABLE_DATABASE_HOST} mysqldump -u${SEATABLE_DATABASE_USER} -p${SEATABLE_DATABASE_PASSWORD} --opt dtable_db > /data/seatable-dumps/dtable.dump
fi

if [ ${SEATABLE_BIGDATA_DUMP} == true ]; then
    echo "== Dump big data =="
    docker exec ${SEATABLE_BIGDATA_HOST} /opt/seatable/scripts/seatable.sh backup-all
fi
