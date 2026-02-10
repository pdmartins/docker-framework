#!/usr/bin/env bash
# Command: df start
# Description: Start infrastructure dependencies and project

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

# Starts infrastructure dependencies and the project application.
# Flow:
#   1. Read df.yml for dependencies
#   2. Start each infra dependency (if not running)
#   3. Wait for healthchecks
#   4. Run init scripts (idempotent)
#   5. Start the project container
# Args: $@ - options (--no-init to skip init scripts)
cmd_start() {
  local skip_init=false

  # Parse flags
  while [[ $# -gt 0 ]]; do
    case "${1}" in
      --no-init)  skip_init=true; shift ;;
      -h|--help)  _start_usage; return 0 ;;
      *)          log_error "Unknown option: ${1}"; return 1 ;;
    esac
  done

  validate_project_context || return 1
  validate_prerequisites || return 1

  local df_yml
  df_yml="$(find_df_yml)"

  local app_name
  app_name="$(get_app_name "${df_yml}")"

  log_info "Starting ${app_name}..."
  echo ""

  # Validate dependencies exist
  validate_deps "${df_yml}" || return 1

  # Start infrastructure dependencies
  start_all_deps "${df_yml}" || return 1

  # Run init scripts
  if [[ "${skip_init}" == false ]]; then
    run_all_init_scripts "${df_yml}" || log_warn "Some init scripts failed"
  fi

  # Start the project
  log_info "Starting ${app_name} application..."
  local app_dir
  app_dir="$(dirname "${df_yml}")"

  # Generate .env for the project from config YAMLs
  if ! generate_project_env "${df_yml}" >/dev/null; then
    log_error "Failed to generate .env for ${app_name}"
    return 1
  fi

  if ! (cd "${app_dir}" && docker compose up -d --build 2>&1); then
    log_error "Failed to start ${app_name}"
    return 1
  fi

  local project_name
  project_name="$(get_project_name "${df_yml}")"
  local app_port
  app_port="$(get_project_port "${app_name}" "${project_name}" 2>/dev/null || echo "?")"
  log_success "${app_name} :${app_port} (started)"
  echo ""
  log_success "All services are up!"
}

# Shows usage for the start command.
_start_usage() {
  cat <<EOF
Usage: df start [options]

Start infrastructure dependencies and the project application.

Options:
  --no-init    Skip running init scripts
  -h, --help   Show this help message

This command must be run from a project app directory containing a df.yml file.
EOF
}
