#!/bin/bash
# Private helpers shared by Mole's native-app bridge. These functions only
# serialize plans and enforce the native caller's confirmation boundary.

set -euo pipefail

mole_gui_require_confirmation() {
    if [[ "${MOLE_GUI_MODE:-0}" == "1" && "${MOLE_DRY_RUN:-0}" != "1" && "${MOLE_GUI_CONFIRMED:-0}" != "1" ]]; then
        echo "Native-app confirmation is required before changing files or settings" >&2
        return 1
    fi
    return 0
}

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
