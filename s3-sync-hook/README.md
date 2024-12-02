# S3 Synchronisation Hooks

this script `post-backup.sh` is used to sync two S3 buckets. It can be used, if the SeaTable Server uses S3 for storage and assets.

It is recommended that versioning is activated on the backup target.

The bucket names are fixed and have to follow this structure

- FRANKFURT ---------------------> MUNICH
- seatable-${CUSTOMER}-storage  -> seatable-dedicated-${CUSTOMER}-backup-storage
- seatable-${CUSTOMER}-fs       -> seatable-dedicated-${CUSTOMER}-backup-fs
- seatable-${CUSTOMER}-commits  -> seatable-dedicated-${CUSTOMER}-backup-commits
- seatable-${CUSTOMER}-blocks   -> seatable-dedicated-${CUSTOMER}-backup-blocks

This also requires a rclone configuration file, mounted to the container with:

```sh
    volumes:
      - ...
      - /opt/restic/rclone:/root/.config/rclone
```

The configuration file `/opt/restic/rclone/rclone.conf` has to look like this:

```sh
[exoscale]
type = s3
provider = Other
access_key_id = EXO...
secret_access_key = ...
region = other-v2-signature
endpoint = sos-de-fra-1.exo.io
acl = private

[exoscale-backup]
type = s3
provider = Other
access_key_id = EXO...
secret_access_key = ...
region = other-v2-signature
endpoint = sos-de-muc-1.exo.io
acl = private
```
