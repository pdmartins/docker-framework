#!/usr/bin/env bash
# Command: df reset
# Description: Reset project data, re-initialize, and restart

# Resets project data, re-runs init scripts, and restarts.
# Flow:
#   1. Stop project services
#   2. Stop infra and remove data
#   3. Re-run init scripts
#   4. Restart everything
# Args: $@ - options
cmd_reset() {
  local force=false

  local project_slug=""

  while [[ $# -gt 0 ]]; do
    case "${1}" in
      -f|--force)  force=true; shift ;;
      -h|--help)   _reset_usage; return 0 ;;
      -*)          log_error "Unknown option: ${1}"; return 1 ;;
      *)           [[ -z "${project_slug}" ]] && project_slug="${1}" || { log_error "Unexpected argument: ${1}"; return 1; }; shift ;;
    esac
  done

  local DF_PROJECT_DIR
  if [[ -n "${project_slug}" ]]; then
    DF_PROJECT_DIR="$(resolve_project_dir_by_slug "${project_slug}")" || return 1
  else
    DF_PROJECT_DIR="${PWD}"
  fi

  validate_project_context || return 1

  local df_yml
  df_yml="$(find_df_yml)"

  resolve_project_metadata "${df_yml}"

  # Confirm reset
  if [[ "${force}" == false ]]; then
    log_warn "This will DELETE all data for ${PROJECT_SLUG} and re-initialize."
    read -rp "Are you sure? (y/N) " confirm
    if [[ "${confirm}" != "y" && "${confirm}" != "Y" ]]; then
      log_info "Aborted"
      return 0
    fi
  fi

  log_info "Resetting ${PROJECT_SLUG}..."

  # Stop project services
  local service_deps
  service_deps="$(resolve_service_deps "${df_yml}")"
  local app_dir
  app_dir="$(dirname "${df_yml}")"

  while IFS= read -r svc; do
    [[ -z "${svc}" ]] && continue
    local svc_dir="${app_dir}/${svc}"
    if [[ -f "${svc_dir}/docker-compose.yml" ]]; then
      docker compose -f "${svc_dir}/docker-compose.yml" \
        --project-name "${PROJECT_SLUG}" down -v 2>&1
    fi
  done <<< "${service_deps}"

  # Stop infra
  stop_all_deps "${df_yml}"

  # Remove project data
  if [[ -d "${PROJECT_DATA_PATH}" ]]; then
    log_info "Removing project data at ${PROJECT_DATA_PATH}..."
    rm -rf "${PROJECT_DATA_PATH}"
    log_success "Project data removed"
  fi

  echo ""

  # Ensure infra is running for init scripts
  start_all_deps "${df_yml}" || return 1

  # Re-run init scripts
  log_info "Re-initializing ${PROJECT_SLUG}..."
  run_all_init_scripts "${df_yml}" || log_warn "Some init scripts failed"

  # Restart project services
  while IFS= read -r svc; do
    [[ -z "${svc}" ]] && continue
    local svc_dir="${app_dir}/${svc}"
    if [[ -d "${svc_dir}" ]] && [[ -f "${svc_dir}/docker-compose.yml" ]]; then
      log_info "Starting service: ${svc}..."
      docker compose -f "${svc_dir}/docker-compose.yml" \
        --project-name "${PROJECT_SLUG}" up -d --build 2>&1
      log_success "${svc} (started)"
    fi
  done <<< "${service_deps}"

  log_success "${PROJECT_SLUG} (reset complete)"
}

# Shows usage for the reset command.
_reset_usage() {
  cat <<EOF
Usage: df reset [project] [options]

Reset project data, re-run init scripts, and restart.

Arguments:
  project   Project slug (e.g. project-pm-obsidian). Defaults to current directory.

This will:
  1. Stop project services and remove volumes
  2. Remove project data directory
  3. Re-start infra and run init scripts
  4. Restart project services

Options:
  -f, --force   Skip confirmation prompt
  -h, --help    Show this help message
EOF
}
