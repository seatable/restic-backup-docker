# Restic Backup Docker Container (for SeaTable)

A docker container to automate restic backups of your SeaTable Server.

This container runs restic backups (and checks) in regular intervals.

- Easy setup and maintanance
- Define a schedule for backup and integrity checks
- Support for different targets (tested with: Local filesystem of the host, AWS, Backblaze and rest-server)
- Healthcheck (https://healthchecks.io/) or mail notifications possible
- Support restic mount inside the container to browse the backup files
- Partial and full restore possible

Use with docker compose, latest yml files at seatable docker release github repo.

## How to use

Everything below `/data/` folder in the container will be part of the backup.
All restic targets are supported like rest-server, S3, backblaze and even the same filesystem of the host.
Executed via cron inside the container.

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

### Hooks

Container supports the execution of the following custom hooks (if available at the container).

- /hooks/pre-backup.sh
- /hooks/post-backup.sh
- /hooks/pre-check.sh
- /hooks/post-check.sh

### Logs

Logs are written inside the container to `/var/log/` and mounted as volume to `/opt/restic/logs`.

## Customize the Container

The container is set up by setting environment variables and volumes.

### Environment variables

| Name                         | Description                             | Example                                                                                         |
| ---------------------------- | --------------------------------------- | ----------------------------------------------------------------------------------------------- |
| `RESTIC_REPOSITORY`          | Restic backup target                    | `/local` or `rest:https://backup.seatable.io`                                                   |
| `RESTIC_PASSWORD`            | Encryption password                     | `topsecret`                                                                                     |
| `RESTIC_TAG`                 | Tag for backup                          | `seatable`                                                                                      |
| `BACKUP_CRON`                | Execution schedule for the backup       | `20 2 * * *`                                                                                    |
| `CHECK_CRON`                 | Execution schedule for integrity check  | `40 3 * * 6`                                                                                    |
| `RESTIC_DATA_SUBSET`         | Restic checks only a subset of the data | `1G` or `10%` or `1/10`                                                                         |
| `RESTIC_FORGET_ARGS`         | Restic Forget parameters                | ` --prune --keep-daily 6 --keep-monthly 6`                                                      |
| `RESTIC_JOB_ARGS`            | Restic Job execution parameters         | `--exclude=/data/logs --exclude-if-present .exclude_from_backup`                                |
| `SEATABLE_DATABASE_DUMP`     | Enable SeaTable database dump           | `true` or `false`                                                                               |
| `SEATABLE_DATABASE_HOST`     | Name of the mariadb container           | `mariadb`                                                                                       |
| `SEATABLE_DATABASE_USER`     | User for connection to mariadb          | `root`                                                                                          |
| `SEATABLE_DATABASE_PASSWORD` | Password for connection to mariadb      | `topsecret`                                                                                     |
| `SEATABLE_BIGDATA_DUMP`      | Enable dump of big data                 | `true` or `false`                                                                               |
| `SEATABLE_BIGDATA_HOST`      | Name of the SeaTable Server container   | `seatable-server`                                                                               |
| `HEALTHCHECK_URL`            | healthcheck.io server check url         | `https://healthcheck.io/ping/a444061a`                                                          |
| `MAILX_ARGS`                 | SMTP settings for mail notification     | `-S smtp=smtp.example.com -S smtp-use-starttls -S smtp-auth-user=... -S smtp-auth-password=...` |
| `AWS_DEFAULT_REGION`         | Required only for S3 backend            | `eu-west-1`                                                                                     |
| `AWS_ACCESS_KEY_ID`          | Required only for S3 backend            |                                                                                                 |
| `AWS_SECRET_ACCESS_KEY_ID`   | Required only for S3 backend            |                                                                                                 |
| `B2_ACCOUNT_ID`              | Required only for backblaze backend     |                                                                                                 |
| `B2_ACCOUNT_KEY`             | Required only for backblaze backend     |                                                                                                 |

## Example docker-compose

```yaml
---

services:
restic-backup:
image: ${SEATABLE_RESTIC_BACKUP_IMAGE:-seatable/restic-backup:1.1.0}
    container_name: restic-backup
    restart: unless-stopped
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - /opt/seatable-compose:/data/seatable-compose:ro
      - /opt/seatable-server/seatable:/data/seatable-server/seatable:ro
      - /opt/restic/local:/local
      - /opt/restic/restore:/restore
      - /opt/restic/cache:/root/.cache/restic
      - /opt/restic/hooks:/hooks:ro
      - /opt/restic/logs:/var/log/
      - /opt/restic/mount:/mnt/mount:shared # needed for "restic mount" / :shared volume to see the content of mounted fuse filesystem from host
    devices:
      - /dev/fuse # needed for "restic mount" / access to the host filesystem
    cap_add:
      - SYS_ADMIN # needed for "restic mount" / grants sysadmin capabilities
    security_opt:
      - apparmor:unconfined # needed for "restic mount" / disable apparmor
    environment:
      - RESTIC_REPOSITORY=${RESTIC_REPOSITORY:-/local}
      - RESTIC_PASSWORD=${RESTIC_PASSWORD:?Variable is not set or empty}
      - RESTIC_TAG=${SEATABLE_SERVER_HOSTNAME:-seatable}
      - BACKUP_CRON=${BACKUP_CRON:-15 2 * * *} # Start backup always at 2:15 am.
      - CHECK_CRON=${CHECK_CRON:-45 3 \* \* 6} # Start check every sunday at 3:45am
      - RESTIC_DATA_SUBSET=${RESTIC_DATA_SUBSET:-1G} # Download max 1G of data from backup and check the data integrity
      - RESTIC_FORGET_ARGS=${RESTIC_FORGET_ARGS:- --prune --keep-daily 6 --keep-weekly 4 --keep-monthly 6}
      - RESTIC_JOB_ARGS=${RESTIC_JOB_ARGS:- --exclude=/data/seatable-server/seatable/logs --exclude=/data/seatable-server/seatable/db-data --exclude-if-present .exclude_from_backup}
      - SEATABLE_DATABASE_DUMP=${SEATABLE_DATABASE_DUMP:-true}
      - SEATABLE_DATABASE_HOST=${SEATABLE_DATABASE_HOST:-mariadb}
      - SEATABLE_DATABASE_USER=${SEATABLE_DATABASE_USER:-root}
      - SEATABLE_DATABASE_PASSWORD=${SEATABLE_MYSQL_ROOT_PASSWORD:?Variable is not set or empty}
      - SEATABLE_BIGDATA_DUMP=${SEATABLE_BIGDATA_DUMP:-true}
      - SEATABLE_BIGDATA_HOST=${SEATABLE_BIGDATA_HOST:-seatable-server}
      - HEALTHCHECK_URL=${HEALTHCHECK_URL}
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

`restic mount` allows to mount a snapshot to make it accessable like a local filesystem. It uses "FUSE" (Filesystem in Userspace), which requires that the FUSE kernel component from the hosts system must be made accessible to the container.

This can be done either with the "privileged" flag in the docker-compose file, which is not recommended or via multiple other parameters during runtime. If you don't want to use this feature, you can easily comment or remove the corresponding lines from the yml file.

```bash
# it is recommended to use screen or another terminal multiplexer for this command
screen -S restic-mount
docker exec -it restic-backup restic mount /mnt/mount
# press "Ctrl + a" and then "d" to detach from the screen
ls /opt/restic/mount
```
