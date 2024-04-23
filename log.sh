# Function to log messages
# $LOG_LEVEL is the requested log level of the container, defined by the user in the ENV_VARIABLES
# $LEVEL is the level of the log message.

# set default values for all other environment variables
export BACKUP_CRON=${BACKUP_CRON:="20 2 * * *"}
export CHECK_CRON=${CHECK_CRON:="40 3 * * 6"}
export LOG_LEVEL=${LOG_LEVEL:="INFO"}
export LOG_TYPE=${LOG_TYPE:="stdout"}
export RESTIC_TAG=${RESTIC_TAG:="seatable"}
export RESTIC_DATA_SUBSET=${RESTIC_DATA_SUBSET:="1G"}
export RESTIC_FORGET_ARGS=${RESTIC_FORGET_ARGS:=" --prune --keep-daily 6 --keep-weekly 4 --keep-monthly 6"}
export RESTIC_JOB_ARGS=${RESTIC_JOB_ARGS:=" --exclude=/data/logs --exclude-if-present .exclude_from_backup"}
export RESTIC_SKIP_INIT=${RESTIC_SKIP_INIT:="false"}
export SEATABLE_DATABASE_DUMP=${SEATABLE_DATABASE_DUMP:="false"}
export SEATABLE_DATABASE_HOST=${SEATABLE_DATABASE_HOST:="mariadb"}
export SEATABLE_DATABASE_USER=${SEATABLE_DATABASE_USER:="root"}
export SEATABLE_BIGDATA_DUMP=${SEATABLE_BIGDATA_DUMP:="false"}
export SEATABLE_BIGDATA_HOST=${SEATABLE_BIGDATA_HOST:="seatable-server"}

log() {
    local LEVEL="$1"
    local MESSAGE="$2"
    local TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")
    local LOG_FILE="/var/log/restic/backup.log"

    # always output to stdout depending of the LEVEL of the message.
    case $LEVEL in
        "DEBUG")
            [[ "$LOG_LEVEL" == "DEBUG" ]] && echo -e "[$TIMESTAMP] [DEBUG] $MESSAGE" >&2
            ;;
        "INFO")
            [[ "$LOG_LEVEL" == "INFO" || "$LOG_LEVEL" == "DEBUG" ]] && echo -e "[$TIMESTAMP] [INFO] $MESSAGE" >&2
            ;;
        "WARNING")
            [[ "$LOG_LEVEL" == "WARNING"  || "$LOG_LEVEL" == "INFO" || "$LOG_LEVEL" == "DEBUG" ]] && echo -e "[$TIMESTAMP] [INFO] $MESSAGE" >&2
            ;;
        "ERROR")
            [[ "$LOG_LEVEL" == "ERROR" || "$LOG_LEVEL" == "WARNING"  || "$LOG_LEVEL" == "INFO" || "$LOG_LEVEL" == "DEBUG" ]] && echo -e "[$TIMESTAMP] [ERROR] $MESSAGE" >&2
            ;;
    esac

    # IF 
    if [[ $LOG_TYPE == "file" ]]; then
        case $LEVEL in
            "DEBUG")
                [[ "$LOG_LEVEL" == "DEBUG" ]] && echo -e "[$TIMESTAMP] [DEBUG] $MESSAGE" >> $LOG_FILE
                ;;
            "INFO")
                [[ "$LOG_LEVEL" == "INFO" || "$LOG_LEVEL" == "DEBUG" ]] && echo -e "[$TIMESTAMP] [INFO] $MESSAGE" >> $LOG_FILE
                ;;
            "WARNING")
                [[ "$LOG_LEVEL" == "WARNING"  || "$LOG_LEVEL" == "INFO" || "$LOG_LEVEL" == "DEBUG" ]] && echo -e "[$TIMESTAMP] [INFO] $MESSAGE" >> $LOG_FILE
                ;;
            "ERROR")
                [[ "$LOG_LEVEL" == "ERROR" || "$LOG_LEVEL" == "WARNING"  || "$LOG_LEVEL" == "INFO" || "$LOG_LEVEL" == "DEBUG" ]] && echo -e "[$TIMESTAMP] [ERROR] $MESSAGE" >> $LOG_FILE
                ;;
        esac
    fi
}
