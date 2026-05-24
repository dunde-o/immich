# Custom Immich Docker Workflow

This fork keeps `main` close to upstream Immich and uses release-tag based
branches for operational Docker images. The intent is to make upgrades boring:
choose an upstream release, make the smallest custom change set, build immutable
custom images, prove them in staging, then promote the same tags to production.

## Branch Policy

- `main` mirrors upstream Immich. Do not put local product or deployment changes
  directly on `main`.
- Operational changes live on release branches named `custom/v1.XX.Y`, replacing
  `v1.XX.Y` with the upstream Immich release tag being customized.
- If upstream has moved to another major version, keep the same pattern, for
  example `custom/v2.0.1`.
- Rebuild-only fixes for the same upstream release should use an explicit
  revision suffix in the Docker tag, for example `custom-v1.XX.Y-r2`.
- Documentation-only branches can use `docs/<topic>` and should merge without
  changing runtime code.

## One-Time Remote Setup

Add the upstream Immich repository if this clone does not already have it:

```bash
git remote add upstream https://github.com/immich-app/immich.git
git fetch upstream --tags --prune
git fetch origin --prune
```

Keep fork `main` synchronized from upstream before starting a new custom release:

```bash
git switch main
git fetch upstream --tags --prune
git merge --ff-only upstream/main
git push origin main
```

Do not use merge commits from custom release branches back into `main`.

## Creating A Custom Release Branch

Start from the exact upstream release tag, not from the moving `main` branch:

```bash
VERSION=v1.XX.Y
git fetch upstream --tags --prune
git switch -c custom/$VERSION $VERSION
```

Apply the custom patch set on that branch. Keep the diff narrow and easy to
rebase:

```bash
git status --short
git diff --stat $VERSION..HEAD
git log --oneline $VERSION..HEAD
```

Before building, confirm the branch points at the intended release base:

```bash
git merge-base --is-ancestor $VERSION HEAD
git describe --tags --always
```

## Docker Tag Policy

Use fixed custom tags for every image deployed to staging or production. Do not
deploy `latest`, `main`, `release`, or any mutable tag.

Recommended tag shape:

```text
custom-v1.XX.Y
custom-v1.XX.Y-r2
custom-v1.XX.Y-cuda
custom-v1.XX.Y-r2-cuda
```

Recommended image names for this fork:

```text
ghcr.io/dunde-o/immich-server:custom-v1.XX.Y
ghcr.io/dunde-o/immich-machine-learning:custom-v1.XX.Y
ghcr.io/dunde-o/immich-machine-learning:custom-v1.XX.Y-cuda
```

Record the image digests after build. A tag is convenient for humans; the digest
is the exact artifact:

```bash
docker buildx imagetools inspect ghcr.io/dunde-o/immich-server:custom-v1.XX.Y
docker buildx imagetools inspect ghcr.io/dunde-o/immich-machine-learning:custom-v1.XX.Y
```

Once a tag has been used in staging or production, do not move it. If a rebuild
is required, publish a new `-rN` tag.

## Compose Configuration

The upstream compose file usually uses `IMMICH_VERSION` for both server and
machine-learning image tags. For custom images, keep production compose explicit
and reviewable.

Option A: keep upstream image names and set only the version tag when using
upstream images:

```env
IMMICH_VERSION=v1.XX.Y
```

Option B: use forked images by editing the service image names in your deployed
compose file:

```yaml
services:
  immich-server:
    image: ghcr.io/dunde-o/immich-server:custom-v1.XX.Y

  immich-machine-learning:
    image: ghcr.io/dunde-o/immich-machine-learning:custom-v1.XX.Y
```

If machine-learning acceleration is enabled, keep the suffix explicit:

```yaml
image: ghcr.io/dunde-o/immich-machine-learning:custom-v1.XX.Y-cuda
```

Keep `.env`, database paths, upload paths, and secrets out of git.

## Remote App Host

For a second server that should run the Immich app containers while using the
NAS Postgres, Redis, and library storage, use the remote app wrapper:

```bash
scripts/immich-remote-app.sh up
```

The script reads `docker/.env`, mounts the NAS library into `UPLOAD_LOCATION`,
checks the Immich storage marker files, pulls the configured images, and starts
`docker/remote-app.compose.yml`. The remote app starts three containers on this
server: API/UI, internal worker, and machine-learning.

Current remote app images for this branch:

```text
ghcr.io/dunde-o/immich-server:v2.7.5-custom.2
ghcr.io/dunde-o/immich-machine-learning:v2.7.5-custom.2
```

The `immich-server` image is used twice by compose:

- `immich_remote_server`: API/UI only, with `IMMICH_WORKERS_INCLUDE=api`.
- `immich_remote_worker_internal`: background jobs only, with
  `IMMICH_WORKERS_EXCLUDE=api`.

The machine-learning image is currently a tag-aligned copy of the upstream
`immich-machine-learning:v2.7.5` image. It is published under the fork namespace
so the server and machine-learning tags move together in deployment files.

Required values in `docker/.env`:

```env
UPLOAD_LOCATION=/path/on/this-server/immich/library
IMMICH_REMOTE_SERVER_IMAGE=ghcr.io/dunde-o/immich-server:v2.7.5-custom.2
IMMICH_REMOTE_ML_IMAGE=ghcr.io/dunde-o/immich-machine-learning:v2.7.5-custom.2
IMMICH_REMOTE_LIBRARY_MOUNT_MODE=nfs
IMMICH_REMOTE_LIBRARY_MOUNT_REMOTE=<nas-host>:<nas-library-path>
IMMICH_REMOTE_LIBRARY_MOUNT_OPTIONS=vers=4.1
DB_HOSTNAME=<nas-db-host>
DB_PORT=5432
REDIS_HOSTNAME=<nas-redis-host>
REDIS_PORT=6379
```

The remote app compose intentionally does not start Postgres or Redis. It must
connect to the NAS instances and must see the same library files through the
mounted `UPLOAD_LOCATION`.

On the NAS, keep only the shared backing services running:

- Postgres
- Redis
- the exported Immich library storage

If the goal is to make this remote app host perform the work, stop the NAS
application workers while the remote app is active:

- stop the NAS `immich-server` container if this host should serve the UI/API;
- stop any NAS `immich-worker-internal` container;
- stop the NAS `immich-machine-learning` container.

If the NAS `immich-server` remains running with workers enabled, it can consume
jobs from the same Redis queue. Use an API-only NAS server configuration only
when the NAS must keep serving the UI while this host performs background jobs.

Useful commands:

```bash
scripts/immich-remote-app.sh config
scripts/immich-remote-app.sh ps
scripts/immich-remote-app.sh logs
scripts/immich-remote-app.sh down
scripts/immich-remote-app.sh umount-library
```

`up` runs `mount-library`, `check-library`, `pull`, then `docker compose up -d`.
`down` runs the reverse cleanup path: `docker compose down`, removes the
configured remote app images from this server, then unmounts the library.
After setting the NAS database password in `docker/.env`, the file can be made
read-only to avoid accidental rewrites:

```bash
scripts/immich-remote-app.sh lock-env
scripts/immich-remote-app.sh unlock-env
```

## Staging Gate

Run every custom image in staging before production. Staging should use a copy of
the production compose shape, separate credentials, and disposable test data or a
sanitized production restore.

Minimum staging checks:

- `docker compose pull` succeeds for every custom image.
- `docker compose up -d` starts without container restart loops.
- Web login works.
- Mobile app can connect to the server endpoint.
- Photo upload, video upload, timeline view, search, and thumbnail generation
  work.
- Machine-learning jobs complete if ML is enabled.
- Server and worker logs have no repeating migration, job, or permission errors.

Useful commands:

```bash
docker compose ps
docker compose logs --tail=200 immich-server
docker compose logs --tail=200 immich-machine-learning
docker compose exec database pg_isready -U "$DB_USERNAME" -d "$DB_DATABASE_NAME"
```

Do not promote to production if staging required manual database edits, manual
container surgery, or unrecorded changes.

## Backup Requirement

Take a backup before every production upgrade or rollback attempt.

At minimum, preserve:

- Postgres database dump.
- Upload/library storage referenced by `UPLOAD_LOCATION`.
- Database storage referenced by `DB_DATA_LOCATION`, if using volume snapshots.
- The exact deployed compose file and `.env` values.
- Current image tags and digests.

Example database dump from the compose host:

```bash
mkdir -p backups
docker compose exec -T database pg_dumpall -U "$DB_USERNAME" > "backups/immich-db-$(date +%Y%m%d-%H%M%S).sql"
```

Also keep an out-of-host copy. A local backup on the same disk is not enough for
media safety.

## Production Deployment

Promote the same image tags that passed staging. Do not rebuild between staging
and production.

Suggested deployment flow:

```bash
docker compose pull
docker compose up -d
docker compose ps
docker compose logs --tail=200 immich-server
```

After deployment, verify:

- Web UI loads and login succeeds.
- New uploads are accepted.
- Existing assets, thumbnails, and videos load.
- Background jobs are draining.
- There are no repeated errors in server, machine-learning, Redis, or Postgres
  logs.

Record the deployed release:

```text
date:
branch:
upstream tag:
server image + digest:
machine-learning image + digest:
backup location:
staging result:
production notes:
```

## Rollback

Rollback depends on whether the new release ran database migrations.

If no irreversible migration ran, switch compose back to the previous fixed image
tags and restart:

```bash
docker compose pull
docker compose up -d
docker compose ps
```

If migrations ran or data was modified by the new version, restore the matching
database backup before starting the older image set. Do not run older Immich code
against a newer migrated database unless the release notes explicitly say it is
safe.

Rollback checklist:

- Stop writes or put the service in maintenance mode if possible.
- Save current logs before changing containers.
- Restore database from the backup that matches the previous production version.
- Restore media/storage snapshots only if the failure affected stored files.
- Start the previous image tags.
- Verify login, timeline, uploads, and background jobs.
- Document the failure and the final running image digests.

## Upgrade Checklist

- [ ] Upstream release notes reviewed.
- [ ] `main` synchronized with upstream.
- [ ] `custom/v1.XX.Y` branch created from the upstream release tag.
- [ ] Custom diff reviewed and kept narrow.
- [ ] Fixed custom Docker tags built and digests recorded.
- [ ] Staging deployed using the same tags.
- [ ] Staging smoke checks passed.
- [ ] Production database and media backups completed.
- [ ] Production deployed using the same tags.
- [ ] Production smoke checks passed.
- [ ] Rollback path and previous image tags documented.
