#!/bin/bash

# NEU für docker container restic backup
CUSTOMER=example

# --- don't change anything below this line ---

NUM_CHECKS=4
LOG_FILE="/var/log/sync.log"
SYNC_PARAMS="--config /root/.config/rclone/rclone.conf --stats 30m --stats-one-line --stats-log-level NOTICE --transfers=16 --checkers=16 --skip-links --s3-no-check-bucket --log-file="${LOG_FILE}" --log-level=NOTICE --size-only"
SIZE_PARAMS="--config /root/.config/rclone/rclone.conf --stats 30m --stats-one-line --stats-log-level NOTICE --transfers=16 --checkers=16 --skip-links --s3-no-check-bucket --log-file=/dev/null     --log-level=NOTICE --json"
DEVIATION_PERC=1
# 0 bedeutet, die Werte müssen identisch sein.

/usr/bin/curl -fsS -m 10 --retry 5 -o /dev/null ${HEALTHCHECK_URL}/start

echo "Allowed deviation in perc: ${DEVIATION_PERC}" > ${LOG_FILE}

function compare_size(){
  c1=`echo ${1} | jq .count`
  c2=`echo ${2} | jq .count`
  c2dev=$(( ${c2} * (100+${DEVIATION_PERC}) / 100 ))
  b1=`echo ${1} | jq .bytes`
  b2=`echo ${2} | jq .bytes`
  b2dev=$(( ${b2} * (100+${DEVIATION_PERC}) / 100 ))

  if [[ $c1 -gt $c2dev || $b1 -gt $b2dev ]]; then
    status="ERROR"
  else
    status="OK"
  fi
  echo ${1} ? ${2} = ${status} >> ${LOG_FILE}
}

echo -e "\nstorage: " >> ${LOG_FILE}
/bin/rclone sync          exoscale:seatable-${CUSTOMER}-storage   exoscale-backup:seatable-dedicated-${CUSTOMER}-backup-storage ${SYNC_PARAMS}
json1=`/bin/rclone size   exoscale:seatable-${CUSTOMER}-storage ${SIZE_PARAMS}`
json2=`/bin/rclone size   exoscale-backup:seatable-dedicated-${CUSTOMER}-backup-storage ${SIZE_PARAMS}`
compare_size $json1 $json2

echo -e "\ncommits: " >> ${LOG_FILE}
/bin/rclone sync          exoscale:seatable-${CUSTOMER}-commits   exoscale-backup:seatable-dedicated-${CUSTOMER}-backup-commits ${SYNC_PARAMS}
json1=`/bin/rclone size   exoscale:seatable-${CUSTOMER}-commits ${SIZE_PARAMS}`
json2=`/bin/rclone size   exoscale-backup:seatable-dedicated-${CUSTOMER}-backup-commits   ${SIZE_PARAMS}`
compare_size $json1 $json2

echo -e "\nfs: " >> ${LOG_FILE}
/bin/rclone sync          exoscale:seatable-${CUSTOMER}-fs        exoscale-backup:seatable-dedicated-${CUSTOMER}-backup-fs      ${SYNC_PARAMS}
json1=`/bin/rclone size   exoscale:seatable-${CUSTOMER}-fs      ${SIZE_PARAMS}`
json2=`/bin/rclone size   exoscale-backup:seatable-dedicated-${CUSTOMER}-backup-fs        ${SIZE_PARAMS}`
compare_size $json1 $json2

echo -e "\nblocks: " >> ${LOG_FILE}
/bin/rclone sync          exoscale:seatable-${CUSTOMER}-blocks    exoscale-backup:seatable-dedicated-${CUSTOMER}-backup-blocks  ${SYNC_PARAMS}
json1=`/bin/rclone size   exoscale:seatable-${CUSTOMER}-blocks  ${SIZE_PARAMS}`
json2=`/bin/rclone size   exoscale-backup:seatable-dedicated-${CUSTOMER}-backup-blocks    ${SIZE_PARAMS}`
compare_size $json1 $json2

hits=$(cat ${LOG_FILE} | grep "ERROR" | wc -l)
if [[ $hits -eq 0 ]]; then
  status=0
else
  status=1
fi

/usr/bin/curl -fsS -m 10 --retry 5 --data-binary @${LOG_FILE} ${HEALTHCHECK_URL}/$status