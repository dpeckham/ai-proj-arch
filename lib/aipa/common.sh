# shellcheck shell=bash
# Shared helpers for the aipa host CLI: messages, paths and project config.
# Compatible with macOS's bash 3.2. Sourced, never executed.

AIPA_CONFIG_HOME="${AIPA_CONFIG_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/ai-proj-arch}"
AIPA_BOT_DIR="${AIPA_BOT_DIR:-$AIPA_CONFIG_HOME/bot}"
AIPA_HARNESS_ENV="${AIPA_HARNESS_ENV:-$AIPA_CONFIG_HOME/harness.env}"
AIPA_LOG_DIR="${AIPA_LOG_DIR:-$HOME/Library/Logs/ai-proj-arch}"

die() { printf 'aipa: %s\n' "$*" >&2; exit 1; }
warn() { printf 'aipa: warning: %s\n' "$*" >&2; }
info() { printf '%s\n' "$*"; }

# Project names become container, volume and launchd names, so keep them tame.
aipa_validate_project() {
  case "$1" in
    "" | *[!a-z0-9-]* | -*) die "invalid project name '$1': use lowercase letters, digits and '-'" ;;
  esac
  [ "${#1}" -le 40 ] || die "project name '$1' is longer than 40 characters"
}

aipa_project_dir() { printf '%s/projects/%s' "$AIPA_CONFIG_HOME" "$1"; }
aipa_project_file() { printf '%s/project.env' "$(aipa_project_dir "$1")"; }
# The run dir is bind-mounted read-only at /run/aipa in the container.
aipa_run_dir() { printf '%s/run' "$(aipa_project_dir "$1")"; }
aipa_container_name() { printf 'aipa-%s' "$1"; }
aipa_home_volume() { printf 'aipa-%s-home' "$1"; }

aipa_kit_root() { (cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd); }
aipa_kit_version() { tr -d '[:space:]' < "$(aipa_kit_root)/VERSION"; }
aipa_image_ref() { printf 'ai-proj-arch/agent:%s' "$(aipa_kit_version)"; }

# Read one KEY=value line from a config file without executing it. Prints the
# value, or nothing if the key is absent. Values are taken literally.
aipa_config_get() {  # <file> <key>
  [ -r "$1" ] || return 0
  sed -n "s/^$2=//p" "$1" | tail -n 1
}

# Load and validate a project's config into AIPA_REPO and AIPA_MAIN_DIR.
aipa_load_project() {  # <project>
  local file
  aipa_validate_project "$1"
  file=$(aipa_project_file "$1")
  [ -r "$file" ] || die "project '$1' is not set up: no $file (run: aipa create $1 --repo <owner>/<name>)"
  AIPA_REPO=$(aipa_config_get "$file" AIPA_REPO)
  AIPA_MAIN_DIR=$(aipa_config_get "$file" AIPA_MAIN_DIR)
  case "$AIPA_REPO" in
    */*/* | /* | */ | "") die "$file: AIPA_REPO must be <owner>/<name>, got '$AIPA_REPO'" ;;
    *[!A-Za-z0-9._/-]*) die "$file: AIPA_REPO has invalid characters: '$AIPA_REPO'" ;;
  esac
  case "$AIPA_MAIN_DIR" in
    /*) ;;
    *) die "$file: AIPA_MAIN_DIR must be an absolute path, got '$AIPA_MAIN_DIR'" ;;
  esac
  # shellcheck disable=SC2034  # read by the scripts that source this file
  AIPA_REPO_OWNER=${AIPA_REPO%%/*}
  # shellcheck disable=SC2034
  AIPA_REPO_NAME=${AIPA_REPO#*/}
}

# Create a directory that only the current user can read, write or list.
aipa_private_dir() {  # <path>
  mkdir -p "$1"
  chmod 700 "$1"
}

# Refuse a secret anyone but the owner can read or replace.
aipa_require_private_file() {  # <path> <what>
  [ -f "$1" ] || die "$2 not found at $1"
  if [ -n "$(find -L "$1" -maxdepth 0 \( -perm -g+r -o -perm -o+r -o -perm -g+w -o -perm -o+w \) 2>/dev/null)" ]; then
    die "$2 at $1 is readable or writable by others. Fix with: chmod 600 '$1'"
  fi
}

# Write content to a file atomically (temp file in the same directory, then
# rename), with mode 600 from the start, so a reader never sees a partial file.
aipa_write_private_atomic() {  # <path>  (content on stdin)
  local tmp
  tmp=$(mktemp "$(dirname "$1")/.tmp.XXXXXX")
  chmod 600 "$tmp"
  if ! cat > "$tmp"; then
    rm -f "$tmp"
    return 1
  fi
  mv -f "$tmp" "$1"
}
