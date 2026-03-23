#!/usr/bin/env bash
# Command: df platform
# Description: Manage platform services (start, stop, status)

_platform_usage() {
  cat <<EOF
Usage: df platform <subcommand> [service]

Manage shared platform services.

Subcommands:
  start <service>   Start a platform service (e.g. sonarqube)
  stop  <service>   Stop a platform service
  status            List all available platform services and their status

Options:
  -h, --help   Show this help message

Examples:
  df platform start sonarqube
  df platform stop sonarqube
  df platform status
EOF
}

# Lists all available platform services with their running status.
_platform_status() {
  local services=()

  while IFS= read -r compose_file; do
    local service
    service="$(basename "$(dirname "${compose_file}")")"
    services+=("${service}")
  done < <(find "${PLATFORM_DIR}" -name "docker-compose.yml" | sort)

  if [[ ${#services[@]} -eq 0 ]]; then
    log_info "No platform services found in ${PLATFORM_DIR}"
    return 0
  fi

  log_header "Platform Services"
  echo ""

  for service in "${services[@]}"; do
    local container_name="platform-${service}"
    if is_container_running "${container_name}"; then
      log_success "${service} (running)"
    else
      log_info "${service} (stopped)"
    fi
  done
}

# Entry point for the platform command.
# Args: $@ - subcommand and options
cmd_platform() {
  if [[ $# -eq 0 ]]; then
    _platform_usage
    return 0
  fi

  local subcommand="${1}"
  shift

  case "${subcommand}" in
    start)
      [[ $# -eq 0 ]] && { log_error "Missing service name"; _platform_usage; return 1; }
      local service="${1}"
      if ! is_valid_platform "${service}"; then
        log_error "Unknown platform service: ${service}"
        local available
        available="$(find "${PLATFORM_DIR}" -name "docker-compose.yml" \
          | sed "s|${PLATFORM_DIR}/||;s|/docker-compose.yml||" | sort | tr '\n' ' ')"
        log_error "Available: ${available}"
        return 1
      fi
      validate_prerequisites || return 1
      ensure_network
      start_platform "${service}"
      ;;
    stop)
      [[ $# -eq 0 ]] && { log_error "Missing service name"; _platform_usage; return 1; }
      local service="${1}"
      if ! is_valid_platform "${service}"; then
        log_error "Unknown platform service: ${service}"
        return 1
      fi
      stop_platform "${service}"
      ;;
    status)
      _platform_status
      ;;
    -h|--help)
      _platform_usage
      ;;
    *)
      log_error "Unknown subcommand: ${subcommand}"
      _platform_usage
      return 1
      ;;
  esac
}
