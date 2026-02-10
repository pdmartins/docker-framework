#!/usr/bin/env bash
# Command: df stop
# Description: Stop the project and optionally unused infrastructure

# shellcheck source=../core.sh
source "${LIB_DIR}/core.sh"
# shellcheck source=../config.sh
source "${LIB_DIR}/config.sh"
# shellcheck source=../deps.sh
source "${LIB_DIR}/deps.sh"
# shellcheck source=../infra.sh
source "${LIB_DIR}/infra.sh"

# Stops the project and optionally unused infrastructure.
# Flow:
#   1. Stop the project container
#   2. Check each infra dependency
#   3. Stop infra if no other project depends on it (with --with-infra)
# Args: $@ - options (--with-infra to also stop unused infra)
cmd_stop() {
  local with_infra=false

  while [[ $# -gt 0 ]]; do
    case "${1}" in
      --with-infra)  with_infra=true; shift ;;
      -h|--help)     _stop_usage; return 0 ;;
      *)             log_error "Unknown option: ${1}"; return 1 ;;
    esac
  done

  validate_project_context || return 1

  local df_yml
  df_yml="$(find_df_yml)"

  local app_name
  app_name="$(get_app_name "${df_yml}")"

  # Stop the project
  log_info "Stopping ${app_name}..."
  local app_dir
  app_dir="$(dirname "${df_yml}")"

  if is_container_running "${app_name}"; then
    (cd "${app_dir}" && docker compose down 2>&1)
    log_success "${app_name} stopped"
  else
    log_info "${app_name} is not running"
  fi

  # Optionally stop unused infra
  if [[ "${with_infra}" == true ]]; then
    echo ""
    log_info "Checking infrastructure dependencies..."

    local deps
    deps="$(resolve_deps "${df_yml}")"

    while IFS= read -r dep; do
      [[ -z "${dep}" ]] && continue
      stop_infra_if_unused "${dep}" "${app_name}"
    done <<< "${deps}"
  fi

  echo ""
  log_success "Done"
}

# Shows usage for the stop command.
_stop_usage() {
  cat <<EOF
Usage: df stop [options]

Stop the project application.

Options:
  --with-infra   Also stop infrastructure resources not used by other projects
  -h, --help     Show this help message
EOF
}
