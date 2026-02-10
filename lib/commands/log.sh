#!/usr/bin/env bash
# Command: df log
# Description: Show logs for the project or a specific resource

# shellcheck source=../core.sh
source "${LIB_DIR}/core.sh"

# Shows logs for the current project or a specific infrastructure resource.
# Args: $1 - resource name (optional, defaults to current project)
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
    # Show logs for a specific resource
    container_name="infra-${target}"
    if ! container_exists "${container_name}"; then
      # Try without infra- prefix (might be an app name)
      container_name="${target}"
      if ! container_exists "${container_name}"; then
        log_error "Container not found: ${target} (tried infra-${target} and ${target})"
        return 1
      fi
    fi
  else
    # Show logs for current project
    validate_project_context || return 1

    local df_yml
    df_yml="$(find_df_yml)"

    container_name="$(get_app_name "${df_yml}")"
    if ! container_exists "${container_name}"; then
      log_error "Container ${container_name} not found. Is it running?"
      return 1
    fi
  fi

  docker logs --tail "${tail_lines}" ${follow_flag} "${container_name}"
}

# Shows usage for the log command.
_log_usage() {
  cat <<EOF
Usage: df log [resource] [options]

Show logs for the project or a specific resource.

Arguments:
  resource       Name of the resource (e.g., sql_server, kafka)
                 If omitted, shows logs for the current project

Options:
  -f, --follow   Follow log output
  -n, --tail N   Number of lines to show (default: 100)
  -h, --help     Show this help message

Examples:
  df log              # Logs for current project
  df log sql_server   # Logs for SQL Server
  df log -f           # Follow current project logs
EOF
}
