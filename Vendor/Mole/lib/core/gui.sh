#!/bin/bash
# Private helpers shared by Mole's native-app bridge. These functions only
# serialize plans already produced by Mole; they never authorize mutations.

set -euo pipefail

mole_gui_json_escape() {
    local value="${1:-}"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    value="${value//$'\b'/\\b}"
    value="${value//$'\f'/\\f}"
    value="${value//$'\n'/\\n}"
    value="${value//$'\r'/\\r}"
    value="${value//$'\t'/\\t}"
    printf '%s' "$value"
}

mole_gui_reject_multiline_value() {
    local value="${1:-}"
    [[ -n "$value" ]] || return 1
    [[ "$value" != *$'\n'* && "$value" != *$'\r'* ]]
}
