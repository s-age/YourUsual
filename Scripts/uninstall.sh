#!/bin/bash
set -euo pipefail

# uninstall.sh — fully remove a locally-installed YourUsual and reset the OS state
# that a plain `rm -rf /Applications/YourUsual.app` leaves behind.
#
# Cleans, per bundle id: the .app, TCC privacy grants, app data/preferences, and
# the Launch-at-Login item. Handles both flavors:
#   prod : com.yourusual.app       /Applications/YourUsual.app        (or the cask)
#   dev  : com.yourusual.app.dev   "/Applications/YourUsual (dev).app"
#
# The dev bundle id also names the separate Application Support store that DEBUG
# builds (Xcode / `swift run` / `swift test`) use, so purging dev clears that data
# too (see RegistryStoreFactory.storeDirectoryName).
#
#   uninstall.sh           # remove both prod and dev
#   uninstall.sh --dev     # remove only the dev build
#   uninstall.sh --prod    # remove only the prod build (uses brew if cask-managed)

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; NC='\033[0m'
info()  { printf "${GREEN}[INFO]${NC} %s\n" "$1"; }
warn()  { printf "${YELLOW}[WARN]${NC} %s\n" "$1"; }
error() { printf "${RED}[ERROR]${NC} %s\n" "$1" >&2; }

usage() {
    cat <<EOF
Usage: $(basename "$0") [--dev | --prod]

Remove a locally-installed YourUsual and reset its OS state (app bundle, TCC
privacy grants, app data, Launch-at-Login item).

Options:
  (none)    Remove both the prod (com.yourusual.app) and dev (com.yourusual.app.dev) builds
  --dev     Remove only the dev build
  --prod    Remove only the prod build (uses 'brew uninstall' if installed via cask)
  -h, --help
EOF
}

DO_PROD=true
DO_DEV=true
case "${1:-}" in
    --dev)      DO_PROD=false ;;
    --prod)     DO_DEV=false  ;;
    -h|--help)  usage; exit 0 ;;
    "")         ;;
    *) error "Unknown option: $1"; usage; exit 1 ;;
esac

CASK="yourusual"

# Purge everything tied to one bundle id.
#   $1 bundle id   $2 /Applications app bundle   $3 login-item name(s, '|'-delimited)   $4 "cask"|""
purge() {
    local id="$1" app="$2" login_names="$3" cask_flag="$4"
    local removed_any=false

    info "── Purging ${id} ──"

    # 1. Quit if running.
    if pgrep -f "/Applications/${app}/Contents/MacOS/" >/dev/null 2>&1; then
        osascript -e "tell application id \"${id}\" to quit" >/dev/null 2>&1 || true
        sleep 1
        pkill -f "/Applications/${app}/Contents/MacOS/" 2>/dev/null || true
        info "quit running ${app}"
    fi

    # 2. Remove the app bundle (via brew when it owns it, else rm).
    if [[ "${cask_flag}" == "cask" ]] && brew list --cask "${CASK}" >/dev/null 2>&1; then
        info "uninstalling Homebrew cask ${CASK}..."
        brew uninstall --cask "${CASK}" || warn "brew uninstall failed"
        removed_any=true
    elif [[ -d "/Applications/${app}" ]]; then
        rm -rf "/Applications/${app}" && info "removed /Applications/${app}"
        removed_any=true
    else
        info "no app bundle at /Applications/${app}"
    fi

    # 3. Reset privacy (TCC) grants for this bundle id.
    if tccutil reset All "${id}" >/dev/null 2>&1; then
        info "reset TCC grants for ${id}"
    fi

    # 4. Remove per-app user data.
    local paths=(
        "${HOME}/Library/Application Support/${id}"
        "${HOME}/Library/Preferences/${id}.plist"
        "${HOME}/Library/Caches/${id}"
        "${HOME}/Library/HTTPStorages/${id}"
        "${HOME}/Library/Saved Application State/${id}.savedState"
    )
    local p
    for p in "${paths[@]}"; do
        if [[ -e "${p}" ]]; then
            rm -rf "${p}" && info "removed ${p/#${HOME}/~}"
        fi
    done

    # 5. Remove the Launch-at-Login item (orphaned once the app is gone).
    # System Events returns a comma-joined list ("YourUsual, OtherApp"); after splitting on
    # commas only the 2nd+ names carry a leading space, so trim it before the exact match —
    # otherwise a sole/first login item named exactly the target would be skipped.
    # SMAppService.mainApp registers under the bundle's display name, which has varied
    # ("Your Usual" vs "YourUsual"), so prod passes both candidates ('|'-delimited).
    local login_list name
    login_list="$(osascript -e "tell application \"System Events\" to get the name of every login item" 2>/dev/null \
        | tr ',' '\n' | sed 's/^ *//')"
    IFS='|' read -ra _names <<< "${login_names}"
    for name in "${_names[@]}"; do
        if printf '%s\n' "${login_list}" | grep -qx "${name}"; then
            osascript -e "tell application \"System Events\" to delete login item \"${name}\"" 2>/dev/null \
                && info "removed login item \"${name}\""
        fi
    done

    ${removed_any} || warn "nothing installed for ${id} (still reset TCC/data just in case)"
}

${DO_PROD} && purge "com.yourusual.app"     "YourUsual.app"        "Your Usual|YourUsual"  "cask"
${DO_DEV}  && purge "com.yourusual.app.dev" "YourUsual (dev).app"  "YourUsual (dev)"       ""

info "Done."
