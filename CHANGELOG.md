# Changelog

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
