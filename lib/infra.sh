#!/usr/bin/env bash
# Infrastructure and platform management: start, stop, manage containers via templates.

# --- Infra (per-project, template-based) ---

# Starts an infrastructure service for a project using the corresponding template.
# Args: $1 - service name, $2 - project slug, $3 - project data path,
#       $4 - squad index, $5 - project index
# Returns: 0 on success, 1 on failure
start_infra() {
  local service="${1}"
  local project_slug="${2}"
  local project_data_path="${3}"
  local squad_index="${4}"
  local project_index="${5}"

  local compose_file="${TEMPLATES_DIR}/${service}/docker-compose.yml"

  if [[ ! -f "${compose_file}" ]]; then
    log_error "Template not found: ${compose_file}"
    return 1
  fi

  local container_name="infra-${project_slug}-${service}"

  if is_container_running "${container_name}"; then
    local port
    port="$(get_host_port "${service}" "${squad_index}" "${project_index}" 2>/dev/null || echo "?")"
    log_success "${service} :${port} (already running)"
    return 0
  fi

  log_step "Starting ${service} for ${project_slug}..."

  # Ensure data directory exists
  mkdir -p "${project_data_path}/${service}"

  # Generate temporary .env
  local env_file
  env_file="$(generate_infra_env "${project_slug}" "${project_data_path}" "${squad_index}" "${project_index}")"

  # Load per-project credentials .env if present (overrides template defaults)
  local extra_env_args
  extra_env_args=()
  if [[ -n "${PROJECT_DIR:-}" && -f "${PROJECT_DIR}/.env" ]]; then
    extra_env_args=(--env-file "${PROJECT_DIR}/.env")
  fi

  local project_name="infra-${project_slug}"

  # Start the container
  if ! docker compose -f "${compose_file}" --env-file "${env_file}" "${extra_env_args[@]}" \
       --project-name "${project_name}" up -d 2>&1; then
    log_error "Failed to start ${service} for ${project_slug}"
    rm -f "${env_file}"
    return 1
  fi

  rm -f "${env_file}"

  # Wait for healthy unless --nowait was requested
  if [[ "${DF_NOWAIT:-false}" != "true" ]]; then
    wait_for_healthy "${container_name}" 60
  fi

  local port
  port="$(get_host_port "${service}" "${squad_index}" "${project_index}" 2>/dev/null || echo "?")"
  log_success "${service} :${port} (started)"
}

# Stops an infrastructure service for a project.
# Args: $1 - service name, $2 - project slug, $3 - project data path,
#       $4 - squad index, $5 - project index
# Returns: 0 on success
stop_infra() {
  local service="${1}"
  local project_slug="${2}"
  local project_data_path="${3}"
  local squad_index="${4}"
  local project_index="${5}"

  local compose_file="${TEMPLATES_DIR}/${service}/docker-compose.yml"
  local container_name="infra-${project_slug}-${service}"

  if ! is_container_running "${container_name}"; then
    log_info "${service} is not running for ${project_slug}"
    return 0
  fi

  log_step "Stopping ${service} for ${project_slug}..."

  local env_file
  env_file="$(generate_infra_env "${project_slug}" "${project_data_path}" "${squad_index}" "${project_index}")"

  # Load per-project credentials .env if present
  local extra_env_args
  extra_env_args=()
  if [[ -n "${PROJECT_DIR:-}" && -f "${PROJECT_DIR}/.env" ]]; then
    extra_env_args=(--env-file "${PROJECT_DIR}/.env")
  fi

  local project_name="infra-${project_slug}"

  docker compose -f "${compose_file}" --env-file "${env_file}" "${extra_env_args[@]}" \
    --project-name "${project_name}" down 2>&1

  rm -f "${env_file}"
  log_success "${service} stopped for ${project_slug}"
}

# --- Platform (shared services) ---

# Starts a platform service (shared, no project variables).
# Args: $1 - service name
# Returns: 0 on success, 1 on failure
start_platform() {
  local service="${1}"
  local compose_file="${PLATFORM_DIR}/${service}/docker-compose.yml"

  if [[ ! -f "${compose_file}" ]]; then
    log_error "Platform compose not found: ${compose_file}"
    return 1
  fi

  local container_name="platform-${service}"

  if is_container_running "${container_name}"; then
    log_success "${service} (platform, already running)"
    return 0
  fi

  log_info "Starting platform service: ${service}..."

  if ! docker compose -f "${compose_file}" --project-name "platform-${service}" up -d 2>&1; then
    log_error "Failed to start platform service: ${service}"
    return 1
  fi

  wait_for_healthy "${container_name}" 120

  log_success "${service} (platform, started)"
}

# Stops a platform service.
# Args: $1 - service name
# Returns: 0 on success
stop_platform() {
  local service="${1}"
  local compose_file="${PLATFORM_DIR}/${service}/docker-compose.yml"
  local container_name="platform-${service}"

  if ! is_container_running "${container_name}"; then
    log_info "${service} (platform) is not running"
    return 0
  fi

  log_info "Stopping platform service: ${service}..."
  docker compose -f "${compose_file}" --project-name "platform-${service}" down 2>&1
  log_success "${service} (platform) stopped"
}

# --- Container checks ---

# Checks if a managed container is running.
# For infra: looks for infra-<project_slug>-<service>
# For platform: looks for platform-<service>
# Args: $1 - service name, $2 - project slug (optional, omit for platform)
# Returns: 0 if running, 1 otherwise
is_managed_container_running() {
  local service="${1}"
  local project_slug="${2:-}"

  local container_name
  if [[ -n "${project_slug}" ]]; then
    container_name="infra-${project_slug}-${service}"
  else
    container_name="platform-${service}"
  fi

  is_container_running "${container_name}"
}

# --- Orchestration helpers ---

# Starts all dependencies for a project (platform + infra).
# Args: $1 - path to df.yml
# Returns: 0 if all started, 1 if any failed
start_all_deps() {
  local df_yml="${1}"
  local failed=0

  ensure_network

  # Resolve project metadata
  resolve_project_metadata "${df_yml}"

  # Start platform dependencies
  local platform_deps
  platform_deps="$(read_yaml "${df_yml}" '.dependencies.platform[]' 2>/dev/null || true)"

  while IFS= read -r dep; do
    [[ -z "${dep}" ]] && continue
    if ! start_platform "${dep}"; then
      failed=1
    fi
  done <<< "${platform_deps}"

  # Start infra dependencies
  local infra_deps
  infra_deps="$(read_yaml "${df_yml}" '.dependencies.infra[]' 2>/dev/null || true)"

  while IFS= read -r dep; do
    [[ -z "${dep}" ]] && continue
    if ! start_infra "${dep}" "${PROJECT_SLUG}" "${PROJECT_DATA_PATH}" "${SQUAD_INDEX}" "${PROJECT_INDEX}"; then
      failed=1
    fi
  done <<< "${infra_deps}"

  return "${failed}"
}

# Stops all infra and service dependencies for a project. Does NOT stop platform.
# Args: $1 - path to df.yml
# Returns: 0 on success
stop_all_deps() {
  local df_yml="${1}"

  resolve_project_metadata "${df_yml}"

  # Stop infra dependencies
  local infra_deps
  infra_deps="$(read_yaml "${df_yml}" '.dependencies.infra[]' 2>/dev/null || true)"

  while IFS= read -r dep; do
    [[ -z "${dep}" ]] && continue
    stop_infra "${dep}" "${PROJECT_SLUG}" "${PROJECT_DATA_PATH}" "${SQUAD_INDEX}" "${PROJECT_INDEX}"
  done <<< "${infra_deps}"
}
