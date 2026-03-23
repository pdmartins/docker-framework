#!/usr/bin/env bash
# Dependency resolution: reads df.yml (new format) and resolves dependencies.

# Resolves infra dependencies from df.yml.
# Args: $1 - path to df.yml
# Returns: list of service names (stdout, one per line)
resolve_infra_deps() {
  local df_yml="${1}"

  if [[ ! -f "${df_yml}" ]]; then
    log_error "df.yml not found: ${df_yml}"
    return 1
  fi

  local result
  if ! result="$(yq '.dependencies.infra // [] | .[]' "${df_yml}" 2>&1)"; then
    log_error "Failed to parse dependencies.infra from ${df_yml}: ${result}"
    return 1
  fi
  echo "${result}"
}

# Resolves platform dependencies from df.yml.
# Args: $1 - path to df.yml
# Returns: list of service names (stdout, one per line)
resolve_platform_deps() {
  local df_yml="${1}"

  if [[ ! -f "${df_yml}" ]]; then
    log_error "df.yml not found: ${df_yml}"
    return 1
  fi

  local result
  if ! result="$(yq '.dependencies.platform // [] | .[]' "${df_yml}" 2>&1)"; then
    log_error "Failed to parse dependencies.platform from ${df_yml}: ${result}"
    return 1
  fi
  echo "${result}"
}

# Resolves service dependencies from df.yml.
# Args: $1 - path to df.yml
# Returns: list of service names (stdout, one per line)
resolve_service_deps() {
  local df_yml="${1}"

  if [[ ! -f "${df_yml}" ]]; then
    log_error "df.yml not found: ${df_yml}"
    return 1
  fi

  local result
  if ! result="$(yq '.dependencies.services // [] | .[]' "${df_yml}" 2>&1)"; then
    log_error "Failed to parse dependencies.services from ${df_yml}: ${result}"
    return 1
  fi
  echo "${result}"
}

# Checks if a service has a valid template.
# Args: $1 - service name
# Returns: 0 if valid, 1 otherwise
is_valid_template() {
  local service="${1}"
  [[ -f "${TEMPLATES_DIR}/${service}/docker-compose.yml" ]]
}

# Checks if a platform service exists.
# Args: $1 - service name
# Returns: 0 if valid, 1 otherwise
is_valid_platform() {
  local service="${1}"
  [[ -f "${PLATFORM_DIR}/${service}/docker-compose.yml" ]]
}

# Validates all dependencies in a df.yml.
# Args: $1 - path to df.yml
# Returns: 0 if all valid, 1 if any invalid
validate_deps() {
  local df_yml="${1}"
  local invalid=0

  # Validate platform deps
  local platform_deps
  platform_deps="$(resolve_platform_deps "${df_yml}")"

  while IFS= read -r dep; do
    [[ -z "${dep}" ]] && continue
    if ! is_valid_platform "${dep}"; then
      log_error "Unknown platform service: ${dep}"
      log_error "No docker-compose.yml found at platform/${dep}/"
      invalid=1
    fi
  done <<< "${platform_deps}"

  # Validate infra deps
  local infra_deps
  infra_deps="$(resolve_infra_deps "${df_yml}")"

  while IFS= read -r dep; do
    [[ -z "${dep}" ]] && continue
    if ! is_valid_template "${dep}"; then
      log_error "Unknown infrastructure service: ${dep}"
      log_error "No template found at templates/${dep}/"
      invalid=1
    fi
  done <<< "${infra_deps}"

  return "${invalid}"
}
