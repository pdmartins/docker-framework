#!/usr/bin/env bash
# Command: df stop
# Description: Stop the project services and infra (not platform)

# Stops project services and infrastructure. Does NOT stop platform services.
# Args: $@ - options
#   -v|--remove-volumes  Also remove Docker volumes when stopping
#   --all                Stop ALL managed containers (platform + infra + projects)
cmd_stop() {
  local remove_volumes=false
  local stop_all=false
  local dry_run=false

  local project_slug=""

  while [[ $# -gt 0 ]]; do
    case "${1}" in
      -v|--remove-volumes)  remove_volumes=true; shift ;;
      --all)                stop_all=true; shift ;;
      --dry-run)            dry_run=true; shift ;;
      -h|--help)            _stop_usage; return 0 ;;
      -*)                   log_error "Unknown option: ${1}"; return 1 ;;
      *)                    [[ -z "${project_slug}" ]] && project_slug="${1}" || { log_error "Unexpected argument: ${1}"; return 1; }; shift ;;
    esac
  done

  export DF_DRY_RUN="${dry_run}"
  if [[ "${dry_run}" == true ]]; then
    log_warn "DRY-RUN mode: no Docker commands will be executed"
    echo ""
  fi

  # If the argument matches a platform service, stop it directly
  if [[ -n "${project_slug}" ]] && is_valid_platform "${project_slug}"; then
    stop_platform "${project_slug}"
    return $?
  fi

  # If no argument and CWD is inside platform/, detect the service from the path
  if [[ -z "${project_slug}" ]]; then
    local platform_svc
    platform_svc="$(detect_platform_cwd)"
    if [[ -n "${platform_svc}" ]] && is_valid_platform "${platform_svc}"; then
      stop_platform "${platform_svc}"
      return $?
    fi
  fi

  local DF_PROJECT_DIR
  if [[ -n "${project_slug}" ]]; then
    DF_PROJECT_DIR="$(resolve_project_dir_by_slug "${project_slug}")" || return 1
  else
    DF_PROJECT_DIR="${PWD}"
  fi

  # --all: stop every managed container regardless of project context
  if [[ "${stop_all}" == true ]]; then
    log_header "df stop --all"
    echo ""
    local stopped=0 skipped=0
    while IFS= read -r name; do
      [[ -z "${name}" ]] && continue
      if docker stop "${name}" &>/dev/null; then
        log_success "${name} (stopped)"
        stopped=$(( stopped + 1 ))
      else
        log_detail "${name} (already stopped)"
        skipped=$(( skipped + 1 ))
      fi
    done < <(docker ps -a \
      --filter "label=managed-by=docker-framework" \
      --format "{{.Names}}" 2>/dev/null || true)
    echo ""
    log_separator
    log_success "Stopped: ${stopped}  |  Already stopped: ${skipped}"
    return 0
  fi

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
      if [[ "${dry_run}" == true ]]; then
        log_step "[DRY-RUN] Would stop service: ${svc} (${svc_dir}/docker-compose.yml)"
      else
        log_info "Stopping service: ${svc}..."
        local down_args=()
        [[ "${remove_volumes}" == true ]] && down_args+=("-v")
        docker compose -f "${svc_dir}/docker-compose.yml" \
          --project-name "${PROJECT_SLUG}" down "${down_args[@]}" 2>&1
        log_success "${svc} stopped"
      fi
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
Usage: df stop [project] [options]

Stop project services and infrastructure dependencies.
Platform services (shared) are NOT stopped (unless --all is used).

Arguments:
  project   Project slug (e.g. project-pm-obsidian). Defaults to current directory.

Options:
  -v, --remove-volumes   Also remove Docker volumes when stopping
  --all                  Stop ALL managed containers (platform + infra + projects)
  --dry-run              Simulate stop without executing any Docker commands
  -h, --help             Show this help message
EOF
}
