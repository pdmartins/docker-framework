#!/usr/bin/env bash
# Command: df reset
# Description: Reset project data, re-initialize, and restart

# shellcheck source=../core.sh
source "${LIB_DIR}/core.sh"
# shellcheck source=../config.sh
source "${LIB_DIR}/config.sh"
# shellcheck source=../deps.sh
source "${LIB_DIR}/deps.sh"
# shellcheck source=../infra.sh
source "${LIB_DIR}/infra.sh"
# shellcheck source=../init.sh
source "${LIB_DIR}/init.sh"

# Resets project data, re-runs init scripts, and restarts.
# Flow:
#   1. Stop the project
#   2. Remove project-specific data (drop database, delete topics, etc.)
#   3. Re-run init scripts
#   4. Restart the project
# Args: $@ - options
cmd_reset() {
  local force=false

  while [[ $# -gt 0 ]]; do
    case "${1}" in
      -f|--force)  force=true; shift ;;
      -h|--help)   _reset_usage; return 0 ;;
      *)           log_error "Unknown option: ${1}"; return 1 ;;
    esac
  done

  validate_project_context || return 1

  local df_yml
  df_yml="$(find_df_yml)"

  local app_name
  app_name="$(get_app_name "${df_yml}")"

  # Confirm reset
  if [[ "${force}" == false ]]; then
    log_warn "This will DELETE all data for ${app_name} and re-initialize."
    read -rp "Are you sure? (y/N) " confirm
    if [[ "${confirm}" != "y" && "${confirm}" != "Y" ]]; then
      log_info "Aborted"
      return 0
    fi
  fi

  log_info "Resetting ${app_name}..."

  # Stop the project
  local app_dir
  app_dir="$(dirname "${df_yml}")"

  if is_container_running "${app_name}"; then
    (cd "${app_dir}" && docker compose down -v 2>&1)
    log_success "${app_name} stopped and volumes removed"
  fi

  # Ensure infra is running for init scripts
  start_all_deps "${df_yml}" || return 1

  # Re-run init scripts
  log_info "Re-initializing ${app_name}..."
  run_all_init_scripts "${df_yml}" || log_warn "Some init scripts failed"

  # Generate .env for the project from config YAMLs
  generate_project_env "${df_yml}" >/dev/null || true

  # Restart the project
  log_info "Restarting ${app_name}..."
  if ! (cd "${app_dir}" && docker compose up -d --build 2>&1); then
    log_error "Failed to restart ${app_name}"
    return 1
  fi

  local project_name
  project_name="$(get_project_name "${df_yml}")"
  local app_port
  app_port="$(get_project_port "${app_name}" "${project_name}" 2>/dev/null || echo "?")"
  log_success "${app_name} :${app_port} (reset complete)"
}

# Shows usage for the reset command.
_reset_usage() {
  cat <<EOF
Usage: df reset [options]

Reset project data, re-run init scripts, and restart.

This will:
  1. Stop the project and remove its volumes
  2. Re-run all init scripts (create databases, topics, etc.)
  3. Restart the project

Options:
  -f, --force   Skip confirmation prompt
  -h, --help    Show this help message
EOF
}
