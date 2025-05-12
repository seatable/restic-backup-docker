# Changelog

## 1.6.0 (12.05.2025)

- updated software versions and debian base image
- run as non root

## 1.5.4 (10.02.2025)

- improved tree output
- added AWS to proposed docker-compose.yml

## 1.5.3 (31.01.2025)

- openssh-client added to docker image

## 1.5.2 (13.01.2025)

- fix: gzip overwrites existing all.dump.gz

## 1.5.1 (17.12.2024)

- Add version to restic-curl client

## 1.5.0 (16.12.2024)

- Add option to compress database dumps with gzip

## 1.4.2 (06.12.2024)

- Changes to improve Docker Scout Health Score

## 1.4.1 (06.12.2024)

- advanced error reporting if post-backup or pre-backup returns an error.

## 1.4.0 (06.12.2024)

- support mariadb-dump and mysqldump, check which is available in the container

## 1.3.2 (16.09.2024)

- fixing typo in entry.sh

## 1.3.1 (12.09.2024)

- remove default values for RESTIC_FORGET_ARGS and RESTIC_JOB_ARGS
- add HEALTHCHECK_URL to debug output
- improved README.md for parallel backups

## 1.3.0 (05.08.2024)

- harmonize to dump any mysql/mariadb database

## 1.2.9 (01.08.2024)

- add possibility to dump Seafile database
- creating log directory on every start

## 1.2.7 (28.06.2024)

- absolute paths in pre-default.sh

## v1.2.6 (24.06.2024)

- add jq to the Dockerfile

## v1.2.5 (23.04.2024)

- mstmp instead of mailx
- new environment variable: RESTIC_SKIP_INIT

## v1.2.4 (22.04.2024)

- default values for manual execution

## v1.2.3 (22.04.2024)

- add ca-certificates to the Dockerfile

## v1.2.2 (22.04.2024)

- remove restic mount

## v1.2.1 (22.04.2024)

- fix problems with container stop

## v1.2.0 (22.04.2024)

- LOG_LEVEL and LOG_TYPE added
- smaller container image
- cron rework
- Timezone support added
- new tag naming (v1.2.0 or pre-v1.2.0)

## v1.1.4 (19.04.2024)

- Cleanup of entry.sh
- fix docker installation method

## v1.1.0 (19.04.2024)

- restic mount support
- basic image switched to debian
- improved documentation of environment variables

## v1.0.0 (05.04.2024)

Initial release.
