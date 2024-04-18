# Restic Backup Docker Container (for SeaTable)

A docker container to automate restic backups of your SeaTable Server.

This container runs restic backups (and checks) in regular intervals.

- ...
- ...
- ...

Use with docker compose, latest yml files at seatable docker release github repo.

## How to use

Everything below `/data/` folder in the container will be part of the backup.
All restic targets are supported.
Executed via cron.

## Hooks

supports the following hooks:

- /hooks/pre-backup.sh
- /hooks/post-backup.sh
- /hooks/pre-check.sh
- /hooks/post-check.sh

## Commands

```bash
docker exec -it restic-backup /bin/backup
```

## Customize the Container

The container is set up by setting environment variables and volumes.

### Environment variables

- RESTIC_REPOSITORY=/local
- RESTIC_PASSWORD=""
- RESTIC_TAG="seatable"
- NFS_TARGET=""
- BACKUP_CRON="20 2 \* \* \*"
- CHECK_CRON=""
- RESTIC_INIT_ARGS=""
- RESTIC_FORGET_ARGS=""
- RESTIC_JOB_ARGS=""
- RESTIC_DATA_SUBSET=""
- MAILX_ARGS=""
- HEALTHCHECK_URL=
- AWS_DEFAULT_REGION="eu-west-1"
- AWS_ACCESS_KEY_ID=""
- AWS_SECRET_ACCESS_KEY=""
- B2_ACCOUNT_ID=
- B2_ACCOUNT_KEY

### Volumes

- `/data` - This is the data that gets backed up. Just mount wherever you want to it in the container and restic will take care of the backup.

## Example docker-compose

```
---
services:
  restic-backup:
    image: lobaro/restic-backup-docker:latest
    container_name: restic-backup
    hostname: stage.seatable.io
    restart: always
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - /opt/seatable-compose:/data/seatable-compose:ro
      - /opt/seatable-server/seatable:/data/seatable-server/seatable:ro
      - /opt/restic/local:/local
      - /opt/restic/restore:/restore
      - /opt/restic/cache:/root/.cache/restic
    environment:
      - RESTIC_REPOSITORY=rest:https://nn0zjie4:W910jhw5LxeaHp5N@nn0zjie4.repo.borgbase.com  ${RESTIC_REPOSITORY:-/local}
      - RESTIC_PASSWORD=${RESTIC_PASSWORD:?Variable is not set or empty}
      - BACKUP_CRON=15 * * * *                             # Start backup always 15 minutes after every hour.
      #- CHECK_CRON=0 22 * * 3                              # Start check every Wednesday 22:00 UTC
      #- RESTIC_DATA_SUBSET=1G                              # Download 50G of data from "storageserver" every Wednesday 22:00 UTC and check the data integrity
      - RESTIC_FORGET_ARGS=--prune --keep-last 12          # Only keep the last 12 snapshots
      - SEATABLE_DATABASE_DUMP=true
      - SEATABLE_DATABASE_PASSWORD=dtable_db
      - SEATABLE_DATABASE_HOST=mariadb
      - SEATABLE_BIGDATA_DUMP=true
      - SEATABLE_BIGDATA_HOST=seatable-server

    # must be in the same network as mariadb for dumps...
    # must be in the same network as seatable-server for start backups -> verstehe ich nicht... -> dafür brauche ich den docker exec, damit...
    # eher stelle ich das per config im seatable-server container ein.
    networks:
      - backend-seatable-net
```

## Was noch fehlt

[x] B2 VARIABLES
[x] HEALTHCHECK
[x] CHECK FIXEN
