#!/usr/bin/env bash
set -euo pipefail

find_fixture() {
  local candidates=(
    "${TEST_SRCDIR:-}/_main/examples/js_compat/compat_entry.js"
    "${TEST_SRCDIR:-}/rules_tsgo/examples/js_compat/compat_entry.js"
    "${TEST_SRCDIR:-}/rules_tsgo+/examples/js_compat/compat_entry.js"
    "${RUNFILES_DIR:-}/_main/examples/js_compat/compat_entry.js"
    "${RUNFILES_DIR:-}/rules_tsgo/examples/js_compat/compat_entry.js"
    "${RUNFILES_DIR:-}/rules_tsgo+/examples/js_compat/compat_entry.js"
  )

  local candidate
  for candidate in "${candidates[@]}"; do
    if [[ -f "${candidate}" ]]; then
      echo "${candidate}"
      return 0
    fi
  done

  echo "failed to find compat_entry.js in runfiles" >&2
  return 1
}

JS_FILE="$(find_fixture)"

mock_line="$(grep -nE "jest\.mock\([\"']\./dep[\"']\)" "${JS_FILE}" | head -n1 | cut -d: -f1)"
require_line="$(grep -nE "require\([\"']\./dep[\"']\)" "${JS_FILE}" | head -n1 | cut -d: -f1)"

if [[ -z "${mock_line}" || -z "${require_line}" ]]; then
  echo "missing expected jest.mock or require statement in ${JS_FILE}" >&2
  exit 1
fi

if (( mock_line >= require_line )); then
  echo "expected jest.mock to appear before require in ${JS_FILE}" >&2
  exit 1
fi

if ! grep -qE "exports\.AirflowAuthSchema" "${JS_FILE}"; then
  echo "missing exports.AirflowAuthSchema assignment in ${JS_FILE}" >&2
  exit 1
fi

if ! grep -qF "Object.defineProperty(exports, \"AirflowAuthSchema\"" "${JS_FILE}"; then
  echo "missing Object.defineProperty export shape for AirflowAuthSchema in ${JS_FILE}" >&2
  exit 1
fi
