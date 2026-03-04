#!/usr/bin/env bash
# Command: df log
# Description: Show logs for the project or a specific resource

# Shows logs for a container.
# Args: $1 - resource name (optional, defaults to showing project help)
cmd_log() {
  local follow=false
  local tail_lines="100"
  local target=""

  while [[ $# -gt 0 ]]; do
    case "${1}" in
      -f|--follow)   follow=true; shift ;;
      -n|--tail)     tail_lines="${2}"; shift 2 ;;
      -h|--help)     _log_usage; return 0 ;;
      -*)            log_error "Unknown option: ${1}"; return 1 ;;
      *)             target="${1}"; shift ;;
    esac
  done

  local container_name=""
  local follow_flag=""

  if [[ "${follow}" == true ]]; then
    follow_flag="--follow"
  fi

  if [[ -n "${target}" ]]; then
    # Try platform-<target> first
    container_name="platform-${target}"
    if ! container_exists "${container_name}"; then
      # Try infra-<project_slug>-<target> if in a project context
      if [[ -f "df.yml" ]]; then
        local df_yml="${PWD}/df.yml"
        local project_slug
        project_slug="$(get_project_slug "${df_yml}")"
        container_name="infra-${project_slug}-${target}"
      fi

      if ! container_exists "${container_name}"; then
        # Try as raw container name
        container_name="${target}"
        if ! container_exists "${container_name}"; then
          log_error "Container not found: ${target}"
          return 1
        fi
      fi
    fi
  else
    # No target: require project context
    validate_project_context || return 1
    log_error "Specify a service name: df log <service>"
    return 1
  fi

  docker logs --tail "${tail_lines}" ${follow_flag} "${container_name}"
}

# Shows usage for the log command.
_log_usage() {
  cat <<EOF
Usage: df log [service] [options]

Show logs for a platform or infrastructure service.

Arguments:
  service        Name of the service (e.g., postgresql, kafka, sonarqube)

Options:
  -f, --follow   Follow log output
  -n, --tail N   Number of lines to show (default: 100)
  -h, --help     Show this help message

Examples:
  df log postgresql    # Logs for this project's PostgreSQL
  df log sonarqube     # Logs for platform SonarQube
  df log kafka -f      # Follow Kafka logs
EOF
}
