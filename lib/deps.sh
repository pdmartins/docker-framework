#!/usr/bin/env bash
# Dependency resolution: reads df.yml and resolves infrastructure dependencies.

# Resolves and returns the list of infrastructure dependencies for a project.
# Args: $1 - path to df.yml
# Returns: list of resource names (stdout, one per line)
resolve_deps() {
  local df_yml="${1}"

  if [[ ! -f "${df_yml}" ]]; then
    log_error "df.yml not found: ${df_yml}"
    return 1
  fi

  yq '.dependencies[]' "${df_yml}" 2>/dev/null || true
}

# Checks if a resource is a valid infrastructure resource (has compose file).
# Args: $1 - resource name
# Returns: 0 if valid, 1 otherwise
is_valid_resource() {
  local resource="${1}"
  [[ -f "${INFRA_DIR}/${resource}/docker-compose.yml" ]]
}

# Validates all dependencies in a df.yml are valid resources.
# Args: $1 - path to df.yml
# Returns: 0 if all valid, 1 if any invalid
validate_deps() {
  local df_yml="${1}"
  local invalid=0

  local deps
  deps="$(resolve_deps "${df_yml}")"

  while IFS= read -r dep; do
    [[ -z "${dep}" ]] && continue

    if ! is_valid_resource "${dep}"; then
      log_error "Unknown infrastructure resource: ${dep}"
      log_error "No docker-compose.yml found at infra/${dep}/"
      invalid=1
    fi
  done <<< "${deps}"

  return "${invalid}"
}

# Checks which projects currently depend on a given resource.
# Scans all project-*/*/df.yml files for the dependency.
# Args: $1 - resource name
# Returns: list of app names depending on the resource (stdout)
find_dependents() {
  local resource="${1}"
  local dependents=""

  for df_yml in "${ROOT_DIR}"/project-*/*/df.yml; do
    [[ -f "${df_yml}" ]] || continue

    local app_name
    app_name="$(yq '.name' "${df_yml}" 2>/dev/null)"

    if yq ".dependencies[]" "${df_yml}" 2>/dev/null | grep -q "^${resource}$"; then
      # Check if this app's container is running
      if is_container_running "${app_name}"; then
        dependents="${dependents}${app_name}\n"
      fi
    fi
  done

  echo -e "${dependents}" | sed '/^$/d'
}
