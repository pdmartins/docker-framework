#!/usr/bin/env bash
# Configuration management: reads ports and credentials from YAML files.
# Infra config: ${INFRA_CONFIG_DIR}/ports.yml, credentials.yml
# Project config: ${ROOT_DIR}/{project}/config/ports.yml, credentials.yml
# Requires: yq

# Reads a value from a YAML file using yq.
# Args: $1 - file path, $2 - yq expression
# Returns: value (stdout)
read_yaml() {
  local file="${1}"
  local expression="${2}"

  if [[ ! -f "${file}" ]]; then
    log_error "Config file not found: ${file}"
    return 1
  fi

  yq "${expression}" "${file}"
}

# --- Infra config (shared) ---

# Gets the port for an infrastructure resource from infra/.config/ports.yml.
# Args: $1 - resource name (e.g., sql_server, kafka)
# Returns: port number (stdout)
get_port() {
  local resource="${1}"
  local port
  port="$(read_yaml "${INFRA_CONFIG_DIR}/ports.yml" ".${resource}")"

  if [[ -z "${port}" || "${port}" == "null" ]]; then
    log_error "Port not configured for resource: ${resource} in infra/.config/ports.yml"
    return 1
  fi

  echo "${port}"
}

# Gets a credential value for a resource from infra/.config/credentials.yml.
# Args: $1 - resource name, $2 - credential key
# Returns: credential value (stdout)
get_credential() {
  local resource="${1}"
  local key="${2}"
  local value
  value="$(read_yaml "${INFRA_CONFIG_DIR}/credentials.yml" ".${resource}.${key}")"

  if [[ -z "${value}" || "${value}" == "null" ]]; then
    log_error "Credential '${key}' not configured for resource: ${resource} in infra/.config/credentials.yml"
    return 1
  fi

  echo "${value}"
}

# Gets all credentials for a resource as KEY=VALUE pairs.
# Args: $1 - resource name
# Returns: KEY=VALUE pairs (stdout, one per line)
get_all_credentials() {
  local resource="${1}"
  local creds_file="${INFRA_CONFIG_DIR}/credentials.yml"

  if [[ ! -f "${creds_file}" ]]; then
    return 0
  fi

  yq ".${resource} // {} | to_entries | .[] | .key + \"=\" + (.value | tostring)" "${creds_file}" 2>/dev/null || true
}

# --- Project config ---

# Gets the port for a project application from {project}/config/ports.yml.
# Args: $1 - app name, $2 - project name
# Returns: port number (stdout)
get_project_port() {
  local app_name="${1}"
  local project_name="${2:-}"

  # If project_name not given, try to resolve from current directory
  if [[ -z "${project_name}" ]]; then
    if [[ -f "df.yml" ]]; then
      project_name="$(read_yaml "df.yml" '.project')"
    fi
  fi

  if [[ -z "${project_name}" ]]; then
    log_error "Cannot determine project name for port lookup"
    return 1
  fi

  local config_file="${ROOT_DIR}/${project_name}/config/ports.yml"
  local port
  port="$(read_yaml "${config_file}" ".${app_name}")"

  if [[ -z "${port}" || "${port}" == "null" ]]; then
    log_error "Port not configured for app: ${app_name} in ${project_name}/config/ports.yml"
    return 1
  fi

  echo "${port}"
}

# Gets a project-level credential.
# Args: $1 - key path (yq expression), $2 - project name
# Returns: value (stdout)
get_project_credential() {
  local key="${1}"
  local project_name="${2}"
  local config_file="${ROOT_DIR}/${project_name}/config/credentials.yml"

  if [[ ! -f "${config_file}" ]]; then
    return 0
  fi

  read_yaml "${config_file}" "${key}"
}

# --- df.yml helpers ---

# Reads the app name from a df.yml file.
# Args: $1 - path to df.yml
# Returns: app name (stdout)
get_app_name() {
  local df_yml="${1}"
  read_yaml "${df_yml}" '.name'
}

# Reads the project name from a df.yml file.
# Args: $1 - path to df.yml
# Returns: project name (stdout)
get_project_name() {
  local df_yml="${1}"
  read_yaml "${df_yml}" '.project'
}

# --- .env generation ---

# Generates a .env file for an infra resource from config YAMLs.
# The docker-compose reads from this .env — no defaults in compose files.
# Args: $1 - resource name
# Returns: path to generated .env (stdout)
generate_infra_env() {
  local resource="${1}"
  local env_file="${INFRA_DIR}/${resource}/.env"

  # Start fresh
  : > "${env_file}"

  # Add port
  local port
  port="$(get_port "${resource}")" || return 1
  echo "PORT=${port}" >> "${env_file}"

  # Add credentials
  local creds
  creds="$(get_all_credentials "${resource}")"
  while IFS= read -r cred_line; do
    [[ -z "${cred_line}" ]] && continue
    local key val
    key="$(echo "${cred_line}" | cut -d= -f1 | tr '[:lower:]' '[:upper:]')"
    val="$(echo "${cred_line}" | cut -d= -f2-)"
    echo "${key}=${val}" >> "${env_file}"
  done <<< "${creds}"

  echo "${env_file}"
}

# Generates a .env file for a project application from config YAMLs.
# Merges infra ports/credentials (for dependencies) + project port.
# Args: $1 - path to df.yml
# Returns: path to generated .env (stdout)
generate_project_env() {
  local df_yml="${1}"
  local app_dir
  app_dir="$(dirname "${df_yml}")"
  local env_file="${app_dir}/.env"

  local app_name
  app_name="$(get_app_name "${df_yml}")"

  local project_name
  project_name="$(get_project_name "${df_yml}")"

  # Start fresh
  : > "${env_file}"

  # Add project app port
  local app_port
  app_port="$(get_project_port "${app_name}" "${project_name}")" || return 1
  echo "APP_PORT=${app_port}" >> "${env_file}"

  # Add infra ports and credentials for each dependency
  local deps
  deps="$(read_yaml "${df_yml}" '.dependencies[]' 2>/dev/null || true)"

  while IFS= read -r dep; do
    [[ -z "${dep}" ]] && continue

    local upper_dep
    upper_dep="$(echo "${dep}" | tr '[:lower:]' '[:upper:]')"

    # Port
    local port
    port="$(get_port "${dep}")" || continue
    echo "${upper_dep}_PORT=${port}" >> "${env_file}"

    # Credentials
    local creds
    creds="$(get_all_credentials "${dep}")"
    while IFS= read -r cred_line; do
      [[ -z "${cred_line}" ]] && continue
      local key val
      key="$(echo "${cred_line}" | cut -d= -f1)"
      val="$(echo "${cred_line}" | cut -d= -f2-)"
      local upper_key
      upper_key="$(echo "${upper_dep}_${key}" | tr '[:lower:]' '[:upper:]')"
      echo "${upper_key}=${val}" >> "${env_file}"
    done <<< "${creds}"
  done <<< "${deps}"

  echo "${env_file}"
}

# Builds environment variables for an app based on its dependencies.
# Injects ports and credentials from config files.
# Args: $1 - path to df.yml
# Returns: env vars as -e flags (stdout)
build_env_vars() {
  local df_yml="${1}"
  local env_flags=""

  local app_name
  app_name="$(get_app_name "${df_yml}")"

  local project_name
  project_name="$(get_project_name "${df_yml}")"

  local app_port
  app_port="$(get_project_port "${app_name}" "${project_name}")" || return 1
  env_flags="${env_flags} -e APP_PORT=${app_port}"

  local deps
  deps="$(read_yaml "${df_yml}" '.dependencies[]' 2>/dev/null || true)"

  while IFS= read -r dep; do
    [[ -z "${dep}" ]] && continue

    local port
    port="$(get_port "${dep}")" || continue
    local upper_dep
    upper_dep="$(echo "${dep}" | tr '[:lower:]' '[:upper:]')"
    env_flags="${env_flags} -e ${upper_dep}_PORT=${port}"

    # Add credentials as env vars
    local creds
    creds="$(get_all_credentials "${dep}")"
    while IFS= read -r cred_line; do
      [[ -z "${cred_line}" ]] && continue
      local key val
      key="$(echo "${cred_line}" | cut -d= -f1)"
      val="$(echo "${cred_line}" | cut -d= -f2-)"
      local upper_key
      upper_key="$(echo "${upper_dep}_${key}" | tr '[:lower:]' '[:upper:]')"
      env_flags="${env_flags} -e ${upper_key}=${val}"
    done <<< "${creds}"
  done <<< "${deps}"

  echo "${env_flags}"
}
