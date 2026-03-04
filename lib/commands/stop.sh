#!/usr/bin/env bash
# Command: df stop
# Description: Stop the project services and infra (not platform)

# Stops project services and infrastructure. Does NOT stop platform services.
# Args: $@ - options
cmd_stop() {
  while [[ $# -gt 0 ]]; do
    case "${1}" in
      -h|--help)     _stop_usage; return 0 ;;
      *)             log_error "Unknown option: ${1}"; return 1 ;;
    esac
  done

  validate_project_context || return 1

  local df_yml
  df_yml="$(find_df_yml)"

  resolve_project_metadata "${df_yml}"

  log_info "Stopping ${PROJECT_SLUG}..."

  # Stop project services
  local service_deps
  service_deps="$(resolve_service_deps "${df_yml}")"

  local app_dir
  app_dir="$(dirname "${df_yml}")"

  while IFS= read -r svc; do
    [[ -z "${svc}" ]] && continue
    local svc_dir="${app_dir}/${svc}"

    if [[ -f "${svc_dir}/docker-compose.yml" ]]; then
      log_info "Stopping service: ${svc}..."
      docker compose -f "${svc_dir}/docker-compose.yml" \
        --project-name "${PROJECT_SLUG}" down 2>&1
      log_success "${svc} stopped"
    fi
  done <<< "${service_deps}"

  # Stop infra dependencies
  stop_all_deps "${df_yml}"

  echo ""
  log_success "Done (platform services left running)"
}

# Shows usage for the stop command.
_stop_usage() {
  cat <<EOF
Usage: df stop [options]

Stop project services and infrastructure dependencies.
Platform services (shared) are NOT stopped.

Options:
  -h, --help     Show this help message
EOF
}
