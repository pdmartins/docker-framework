#!/usr/bin/env bash
# Command: df restart
# Description: Restart the project and its dependencies

# Restarts the project and optionally its infrastructure.
# Args: $@ - options
cmd_restart() {
  local restart_infra=false

  while [[ $# -gt 0 ]]; do
    case "${1}" in
      --with-infra)  restart_infra=true; shift ;;
      -h|--help)     _restart_usage; return 0 ;;
      *)             log_error "Unknown option: ${1}"; return 1 ;;
    esac
  done

  validate_project_context || return 1

  local df_yml
  df_yml="$(find_df_yml)"

  resolve_project_metadata "${df_yml}"

  log_info "Restarting ${PROJECT_SLUG}..."

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
        --project-name "${PROJECT_SLUG}" down 2>&1
    fi
  done <<< "${service_deps}"

  # Restart infra if requested
  if [[ "${restart_infra}" == true ]]; then
    stop_all_deps "${df_yml}"
  fi

  echo ""

  # Start everything back up
  cmd_start --no-init
}

# Shows usage for the restart command.
_restart_usage() {
  cat <<EOF
Usage: df restart [options]

Restart the project services.

Options:
  --with-infra   Also restart infrastructure dependencies
  -h, --help     Show this help message
EOF
}
