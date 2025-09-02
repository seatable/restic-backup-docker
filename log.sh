# Function to log messages
# $LOG_LEVEL is the requested log level of the container, defined by the user in the ENV_VARIABLES
# $LEVEL is the level of the log message.

set_default() {
  local var_name=$1
  local default_value=$2
  export "$var_name"="${!var_name:-$default_value}"
}

# set default values for all other environment variables
set_default BACKUP_CRON "20 2 * * *"
set_default CHECK_CRON "40 3 * * 6"
set_default LOG_LEVEL "INFO"
set_default LOG_TYPE "stdout"
set_default RESTIC_TAG "seatable"
set_default RESTIC_DATA_SUBSET "1G"
set_default RESTIC_FORGET_ARGS ""
set_default RESTIC_JOB_ARGS ""
set_default RESTIC_SKIP_INIT false
set_default DATABASE_DUMP false
set_default DATABASE_HOST "mariadb"
set_default DATABASE_USER "root"
set_default DATABASE_LIST ""
set_default DATABASE_DUMP_COMPRESSION "false"
set_default SEATABLE_BIGDATA_DUMP "false"
set_default SEATABLE_BIGDATA_HOST "seatable-server"
set_default HEALTHCHECK_URL ""
set_default USER_AGENT "restic-backup-docker/1.6.1"

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
