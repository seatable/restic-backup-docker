# Restic Backup Docker Container (for SeaTable)

A docker container to automate restic backups of your SeaTable Server.

This container runs restic backups (and checks) in regular intervals.

- Easy setup and maintanance
- Define a schedule for backup and integrity checks
- Support for different targets (tested with: Local filesystem of the host, AWS, Backblaze and rest-server)
- Healthcheck (https://healthchecks.io/) or mail notifications possible
- Support restic mount inside the container to browse the backup files (???)
- Partial and full restore possible

Use with docker compose, latest yml files at seatable docker release github repo.

## How to use

Everything below `/data/` folder in the container will be part of the backup.
All restic targets are supported like rest-server, S3, backblaze and even the same filesystem of the host.
Executed via cron inside the container.

### Hooks

Container supports the execution of the following custom hooks (if available at the container).

- /hooks/pre-backup.sh
- /hooks/post-backup.sh
- /hooks/pre-check.sh
- /hooks/post-check.sh

### Commands

In general every restic command can be easily executed in the docker container like these. Check the [official restic documentation](https://restic.readthedocs.io/) for more details.

```bash
docker exec -it restic-backup restic [command]

# Examples:
docker exec -it restic-backup restic -h
docker exec -it restic-backup restic snapshots
docker exec -it restic-backup restic version
docker exec -it restic-backup restic stats
```

In addition there are two easy to use command for backup and check. These are executed according the CRON schedule.
To execute a backup or the check the consistency manually, independent of the CRON, just run:

```bash
docker exec -it restic-backup backup
docker exec -it restic-backup check
```

## Customize the Container

The container is set up by setting environment variables and volumes.

### Environment variables

- RESTIC_REPOSITORY=/local
- RESTIC_PASSWORD=""
- RESTIC_TAG="seatable"
- BACKUP_CRON="20 2 \* \* \*"
- CHECK_CRON=""
- RESTIC_DATA_SUBSET=""
- RESTIC_FORGET_ARGS=""
- RESTIC_JOB_ARGS=""
- SEATABLE_DATABASE_DUMP=boolean
- SEATABLE_DATABSE_PASSWORD=
- SEATABLE_DATABASE_HOST=
- SEATABLE_BIGDATA_DUMP=
- SEATABLE_BIGDATA_HOST=
- HEALTHCHECK_URL=
- AWS_DEFAULT_REGION="eu-west-1"
- AWS_ACCESS_KEY_ID=""
- AWS_SECRET_ACCESS_KEY=""
- B2_ACCOUNT_ID=
- B2_ACCOUNT_KEY
- MAILX_ARGS

### Volumes

- `/data` - This is the data that gets backed up. Just mount wherever you want to it in the container and restic will take care of the backup.

### Logs

...

## Example docker-compose

```yaml
---

services:
restic-backup:
image: ${SEATABLE_RESTIC_BACKUP_IMAGE:-seatable/restic-backup:1.0.0}
    container_name: restic-backup
    hostname: ${SEATABLE_SERVER_HOSTNAME:?Variable is not set or empty}
    restart: unless-stopped
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - /opt/seatable-compose:/data/seatable-compose:ro
      - /opt/seatable-server/seatable:/data/seatable-server/seatable:ro
      - /opt/restic/local:/local
      - /opt/restic/restore:/restore
      - /opt/restic/cache:/root/.cache/restic
      #- /opt/restic/hooks:/hooks:ro
      #- /opt/restic/logs:/var/log/
    environment:
      - RESTIC_REPOSITORY=${RESTIC_REPOSITORY:-/local} - RESTIC_PASSWORD=${RESTIC_PASSWORD:?Variable is not set or empty}
      - RESTIC_TAG=${SEATABLE_SERVER_HOSTNAME}
      - BACKUP_CRON=${BACKUP_CRON:-15 2 * * *} # Start backup always at 2:15 am.
      - CHECK_CRON=${CHECK_CRON:-45 3 \* \* 6} # Start check every sunday at 3:45am
      - RESTIC_DATA_SUBSET=${RESTIC_DATA_SUBSET:-1G} # Download max 1G of data from backup and check the data integrity
      - RESTIC_FORGET_ARGS=${RESTIC_FORGET_ARGS:- --prune --keep-daily 6 --keep-weekly 4 --keep-monthly 6}
      - RESTIC_JOB_ARGS=${RESTIC_JOB_ARGS:- --exclude=/data/seatable-server/seatable/logs --exclude=/data/seatable-server/seatable/db-data --exclude-if-present .exclude_from_backup}
      - SEATABLE_DATABASE_DUMP=${SEATABLE_DATABASE_DUMP:-true}
      - SEATABLE_DATABASE_PASSWORD=${SEATABLE_MYSQL_ROOT_PASSWORD:?Variable is not set or empty}
      - SEATABLE_DATABASE_HOST=mariadb
      - SEATABLE_BIGDATA_DUMP=${SEATABLE_BIGDATA_DUMP:-true}
      - SEATABLE_BIGDATA_HOST=seatable-server
      - HEALTHCHECK_URL=${HEALTHCHECK_URL}

    # must be in the same network as mariadb for dumps...
    # must not be in the same network as seatable-server. Big data backup is initiated via docker exec
    networks:
      - backend-seatable-net
```

## How to restore

### Restore to host server

Restore inside the docker container to the /restore folder. This is mounted to the host system and the files can be seen there.
Use the following command to restore files from the latest snapshot.

```bash
docker exec -it restic-backup restic restore latest --target /restore
```

If you want to restore only a subset and from an old snapshot, use this command:
All commands from the [official restic documentation](https://restic.readthedocs.io/) are supported.

```bash
# get snapshot ids
docker exec -it restic-backup restic snapshots

# get list of files in a snapshot (you will need the path to the files for partial restore)
docker exec -it restic-backup restic ls <snapshot>

# restore only config files from a specific snapshot
docker exec -it restic-backup restic restore <snapshot> --include /data/seatable-server/seatable/conf/ --target /restore
```

### Mount

Mounting of a snapshot is not working ... fusemount???

## Open topics

- [ ] logging to stdout instead of log files
- [ ] Mail notification if something goes wrong -> mailx documentation
- [ ] clarification why restic mount is not working

```

```
