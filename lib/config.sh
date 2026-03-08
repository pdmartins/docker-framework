#!/usr/bin/env bash
# Configuration management: port calculation, env generation, squads registry.
# Requires: yq

# --- Known service ports (NNN suffix) ---
# Max 5 squads (X=1..5), 9 projects per squad (Y=1..9)
# Host port formula: XY * 1000 + NNN

declare -A SERVICE_PORTS
SERVICE_PORTS=(
  [postgresql]=432
  [kafka]=92
  [zookeeper]=181
  [redis]=379
  [rabbitmq]=672
  [rabbitmq_mgmt]=673
  [couchdb]=984
)

# --- YAML helpers ---

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

# --- df.yml helpers ---

# Reads the project slug from df.yml.
# Args: $1 - path to df.yml
# Returns: slug (stdout)
get_project_slug() {
  local df_yml="${1}"
  read_yaml "${df_yml}" '.project.name'
}

# Reads the squad slug from df.yml.
# Args: $1 - path to df.yml
# Returns: slug (stdout)
get_squad_slug() {
  local df_yml="${1}"
  read_yaml "${df_yml}" '.project.squad'
}

# Reads the project index from df.yml.
# Args: $1 - path to df.yml
# Returns: index (stdout)
get_project_index() {
  local df_yml="${1}"
  read_yaml "${df_yml}" '.project.index'
}

# --- Squads registry ---

# Looks up squad index from squads.yml by slug.
# Args: $1 - squad slug
# Returns: squad index (stdout)
get_squad_index() {
  local squad_slug="${1}"
  local squads_file="${CONFIG_DIR}/squads.yml"
  local index
  index="$(read_yaml "${squads_file}" ".squads[] | select(.slug == \"${squad_slug}\") | .index")"

  if [[ -z "${index}" || "${index}" == "null" ]]; then
    log_error "Squad not found in squads.yml: ${squad_slug}"
    return 1
  fi

  echo "${index}"
}

# Looks up project index from squads.yml by squad slug + project slug.
# Args: $1 - squad slug, $2 - project slug
# Returns: project index (stdout)
lookup_project_index() {
  local squad_slug="${1}"
  local project_slug="${2}"
  local squads_file="${CONFIG_DIR}/squads.yml"
  local index
  index="$(read_yaml "${squads_file}" ".squads[] | select(.slug == \"${squad_slug}\") | .projects[] | select(.slug == \"${project_slug}\") | .index")"

  if [[ -z "${index}" || "${index}" == "null" ]]; then
    log_error "Project not found in squads.yml: ${squad_slug}/${project_slug}"
    return 1
  fi

  echo "${index}"
}

# --- Port calculation ---

# Calculates the port prefix (XY) for a project.
# Args: $1 - squad index, $2 - project index
# Returns: prefix number (stdout)
calculate_port_prefix() {
  local squad_index="${1}"
  local project_index="${2}"
  echo $(( squad_index * 10 + project_index ))
}

# Calculates all host ports for a project.
# Args: $1 - squad index, $2 - project index
# Returns: KEY=VALUE pairs (stdout, one per line)
calculate_ports() {
  local squad_index="${1}"
  local project_index="${2}"
  local prefix
  prefix="$(calculate_port_prefix "${squad_index}" "${project_index}")"

  local service
  for service in "${!SERVICE_PORTS[@]}"; do
    local nnn="${SERVICE_PORTS[${service}]}"
    local host_port=$(( prefix * 1000 + 10#${nnn} ))
    local upper_service
    upper_service="$(echo "${service}" | tr '[:lower:]' '[:upper:]')"
    echo "HOST_PORT_${upper_service}=${host_port}"
  done | sort
}

# Gets a specific host port for a service.
# Args: $1 - service name, $2 - squad index, $3 - project index
# Returns: port number (stdout)
get_host_port() {
  local service="${1}"
  local squad_index="${2}"
  local project_index="${3}"

  local nnn="${SERVICE_PORTS[${service}]}"
  if [[ -z "${nnn}" ]]; then
    log_error "Unknown service for port calculation: ${service}"
    return 1
  fi

  local prefix
  prefix="$(calculate_port_prefix "${squad_index}" "${project_index}")"
  echo $(( prefix * 1000 + 10#${nnn} ))
}

# --- .env generation ---

# Generates a temporary .env file for a template compose.
# Args: $1 - project slug, $2 - project data path, $3 - squad index, $4 - project index
# Returns: path to generated .env (stdout)
generate_infra_env() {
  local project_slug="${1}"
  local project_data_path="${2}"
  local squad_index="${3}"
  local project_index="${4}"

  local env_file
  env_file="$(mktemp "${TMPDIR:-/tmp}/df-env-${project_slug}-XXXXXX")"

  echo "PROJECT_SLUG=${project_slug}" >> "${env_file}"
  echo "PROJECT_DATA_PATH=${project_data_path}" >> "${env_file}"

  # Add all host ports
  calculate_ports "${squad_index}" "${project_index}" >> "${env_file}"

  echo "${env_file}"
}

# Resolves project metadata from df.yml and squads.yml.
# Sets global variables: PROJECT_SLUG, SQUAD_SLUG, SQUAD_INDEX, PROJECT_INDEX, PROJECT_DATA_PATH, PROJECT_DIR
# Args: $1 - path to df.yml
resolve_project_metadata() {
  local df_yml="${1}"

  PROJECT_SLUG="$(get_project_slug "${df_yml}")"
  SQUAD_SLUG="$(get_squad_slug "${df_yml}")"

  # Try df.yml index first, fall back to squads.yml lookup
  PROJECT_INDEX="$(get_project_index "${df_yml}")"
  if [[ -z "${PROJECT_INDEX}" || "${PROJECT_INDEX}" == "null" ]]; then
    PROJECT_INDEX="$(lookup_project_index "${SQUAD_SLUG}" "${PROJECT_SLUG}")"
  fi
  SQUAD_INDEX="$(get_squad_index "${SQUAD_SLUG}")"

  # Always resolve the directory where df.yml lives
  PROJECT_DIR="$(cd "$(dirname "${df_yml}")" && pwd)"

  # Data path: use explicit data_path from df.yml if set, otherwise default to {PROJECT_DIR}/data
  local custom_data_path
  custom_data_path="$(read_yaml "${df_yml}" '.project.data_path // ""')"
  if [[ -n "${custom_data_path}" && "${custom_data_path}" != "null" ]]; then
    PROJECT_DATA_PATH="${custom_data_path}"
  else
    PROJECT_DATA_PATH="${PROJECT_DIR}/data"
  fi
}

# --- Ports documentation ---

# Generates PORTS.md from squads.yml with all calculated ports.
generate_ports_doc() {
  local squads_file="${CONFIG_DIR}/squads.yml"
  local output_file="${ROOT_DIR}/PORTS.md"

  if [[ ! -f "${squads_file}" ]]; then
    log_error "squads.yml not found: ${squads_file}"
    return 1
  fi

  {
    echo "# Port Assignments"
    echo ""
    echo "> Auto-generated by \`df\`. Do not edit manually."
    echo ""
    echo "## Schema"
    echo ""
    echo "Host port format: \`XYNNN\`"
    echo ""
    echo "- \`X\` = squad index"
    echo "- \`Y\` = project index within squad"
    echo "- \`NNN\` = last 3 digits of service default port"
    echo ""
    echo "| Service | Default Port | NNN |"
    echo "|---------|-------------|-----|"
    echo "| PostgreSQL | 5432 | 432 |"
    echo "| Kafka | 9092 | 092 |"
    echo "| Zookeeper | 2181 | 181 |"
    echo "| Redis | 6379 | 379 |"
    echo "| RabbitMQ | 5672 | 672 |"
    echo "| RabbitMQ Management | 15672 | 673 |"
    echo "| CouchDB | 5984 | 984 |"
    echo ""
    echo "## Assignments"
    echo ""
    echo "| Squad | Project | Prefix | PostgreSQL | Kafka | Zookeeper | Redis | RabbitMQ | RabbitMQ Mgmt | CouchDB |"
    echo "|-------|---------|--------|------------|-------|-----------|-------|----------|---------------|---------|"

    local squad_count
    squad_count="$(read_yaml "${squads_file}" '.squads | length')"

    local i=0
    while [[ "${i}" -lt "${squad_count}" ]]; do
      local squad_slug squad_index
      squad_slug="$(read_yaml "${squads_file}" ".squads[${i}].slug")"
      squad_index="$(read_yaml "${squads_file}" ".squads[${i}].index")"

      local project_count
      project_count="$(read_yaml "${squads_file}" ".squads[${i}].projects | length")"

      local j=0
      while [[ "${j}" -lt "${project_count}" ]]; do
        local proj_slug proj_index prefix
        proj_slug="$(read_yaml "${squads_file}" ".squads[${i}].projects[${j}].slug")"
        proj_index="$(read_yaml "${squads_file}" ".squads[${i}].projects[${j}].index")"
        prefix="$(calculate_port_prefix "${squad_index}" "${proj_index}")"

        local pg kafka zk redis rmq rmq_mgmt couchdb
        pg=$(( prefix * 1000 + 10#${SERVICE_PORTS[postgresql]} ))
        kafka=$(( prefix * 1000 + 10#${SERVICE_PORTS[kafka]} ))
        zk=$(( prefix * 1000 + 10#${SERVICE_PORTS[zookeeper]} ))
        redis=$(( prefix * 1000 + 10#${SERVICE_PORTS[redis]} ))
        rmq=$(( prefix * 1000 + 10#${SERVICE_PORTS[rabbitmq]} ))
        rmq_mgmt=$(( prefix * 1000 + 10#${SERVICE_PORTS[rabbitmq_mgmt]} ))
        couchdb=$(( prefix * 1000 + 10#${SERVICE_PORTS[couchdb]} ))

        echo "| ${squad_slug} | ${proj_slug} | ${prefix} | ${pg} | ${kafka} | ${zk} | ${redis} | ${rmq} | ${rmq_mgmt} | ${couchdb} |"

        j=$((j + 1))
      done

      i=$((i + 1))
    done
  } > "${output_file}"

  log_success "PORTS.md generated"
}
