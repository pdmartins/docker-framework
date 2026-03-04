#!/usr/bin/env bash
# Command: df start
# Description: Start platform, infra dependencies, and project services

# Starts dependencies and the project services.
# Flow:
#   1. Read df.yml
#   2. Start platform dependencies (if not running)
#   3. Start infra dependencies via templates
#   4. Run init scripts (idempotent)
#   5. Start project services
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

  # Resolve project metadata
  resolve_project_metadata "${df_yml}"

  log_info "Starting ${PROJECT_SLUG}..."
  echo ""

  # Validate dependencies exist
  validate_deps "${df_yml}" || return 1

  # Start platform + infra dependencies
  start_all_deps "${df_yml}" || return 1

  # Run init scripts
  if [[ "${skip_init}" == false ]]; then
    run_all_init_scripts "${df_yml}" || log_warn "Some init scripts failed"
  fi

  # Start project services
  local service_deps
  service_deps="$(resolve_service_deps "${df_yml}")"

  if [[ -n "${service_deps}" ]]; then
    echo ""
    log_info "Starting project services..."

    local app_dir
    app_dir="$(dirname "${df_yml}")"

    while IFS= read -r svc; do
      [[ -z "${svc}" ]] && continue
      local svc_dir="${app_dir}/${svc}"

      if [[ -d "${svc_dir}" ]] && [[ -f "${svc_dir}/docker-compose.yml" ]]; then
        log_info "Starting service: ${svc}..."
        if ! docker compose -f "${svc_dir}/docker-compose.yml" \
             --project-name "${PROJECT_SLUG}" up -d --build 2>&1; then
          log_error "Failed to start service: ${svc}"
        else
          log_success "${svc} (started)"
        fi
      else
        log_warn "Service directory or compose file not found: ${svc_dir}"
      fi
    done <<< "${service_deps}"
  fi

  echo ""
  log_success "All services are up!"
}

# Shows usage for the start command.
_start_usage() {
  cat <<EOF
Usage: df start [options]

Start platform services, infrastructure dependencies, and project services.

Options:
  --no-init    Skip running init scripts
  -h, --help   Show this help message

This command must be run from a project directory containing a df.yml file.
EOF
}
