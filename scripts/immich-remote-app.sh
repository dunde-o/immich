#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="${ROOT_DIR}/docker/remote-app.compose.yml"
ENV_FILE="${ROOT_DIR}/docker/.env"

usage() {
  cat <<'USAGE'
Usage:
  scripts/immich-remote-app.sh config
  scripts/immich-remote-app.sh mount-library
  scripts/immich-remote-app.sh umount-library
  scripts/immich-remote-app.sh check-library
  scripts/immich-remote-app.sh pull
  scripts/immich-remote-app.sh up
  scripts/immich-remote-app.sh down
  scripts/immich-remote-app.sh logs
  scripts/immich-remote-app.sh ps
  scripts/immich-remote-app.sh lock-env
  scripts/immich-remote-app.sh unlock-env

The runtime env file is docker/.env.
The up command runs: mount-library -> check-library -> pull -> docker compose up -d.
The down command runs the reverse path: docker compose down -> remove images -> umount-library.
Use lock-env after setting DB_PASSWORD if you want to prevent accidental .env rewrites.
USAGE
}

ensure_env() {
  if [[ ! -f "${ENV_FILE}" ]]; then
    echo "Missing ${ENV_FILE}" >&2
    echo "Copy docker/example.env to docker/.env and fill the remote app values." >&2
    exit 1
  fi
}

compose() {
  docker compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" "$@"
}

env_value() {
  local key="$1"
  awk -v key="${key}" '
    BEGIN { FS = "=" }
    $1 == key {
      sub(/^[^=]*=/, "")
      gsub(/^"|"$/, "")
      print
      exit
    }
  ' "${ENV_FILE}"
}

require_env() {
  local key="$1"
  local value
  value="$(env_value "${key}")"
  if [[ -z "${value}" || "${value}" == \<* ]]; then
    echo "${key} is required in ${ENV_FILE}" >&2
    exit 1
  fi
  printf '%s\n' "${value}"
}

library_path() {
  require_env "UPLOAD_LOCATION"
}

validate_remote_app_env() {
  require_env "IMMICH_REMOTE_SERVER_IMAGE" >/dev/null
  require_env "IMMICH_REMOTE_ML_IMAGE" >/dev/null
  require_env "DB_HOSTNAME" >/dev/null
  require_env "DB_USERNAME" >/dev/null
  require_env "DB_PASSWORD" >/dev/null
  require_env "DB_DATABASE_NAME" >/dev/null
  require_env "REDIS_HOSTNAME" >/dev/null
}

lock_env() {
  ensure_env
  chmod 400 "${ENV_FILE}"
  echo "Locked ${ENV_FILE} as read-only."
}

unlock_env() {
  ensure_env
  chmod 600 "${ENV_FILE}"
  echo "Unlocked ${ENV_FILE} for editing."
}

remove_images() {
  ensure_env

  local image
  local images=()
  mapfile -t images < <(printf '%s\n' "$(require_env "IMMICH_REMOTE_SERVER_IMAGE")" "$(require_env "IMMICH_REMOTE_ML_IMAGE")" | awk '!seen[$0]++')

  for image in "${images[@]}"; do
    if docker image inspect "${image}" >/dev/null 2>&1; then
      docker image rm "${image}"
    else
      echo "Image already removed: ${image}"
    fi
  done
}

mount_library() {
  ensure_env

  local path mode remote options
  path="$(library_path)"
  mode="$(env_value "IMMICH_REMOTE_LIBRARY_MOUNT_MODE")"
  remote="$(env_value "IMMICH_REMOTE_LIBRARY_MOUNT_REMOTE")"
  options="$(env_value "IMMICH_REMOTE_LIBRARY_MOUNT_OPTIONS")"

  if [[ -z "${mode}" || "${mode}" == "none" ]]; then
    return 0
  fi

  mkdir -p "${path}"
  if mountpoint -q "${path}"; then
    echo "Library already mounted: ${path}"
    return 0
  fi

  if [[ -z "${remote}" || "${remote}" == \<* ]]; then
    echo "IMMICH_REMOTE_LIBRARY_MOUNT_REMOTE is required when IMMICH_REMOTE_LIBRARY_MOUNT_MODE=${mode}" >&2
    exit 1
  fi

  case "${mode}" in
    nfs)
      if ! command -v mount.nfs >/dev/null 2>&1; then
        echo "NFS mount helper is not installed. Install nfs-common first." >&2
        exit 1
      fi
      sudo mount -t nfs ${options:+-o "${options}"} "${remote}" "${path}"
      ;;
    cifs)
      if ! command -v mount.cifs >/dev/null 2>&1; then
        echo "CIFS mount helper is not installed. Install cifs-utils first." >&2
        exit 1
      fi
      sudo mount -t cifs ${options:+-o "${options}"} "${remote}" "${path}"
      ;;
    *)
      echo "Unsupported IMMICH_REMOTE_LIBRARY_MOUNT_MODE=${mode}. Use nfs, cifs, or none." >&2
      exit 1
      ;;
  esac

  echo "Mounted library: ${path}"
}

umount_library() {
  ensure_env

  local path
  path="$(library_path)"

  if ! mountpoint -q "${path}"; then
    echo "Library is not mounted: ${path}"
    return 0
  fi

  sudo umount "${path}"
  echo "Unmounted library: ${path}"
}

check_library() {
  ensure_env

  local path marker missing=0
  path="$(library_path)"

  if [[ ! -d "${path}" ]]; then
    echo "UPLOAD_LOCATION does not exist: ${path}" >&2
    exit 1
  fi

  for marker in encoded-video/.immich thumbs/.immich upload/.immich library/.immich profile/.immich backups/.immich; do
    if [[ ! -f "${path}/${marker}" ]]; then
      echo "Missing library marker: ${path}/${marker}" >&2
      missing=1
    fi
  done

  if [[ "${missing}" -ne 0 ]]; then
    echo "UPLOAD_LOCATION is not the mounted Immich library root." >&2
    exit 1
  fi

  echo "Library mount looks ready: ${path}"
}

command="${1:-}"
case "${command}" in
  config)
    ensure_env
    validate_remote_app_env
    compose config
    ;;
  mount-library)
    mount_library
    ;;
  umount-library)
    umount_library
    ;;
  check-library)
    mount_library
    check_library
    ;;
  pull)
    ensure_env
    validate_remote_app_env
    compose pull
    ;;
  up)
    ensure_env
    validate_remote_app_env
    mount_library
    check_library
    compose pull
    compose up -d
    ;;
  down)
    ensure_env
    validate_remote_app_env
    compose down
    remove_images
    umount_library
    ;;
  logs)
    ensure_env
    compose logs -f --tail=200
    ;;
  ps)
    ensure_env
    compose ps
    ;;
  lock-env)
    lock_env
    ;;
  unlock-env)
    unlock_env
    ;;
  *)
    usage
    exit 1
    ;;
esac
