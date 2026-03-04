#!/usr/bin/env bash
# Minimal test harness for bash unit tests.

TESTS_PASS=0
TESTS_FAIL=0
TESTS_TOTAL=0
CURRENT_TEST=""

assert_equals() {
  local expected="${1}"
  local actual="${2}"
  local msg="${3:-}"

  if [[ "${expected}" == "${actual}" ]]; then
    return 0
  else
    echo "  FAIL: ${msg:-assertion failed}"
    echo "    expected: '${expected}'"
    echo "    actual:   '${actual}'"
    return 1
  fi
}

assert_contains() {
  local haystack="${1}"
  local needle="${2}"
  local msg="${3:-}"

  if [[ "${haystack}" == *"${needle}"* ]]; then
    return 0
  else
    echo "  FAIL: ${msg:-does not contain expected string}"
    echo "    looking for: '${needle}'"
    echo "    in:          '${haystack}'"
    return 1
  fi
}

assert_not_empty() {
  local value="${1}"
  local msg="${2:-}"

  if [[ -n "${value}" ]]; then
    return 0
  else
    echo "  FAIL: ${msg:-value is empty}"
    return 1
  fi
}

run_test() {
  local test_name="${1}"
  local test_func="${2}"
  CURRENT_TEST="${test_name}"
  TESTS_TOTAL=$((TESTS_TOTAL + 1))

  if ${test_func} 2>&1; then
    TESTS_PASS=$((TESTS_PASS + 1))
    echo "  ✓ ${test_name}"
  else
    TESTS_FAIL=$((TESTS_FAIL + 1))
    echo "  ✗ ${test_name}"
  fi
}

print_summary() {
  echo ""
  echo "Results: ${TESTS_PASS}/${TESTS_TOTAL} passed, ${TESTS_FAIL} failed"
  if [[ "${TESTS_FAIL}" -gt 0 ]]; then
    return 1
  fi
  return 0
}
