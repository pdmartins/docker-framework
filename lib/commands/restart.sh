#!/usr/bin/env bash
# Command: df restart
# Description: Restart the project and its dependencies

# Restarts the project and optionally its infrastructure.
# Args: $@ - options
#   --with-infra         Also restart infrastructure dependencies
#   --nowait             Don't wait for healthchecks
#   -f|--follow          Stream logs after restart
cmd_restart() {
  local restart_infra=false
  local follow=false
  local nowait=false

  local project_slug=""

  while [[ $# -gt 0 ]]; do
    case "${1}" in
      --with-infra)    restart_infra=true; shift ;;
      --nowait)        nowait=true; shift ;;
      -f|--follow)     follow=true; shift ;;
      -h|--help)       _restart_usage; return 0 ;;
      -*)              log_error "Unknown option: ${1}"; return 1 ;;
      *)               [[ -z "${project_slug}" ]] && project_slug="${1}" || { log_error "Unexpected argument: ${1}"; return 1; }; shift ;;
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

  # Build start flags to carry forward
  local start_args=("--no-init")
  [[ "${nowait}" == true ]]   && start_args+=("--nowait")
  [[ "${follow}" == true ]]   && start_args+=("-f")
  [[ -n "${project_slug}" ]]  && start_args+=("${project_slug}")

  # Start everything back up
  cmd_start "${start_args[@]}"
}

# Shows usage for the restart command.
_restart_usage() {
  cat <<EOF
Usage: df restart [project] [options]

Restart the project services.

Arguments:
  project   Project slug (e.g. project-pm-obsidian). Defaults to current directory.

Options:
  --with-infra   Also restart infrastructure dependencies
  --nowait       Don't wait for healthchecks after restart
  -f, --follow   Stream logs after restart
  -h, --help     Show this help message
EOF
}
