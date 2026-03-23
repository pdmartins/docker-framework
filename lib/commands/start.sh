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
# Args: $@ - options
#   --no-init    Skip init scripts
#   --nowait     Start in background, do not wait for healthcheck
#   -f|--follow  Stream container logs after starting (foreground)
cmd_start() {
  local skip_init=false
  local nowait=false
  local follow=false
  local dry_run=false

  local project_slug=""

  # Parse flags
  while [[ $# -gt 0 ]]; do
    case "${1}" in
      --no-init)       skip_init=true; shift ;;
      --nowait)        nowait=true; shift ;;
      -f|--follow)     follow=true; shift ;;
      --dry-run)       dry_run=true; shift ;;
      -h|--help)       _start_usage; return 0 ;;
      -*)              log_error "Unknown option: ${1}"; return 1 ;;
      *)               [[ -z "${project_slug}" ]] && project_slug="${1}" || { log_error "Unexpected argument: ${1}"; return 1; }; shift ;;
    esac
  done

  # If the argument matches a platform service, start it directly
  if [[ -n "${project_slug}" ]] && is_valid_platform "${project_slug}"; then
    validate_prerequisites || return 1
    ensure_network
    start_platform "${project_slug}"
    return $?
  fi

  # If no argument and CWD is inside platform/, detect the service from the path
  if [[ -z "${project_slug}" ]]; then
    local platform_svc
    platform_svc="$(detect_platform_cwd)"
    if [[ -n "${platform_svc}" ]] && is_valid_platform "${platform_svc}"; then
      validate_prerequisites || return 1
      ensure_network
      start_platform "${platform_svc}"
      return $?
    fi
  fi

  local DF_PROJECT_DIR
  if [[ -n "${project_slug}" ]]; then
    DF_PROJECT_DIR="$(resolve_project_dir_by_slug "${project_slug}")" || return 1
  else
    DF_PROJECT_DIR="${PWD}"
  fi

  validate_project_context || return 1
  validate_prerequisites || return 1

  local df_yml
  df_yml="$(find_df_yml)"

  # Resolve project metadata
  resolve_project_metadata "${df_yml}"

  log_header "df start — ${PROJECT_SLUG}"
  echo ""

  # Validate dependencies exist
  validate_deps "${df_yml}" || return 1

  # Export flags so infra.sh can use them
  export DF_NOWAIT="${nowait}"
  export DF_DRY_RUN="${dry_run}"

  if [[ "${dry_run}" == true ]]; then
    log_warn "DRY-RUN mode: no Docker commands will be executed"
    echo ""
  fi

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
    log_step "Starting project services..."

    local app_dir
    app_dir="$(dirname "${df_yml}")"

    # Collect compose files for --follow mode
    local compose_files=()

    while IFS= read -r svc; do
      [[ -z "${svc}" ]] && continue
      local svc_dir="${app_dir}/${svc}"

      if [[ -d "${svc_dir}" ]] && [[ -f "${svc_dir}/docker-compose.yml" ]]; then
        if [[ "${dry_run}" == true ]]; then
          log_step "[DRY-RUN] Would start service: ${svc} (${svc_dir}/docker-compose.yml)"
        elif [[ "${follow}" == true ]]; then
          # Start detached first so deps are up, then we'll follow
          log_step "Starting service: ${svc}..."
          docker compose -f "${svc_dir}/docker-compose.yml" \
            --project-name "${PROJECT_SLUG}" up -d --build 2>&1 \
            || { log_error "Failed to start service: ${svc}"; continue; }
          log_success "${svc} (started)"
          compose_files+=( "-f" "${svc_dir}/docker-compose.yml" )
        else
          log_step "Starting service: ${svc}..."
          if ! docker compose -f "${svc_dir}/docker-compose.yml" \
               --project-name "${PROJECT_SLUG}" up -d --build 2>&1; then
            log_error "Failed to start service: ${svc}"
          else
            log_success "${svc} (started)"
          fi
        fi
      else
        log_warn "Service directory or compose file not found: ${svc_dir}"
      fi
    done <<< "${service_deps}"

    # Stream logs if --follow requested and we have services
    if [[ "${follow}" == true ]] && [[ "${#compose_files[@]}" -gt 0 ]]; then
      echo ""
      log_detail "Following logs (Ctrl+C to stop)..."
      log_separator
      docker compose "${compose_files[@]}" \
        --project-name "${PROJECT_SLUG}" logs --follow
      return 0
    fi
  fi

  echo ""
  log_separator
  log_success "All services are up!"
}

# Shows usage for the start command.
_start_usage() {
  cat <<EOF
Usage: df start [project] [options]

Start platform services, infrastructure dependencies, and project services.

Arguments:
  project   Project slug (e.g. project-pm-obsidian). Defaults to current directory.

Options:
  --no-init       Skip running init scripts
  --nowait        Start in background without waiting for healthcheck
  -f, --follow    Stay attached and stream logs after starting
  --dry-run       Simulate start without executing any Docker commands
  -h, --help      Show this help message

This command must be run from a project directory containing a df.yml file.
EOF
}
