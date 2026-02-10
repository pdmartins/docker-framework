#!/usr/bin/env bash
# Command: df restart
# Description: Restart the project and its dependencies

# shellcheck source=../core.sh
source "${LIB_DIR}/core.sh"
# shellcheck source=../config.sh
source "${LIB_DIR}/config.sh"
# shellcheck source=../deps.sh
source "${LIB_DIR}/deps.sh"
# shellcheck source=../infra.sh
source "${LIB_DIR}/infra.sh"

# Restarts the project application and optionally its infrastructure.
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

  local app_name
  app_name="$(get_app_name "${df_yml}")"

  log_info "Restarting ${app_name}..."

  # Stop the project
  local app_dir
  app_dir="$(dirname "${df_yml}")"

  if is_container_running "${app_name}"; then
    (cd "${app_dir}" && docker compose down 2>&1)
  fi

  # Restart infra if requested
  if [[ "${restart_infra}" == true ]]; then
    local deps
    deps="$(resolve_deps "${df_yml}")"

    while IFS= read -r dep; do
      [[ -z "${dep}" ]] && continue
      stop_infra "${dep}"
    done <<< "${deps}"
  fi

  echo ""

  # Start everything back up
  cmd_start --no-init
}

# Shows usage for the restart command.
_restart_usage() {
  cat <<EOF
Usage: df restart [options]

Restart the project application.

Options:
  --with-infra   Also restart infrastructure dependencies
  -h, --help     Show this help message
EOF
}
