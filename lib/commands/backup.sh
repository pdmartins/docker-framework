#!/usr/bin/env bash
# Command: df backup / df restore
# Description: Backup and restore Docker volumes for managed containers

# Backup storage root: defaults to ~/docker-framework-backups unless overridden
_BACKUP_DIR="${DF_BACKUP_DIR:-${HOME}/docker-framework-backups}"

# Ensures the backup directory exists.
_backup_ensure_dir() {
  mkdir -p "${_BACKUP_DIR}"
}

# Returns the list of named volumes mounted on a container.
# Args: $1 - container name
# Output: one volume name per line
_backup_get_volumes() {
  local container="${1}"
  docker inspect --format \
    '{{range .Mounts}}{{if eq .Type "volume"}}{{.Name}}{{"\n"}}{{end}}{{end}}' \
    "${container}" 2>/dev/null | grep -v '^$' || true
}

# Backs up a single named volume to a .zip archive in _BACKUP_DIR.
# Args: $1 - volume name
_backup_volume() {
  local vol="${1}"
  _backup_ensure_dir

  local vol_path
  vol_path="$(docker volume inspect --format '{{.Mountpoint}}' "${vol}" 2>/dev/null || true)"

  if [[ -z "${vol_path}" ]]; then
    log_warn "Volume not found or has no mountpoint: ${vol}"
    return 1
  fi

  local archive="${_BACKUP_DIR}/${vol}.zip"
  log_step "Backing up volume: ${vol}..."

  if zip -r "${archive}" "${vol_path}" -x "*.sock" &>/dev/null; then
    log_detail "→ ${archive}"
    log_success "${vol} (backed up)"
  else
    log_error "Failed to backup volume: ${vol}"
    return 1
  fi
}

# Restores a single volume from a .zip archive in _BACKUP_DIR.
# Creates a safety backup of current data before restoring.
# Args: $1 - volume name
_restore_volume() {
  local vol="${1}"
  local archive="${_BACKUP_DIR}/${vol}.zip"

  if [[ ! -f "${archive}" ]]; then
    log_error "Backup archive not found: ${archive}"
    return 1
  fi

  local vol_path
  vol_path="$(docker volume inspect --format '{{.Mountpoint}}' "${vol}" 2>/dev/null || true)"

  if [[ -z "${vol_path}" ]]; then
    log_warn "Volume not found (may be recreated on start): ${vol}"
    vol_path=""
  fi

  # Safety backup before overwriting
  if [[ -n "${vol_path}" ]] && [[ -d "${vol_path}" ]]; then
    local safety="${_BACKUP_DIR}/${vol}_before_restore_$(date +%Y%m%d_%H%M%S).zip"
    log_step "Creating safety backup: $(basename "${safety}")..."
    zip -r "${safety}" "${vol_path}" -x "*.sock" &>/dev/null \
      && log_detail "→ ${safety}" \
      || log_warn "Safety backup failed — proceeding anyway"
  fi

  log_step "Restoring volume: ${vol}..."

  if [[ -n "${vol_path}" ]]; then
    # Clear existing data
    rm -rf "${vol_path:?}"/* 2>/dev/null || true
    unzip -q "${archive}" -d "/" &>/dev/null \
      && log_success "${vol} (restored)" \
      || { log_error "Failed to restore volume: ${vol}"; return 1; }
  else
    log_warn "Cannot restore: volume mountpoint unavailable. Start the service first."
    return 1
  fi
}

# Lists all backup archives in _BACKUP_DIR.
_backup_list() {
  log_header "df backup list"
  echo ""

  if [[ ! -d "${_BACKUP_DIR}" ]] || [[ -z "$(ls -A "${_BACKUP_DIR}" 2>/dev/null)" ]]; then
    log_info "No backups found in ${_BACKUP_DIR}"
    return 0
  fi

  printf "  ${COLOR_GRAY}%-50s  %10s  %s${COLOR_RESET}\n" "ARCHIVE" "SIZE" "DATE"
  echo "  ${COLOR_GRAY}$(printf '─%.0s' $(seq 1 78))${COLOR_RESET}"

  local count=0
  while IFS= read -r archive; do
    [[ -f "${archive}" ]] || continue
    local name size date
    name="$(basename "${archive}")"
    size="$(du -sh "${archive}" 2>/dev/null | cut -f1)"
    date="$(date -r "${archive}" '+%Y-%m-%d %H:%M' 2>/dev/null || stat -c '%y' "${archive}" 2>/dev/null | cut -d' ' -f1-2 | cut -c1-16)"
    printf "  %-50s  %10s  %s\n" "${name}" "${size}" "${date}"
    count=$(( count + 1 ))
  done < <(find "${_BACKUP_DIR}" -maxdepth 1 -name "*.zip" | sort)

  echo "  ${COLOR_GRAY}$(printf '─%.0s' $(seq 1 78))${COLOR_RESET}"
  printf "  ${COLOR_GRAY}%d archive(s) in %s${COLOR_RESET}\n\n" "${count}" "${_BACKUP_DIR}"
}

# Main backup command dispatcher.
# Usage:
#   df backup [list]                 List all archives
#   df backup [container]            Backup volumes of container (or all managed)
#   df restore [container]           Restore volumes of container (or all managed)
cmd_backup() {
  case "${1:-}" in
    list)        _backup_list ;;
    -h|--help)   _backup_usage; return 0 ;;
    "")
      # Backup all managed containers
      log_header "df backup — all containers"
      local found=false
      while IFS= read -r name; do
        [[ -z "${name}" ]] && continue
        found=true
        local vols
        vols="$(_backup_get_volumes "${name}")"
        if [[ -z "${vols}" ]]; then
          log_detail "${name}: no named volumes"
          continue
        fi
        while IFS= read -r vol; do
          [[ -z "${vol}" ]] && continue
          _backup_volume "${vol}" || true
        done <<< "${vols}"
      done < <(docker ps -a \
        --filter "label=managed-by=docker-framework" \
        --format "{{.Names}}" 2>/dev/null || true)
      [[ "${found}" == false ]] && log_warn "No managed containers found"
      echo ""
      log_success "Backup complete — archives in ${_BACKUP_DIR}"
      ;;
    *)
      # Backup specific container
      local container="${1}"
      if ! docker ps -a --filter "name=^${container}$" --format '{{.Names}}' \
          | grep -q "^${container}$"; then
        log_error "Container not found: ${container}"
        return 1
      fi
      log_header "df backup — ${container}"
      local vols
      vols="$(_backup_get_volumes "${container}")"
      if [[ -z "${vols}" ]]; then
        log_warn "${container} has no named volumes to backup"
        return 0
      fi
      while IFS= read -r vol; do
        [[ -z "${vol}" ]] && continue
        _backup_volume "${vol}" || true
      done <<< "${vols}"
      echo ""
      log_success "Backup complete — archives in ${_BACKUP_DIR}"
      ;;
  esac
}

# Main restore command dispatcher.
cmd_restore() {
  case "${1:-}" in
    -h|--help)  _restore_usage; return 0 ;;
    "")
      # Restore all managed containers
      log_warn "This will OVERWRITE data for ALL managed containers."
      read -rp "Are you sure? (y/N) " confirm
      [[ "${confirm}" != "y" && "${confirm}" != "Y" ]] && { log_info "Aborted"; return 0; }
      log_header "df restore — all containers"
      while IFS= read -r name; do
        [[ -z "${name}" ]] && continue
        local vols
        vols="$(_backup_get_volumes "${name}")"
        while IFS= read -r vol; do
          [[ -z "${vol}" ]] && continue
          _restore_volume "${vol}" || true
        done <<< "${vols}"
      done < <(docker ps -a \
        --filter "label=managed-by=docker-framework" \
        --format "{{.Names}}" 2>/dev/null || true)
      ;;
    *)
      local container="${1}"
      log_warn "This will OVERWRITE data for ${container}."
      read -rp "Are you sure? (y/N) " confirm
      [[ "${confirm}" != "y" && "${confirm}" != "Y" ]] && { log_info "Aborted"; return 0; }
      log_header "df restore — ${container}"
      local vols
      vols="$(_backup_get_volumes "${container}")"
      if [[ -z "${vols}" ]]; then
        log_warn "${container} has no named volumes to restore"
        return 0
      fi
      while IFS= read -r vol; do
        [[ -z "${vol}" ]] && continue
        _restore_volume "${vol}" || true
      done <<< "${vols}"
      ;;
  esac

  echo ""
  log_success "Restore complete"
}

# Shows usage for the backup command.
_backup_usage() {
  cat <<EOF
Usage: df backup [container|list] [options]

Backup Docker volumes for managed containers.

Arguments:
  (none)      Backup volumes from ALL managed containers
  list        List all available backup archives
  container   Backup volumes of a specific container

Options:
  -h, --help  Show this help message

Backups are stored in: ${_BACKUP_DIR}
Override with: export DF_BACKUP_DIR=/path

Examples:
  df backup                       # Backup all managed containers
  df backup list                  # List archives
  df backup platform-sonarqube    # Backup SonarQube volumes
EOF
}

# Shows usage for the restore command.
_restore_usage() {
  cat <<EOF
Usage: df restore [container] [options]

Restore Docker volumes from backup archives.
A safety backup is created automatically before each restore.

Arguments:
  (none)      Restore ALL managed containers (requires confirmation)
  container   Restore a specific container's volumes

Options:
  -h, --help  Show this help message

Backups are read from: ${_BACKUP_DIR}
Override with: export DF_BACKUP_DIR=/path

Examples:
  df restore platform-sonarqube   # Restore SonarQube volumes
EOF
}
