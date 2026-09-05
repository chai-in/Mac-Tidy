#!/usr/bin/env bats

setup() {
    export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    export HOME="$BATS_TEST_TMPDIR/home"
    export MOLE_TEST_NO_AUTH=1
    mkdir -p "$HOME"
}

@test "native mutation guard rejects missing confirmation but allows previews and CLI callers" {
    run /bin/bash --noprofile --norc <<'SCRIPT'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/gui.sh"
MOLE_GUI_MODE=1
if mole_gui_require_confirmation; then exit 1; fi
MOLE_DRY_RUN=1
mole_gui_require_confirmation || exit 1
MOLE_DRY_RUN=0
MOLE_GUI_CONFIRMED=1
mole_gui_require_confirmation || exit 1
MOLE_GUI_CONFIRMED=0
MOLE_GUI_MODE=0
mole_gui_require_confirmation || exit 1
SCRIPT
    [ "$status" -eq 0 ]
}

@test "native cleanup preview honors skipped system caches even with cached sudo" {
    run /bin/bash --noprofile --norc <<'SCRIPT'
set -euo pipefail
source "$PROJECT_ROOT/bin/clean.sh"
prepare_clean_preview_file() { return 0; }
write_clean_preview_header() { :; }
adopt_sudo_session() { echo UNEXPECTED_SUDO_ADOPTION; return 0; }
DRY_RUN=true
MOLE_GUI_SYSTEM_CACHES=skip
start_cleanup
[[ "$SYSTEM_CLEAN" == false ]] || exit 1
SCRIPT
    [ "$status" -eq 0 ]
    [[ "$output" != *"UNEXPECTED_SUDO_ADOPTION"* ]]
}

@test "native sudo uses its GUI prompt even when the tty device is readable" {
    run /bin/bash --noprofile --norc <<'SCRIPT'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
# Every authorization operation is a shell mock; no real prompts can open.
sudo() {
    case "$1" in
        -n) return 1 ;;
        -k) return 0 ;;
        -S) local value; read -r value; [[ "$value" == fixture ]] ;;
        *) return 1 ;;
    esac
}
osascript() {
    [[ "$*" == *'with title "Mac Tidy"'* ]] || return 1
    printf 'fixture'
}
MOLE_GUI_MODE=1
MOLE_TEST_MODE=0
MOLE_TEST_NO_AUTH=0
request_sudo_access 'Fixture access' || exit 1
SCRIPT
    [ "$status" -eq 0 ]
}
