#!/usr/bin/env bash
# Infrastructure management: start, stop, and manage infra containers.

# Starts an infrastructure resource if not already running.
# Args: $1 - resource name (e.g., sql_server, kafka)
# Returns: 0 on success, 1 on failure
start_infra() {
  local resource="${1}"
  local compose_file="${INFRA_DIR}/${resource}/docker-compose.yml"

  if [[ ! -f "${compose_file}" ]]; then
    log_error "Compose file not found: ${compose_file}"
    return 1
  fi

  local container_name="infra-${resource}"

  if is_container_running "${container_name}"; then
    local port
    port="$(get_port "${resource}" 2>/dev/null || echo "?")"
    log_success "${resource} :${port} (already running)"
    return 0
  fi

  log_info "Starting ${resource}..."

  # Generate .env from config YAMLs (single source of truth)
  if ! generate_infra_env "${resource}" >/dev/null; then
    log_error "Failed to generate .env for ${resource}"
    return 1
  fi

  # Start the container (docker compose reads .env automatically)
  if ! (cd "${INFRA_DIR}/${resource}" && docker compose up -d 2>&1); then
    log_error "Failed to start ${resource}"
    return 1
  fi

  # Wait for healthy
  wait_for_healthy "${container_name}" 60

  port="$(get_port "${resource}" 2>/dev/null || echo "?")"
  log_success "${resource} :${port} (started)"
}

# Stops an infrastructure resource.
# Args: $1 - resource name
# Returns: 0 on success
stop_infra() {
  local resource="${1}"
  local compose_file="${INFRA_DIR}/${resource}/docker-compose.yml"
  local container_name="infra-${resource}"

  if ! is_container_running "${container_name}"; then
    log_info "${resource} is not running"
    return 0
  fi

  log_info "Stopping ${resource}..."
  (cd "${INFRA_DIR}/${resource}" && docker compose down 2>&1)
  log_success "${resource} stopped"
}

# Starts all infrastructure dependencies for a project.
# Args: $1 - path to df.yml
# Returns: 0 if all started, 1 if any failed
start_all_deps() {
  local df_yml="${1}"
  local failed=0

  ensure_network

  local deps
  deps="$(resolve_deps "${df_yml}")"

  while IFS= read -r dep; do
    [[ -z "${dep}" ]] && continue

    if ! start_infra "${dep}"; then
      failed=1
    fi
  done <<< "${deps}"

  return "${failed}"
}

# Stops infrastructure resources that are no longer needed by any running project.
# Args: $1 - resource name, $2 - current app name (to exclude from check)
# Returns: 0 if stopped, 1 if still in use
stop_infra_if_unused() {
  local resource="${1}"
  local exclude_app="${2}"

  local dependents
  dependents="$(find_dependents "${resource}")"

  # Remove the excluded app from dependents list
  dependents="$(echo "${dependents}" | grep -v "^${exclude_app}$" || true)"

  if [[ -z "${dependents}" ]]; then
    stop_infra "${resource}"
    return 0
  else
    log_info "${resource} still in use by: $(echo "${dependents}" | tr '\n' ', ' | sed 's/,$//')"
    return 1
  fi
}
