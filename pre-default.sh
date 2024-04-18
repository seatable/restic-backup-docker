#!/usr/bin/env bash
#
# description of the script

set -euo pipefail

#

if [ $SEATABLE_DATABASE_DUMP == true ]; then
    echo "== Database Dumps =="
    mkdir -p /data/seatable-dumps
    docker exec ${SEATABLE_DATABASE_HOST} mysqldump -uroot -p${SEATABLE_DATABASE_PASSWORD} --opt ccnet_db > /data/seatable-dumps/ccnet.dump
    docker exec ${SEATABLE_DATABASE_HOST} mysqldump -uroot -p${SEATABLE_DATABASE_PASSWORD} --opt seafile_db > /data/seatable-dumps/seafile.dump
    docker exec ${SEATABLE_DATABASE_HOST} mysqldump -uroot -p${SEATABLE_DATABASE_PASSWORD} --opt dtable_db > /data/seatable-dumps/dtable.dump
fi

if [ $SEATABLE_BIGDATA_DUMP == true ]; then
    echo "== BigData Dumps =="
    docker exec seatable-server /opt/seatable/scripts/seatable.sh backup-all
fi
