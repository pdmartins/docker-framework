#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

LIB_DIR="${ROOT_DIR}/lib"
TEMPLATES_DIR="${ROOT_DIR}/templates"
PLATFORM_DIR="${ROOT_DIR}/platform"
CONFIG_DIR="${ROOT_DIR}/config"

export ROOT_DIR LIB_DIR TEMPLATES_DIR PLATFORM_DIR CONFIG_DIR

# Source test harness
source "${SCRIPT_DIR}/test_harness.sh"

# Stub log functions (no-op for tests)
log_info() { :; }
log_success() { :; }
log_warn() { :; }
log_error() { :; }

# Source the module under test
source "${LIB_DIR}/config.sh"

# ─── calculate_ports tests ───

test_calculate_ports_bw_agronomy() {
  local output
  output="$(calculate_ports 1 1)"

  assert_contains "${output}" "HOST_PORT_POSTGRESQL=11432" "bw/agronomy postgresql port" && \
  assert_contains "${output}" "HOST_PORT_KAFKA=11092" "bw/agronomy kafka port" && \
  assert_contains "${output}" "HOST_PORT_ZOOKEEPER=11181" "bw/agronomy zookeeper port" && \
  assert_contains "${output}" "HOST_PORT_REDIS=11379" "bw/agronomy redis port" && \
  assert_contains "${output}" "HOST_PORT_RABBITMQ=11672" "bw/agronomy rabbitmq port" && \
  assert_contains "${output}" "HOST_PORT_RABBITMQ_MGMT=11673" "bw/agronomy rabbitmq mgmt port"
}

test_calculate_ports_bw_assistant() {
  local output
  output="$(calculate_ports 1 2)"

  assert_contains "${output}" "HOST_PORT_POSTGRESQL=12432" "bw/assistant postgresql port" && \
  assert_contains "${output}" "HOST_PORT_KAFKA=12092" "bw/assistant kafka port" && \
  assert_contains "${output}" "HOST_PORT_REDIS=12379" "bw/assistant redis port"
}

test_calculate_ports_pm_obsidian() {
  local output
  output="$(calculate_ports 2 1)"

  assert_contains "${output}" "HOST_PORT_POSTGRESQL=21432" "pm/obsidian postgresql port" && \
  assert_contains "${output}" "HOST_PORT_KAFKA=21092" "pm/obsidian kafka port" && \
  assert_contains "${output}" "HOST_PORT_REDIS=21379" "pm/obsidian redis port" && \
  assert_contains "${output}" "HOST_PORT_ZOOKEEPER=21181" "pm/obsidian zookeeper port"
}

test_calculate_ports_prefix_formula() {
  # prefix = squad_index * 10 + project_index
  local prefix
  prefix="$(calculate_port_prefix 3 5)"
  assert_equals "35" "${prefix}" "prefix for squad 3, project 5"
}

test_calculate_ports_rabbitmq_conflict_resolved() {
  # RabbitMQ uses NNN=672, RabbitMQ Management uses NNN=673 (not 672)
  local output
  output="$(calculate_ports 1 1)"

  local rmq_port rmq_mgmt_port
  rmq_port="$(echo "${output}" | grep '^HOST_PORT_RABBITMQ=' | cut -d= -f2)"
  rmq_mgmt_port="$(echo "${output}" | grep '^HOST_PORT_RABBITMQ_MGMT=' | cut -d= -f2)"

  # They must be different
  if [[ "${rmq_port}" == "${rmq_mgmt_port}" ]]; then
    echo "  FAIL: RabbitMQ and RabbitMQ Management ports conflict: ${rmq_port}"
    return 1
  fi

  assert_equals "11672" "${rmq_port}" "rabbitmq port" && \
  assert_equals "11673" "${rmq_mgmt_port}" "rabbitmq mgmt port"
}

test_get_host_port_specific() {
  local port
  port="$(get_host_port "postgresql" 3 1)"
  assert_equals "31432" "${port}" "specific host port for av/hv_stt postgresql"
}

# ─── generate_infra_env tests ───

test_generate_infra_env_variables() {
  local env_file
  env_file="$(generate_infra_env "assistant" "/repos/_bw/assistant/data" 1 2)"

  local content
  content="$(cat "${env_file}")"

  assert_contains "${content}" "PROJECT_SLUG=assistant" "project slug" && \
  assert_contains "${content}" "PROJECT_DATA_PATH=/repos/_bw/assistant/data" "project data path" && \
  assert_contains "${content}" "HOST_PORT_POSTGRESQL=12432" "postgresql port in env" && \
  assert_contains "${content}" "HOST_PORT_KAFKA=12092" "kafka port in env" && \
  assert_contains "${content}" "HOST_PORT_REDIS=12379" "redis port in env"

  rm -f "${env_file}"
}

test_generate_infra_env_path_correct() {
  local env_file
  env_file="$(generate_infra_env "agronomy" "/repos/_bw/agronomy/data" 1 1)"

  local content
  content="$(cat "${env_file}")"

  assert_contains "${content}" "PROJECT_DATA_PATH=/repos/_bw/agronomy/data" "agronomy data path" && \
  assert_contains "${content}" "HOST_PORT_POSTGRESQL=11432" "agronomy postgresql port"

  rm -f "${env_file}"
}

test_generate_infra_env_creates_temp_file() {
  local env_file
  env_file="$(generate_infra_env "test-proj" "/tmp/test-data" 1 1)"

  if [[ ! -f "${env_file}" ]]; then
    echo "  FAIL: env file was not created"
    return 1
  fi

  rm -f "${env_file}"
}

# ─── generate_ports_doc tests ───

test_generate_ports_doc_contains_all_squads() {
  generate_ports_doc

  local content
  content="$(cat "${ROOT_DIR}/PORTS.md")"

  assert_contains "${content}" "| bw | agronomy | 11 |" "agronomy row" && \
  assert_contains "${content}" "| bw | assistant | 12 |" "assistant row" && \
  assert_contains "${content}" "| pm | obsidian | 21 |" "obsidian row" && \
  assert_contains "${content}" "| av | hv_stt | 31 |" "hv_stt row"
}

test_generate_ports_doc_correct_ports() {
  generate_ports_doc

  local content
  content="$(cat "${ROOT_DIR}/PORTS.md")"

  assert_contains "${content}" "| 11432 |" "agronomy postgresql" && \
  assert_contains "${content}" "| 12092 |" "assistant kafka" && \
  assert_contains "${content}" "| 21379 |" "obsidian redis" && \
  assert_contains "${content}" "| 31432 |" "hv_stt postgresql"
}

test_generate_ports_doc_has_schema() {
  generate_ports_doc

  local content
  content="$(cat "${ROOT_DIR}/PORTS.md")"

  assert_contains "${content}" "XYNNN" "schema format" && \
  assert_contains "${content}" "Auto-generated" "auto-generated note"
}

test_generate_ports_doc_reflects_squads_yml() {
  # Create a temp squads.yml with a different set
  local original_config_dir="${CONFIG_DIR}"
  local tmp_config
  tmp_config="$(mktemp -d)"

  cat > "${tmp_config}/squads.yml" <<'YAML'
squads:
  - index: 3
    slug: cx
    projects:
      - index: 1
        slug: portal
YAML

  CONFIG_DIR="${tmp_config}"

  generate_ports_doc

  local content
  content="$(cat "${ROOT_DIR}/PORTS.md")"

  CONFIG_DIR="${original_config_dir}"

  assert_contains "${content}" "| cx | portal | 31 |" "custom squad row" && \
  assert_contains "${content}" "| 31432 |" "custom portal postgresql"

  rm -rf "${tmp_config}"

  # Restore original PORTS.md
  generate_ports_doc
}

# ─── Run all tests ───

echo "=== calculate_ports tests ==="
run_test "bw/agronomy ports" test_calculate_ports_bw_agronomy
run_test "bw/assistant ports" test_calculate_ports_bw_assistant
run_test "pm/obsidian ports" test_calculate_ports_pm_obsidian
run_test "prefix formula" test_calculate_ports_prefix_formula
run_test "rabbitmq conflict resolved" test_calculate_ports_rabbitmq_conflict_resolved
run_test "get_host_port specific" test_get_host_port_specific

echo ""
echo "=== generate_infra_env tests ==="
run_test "env variables correct" test_generate_infra_env_variables
run_test "env path correct" test_generate_infra_env_path_correct
run_test "env creates temp file" test_generate_infra_env_creates_temp_file

echo ""
echo "=== generate_ports_doc tests ==="
run_test "contains all squads" test_generate_ports_doc_contains_all_squads
run_test "correct port values" test_generate_ports_doc_correct_ports
run_test "has schema section" test_generate_ports_doc_has_schema
run_test "reflects squads.yml" test_generate_ports_doc_reflects_squads_yml

print_summary
