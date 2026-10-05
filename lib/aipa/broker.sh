# shellcheck shell=bash
# Token broker: keeps a fresh, repo-scoped GitHub App installation token in the
# project's run dir, which the container sees read-only at /run/aipa/gh-token.
# The App's private key stays on the host; containers only ever see tokens.
#
# Tokens live for one hour. The broker mints a new one every
# AIPA_BROKER_INTERVAL seconds (default 45 minutes) and retries with backoff on
# failure. launchd keeps it running (and restarts it) independently of any
# terminal, so work in the container continues after the CEO closes theirs.

AIPA_BROKER_INTERVAL="${AIPA_BROKER_INTERVAL:-2700}"

aipa_mint_script() { printf '%s/vendor/dnbg/dnbg-workflow/skills/reviewer/mint-token.sh' "$(aipa_kit_root)"; }

# Mint one token scoped to the project's repo and write it atomically.
broker_mint_once() {  # <project>   (expects aipa_load_project to have run)
  local run token
  run=$(aipa_run_dir "$1")
  aipa_private_dir "$run"
  token=$(DNBG_REVIEWER_CONFIG_DIR="$AIPA_BOT_DIR" \
          DNBG_REVIEWER_REPOSITORIES="$AIPA_REPO_NAME" \
          bash "$(aipa_mint_script)" "$AIPA_REPO_OWNER") || return 1
  case "$token" in
    ghs_?*) ;;
    *) printf 'broker: mint returned something that is not a token\n' >&2; return 1 ;;
  esac
  printf '%s\n' "$token" | aipa_write_private_atomic "$run/gh-token"
}

broker_log() { printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"; }

# Run forever (launchd's job). Never prints a token.
broker_loop() {  # <project>
  local backoff=30
  aipa_load_project "$1"
  broker_log "broker started for $AIPA_REPO (interval ${AIPA_BROKER_INTERVAL}s)"
  while :; do
    if broker_mint_once "$1"; then
      broker_log "minted a token scoped to $AIPA_REPO"
      backoff=30
      sleep "$AIPA_BROKER_INTERVAL"
    else
      broker_log "mint failed; retrying in ${backoff}s"
      sleep "$backoff"
      backoff=$((backoff * 2))
      [ "$backoff" -le 300 ] || backoff=300
    fi
  done
}

broker_label() { printf 'com.ai-proj-arch.broker.%s' "$1"; }
broker_plist() { printf '%s/Library/LaunchAgents/%s.plist' "$HOME" "$(broker_label "$1")"; }

# XML-escape a value for the plist.
_plist_escape() { printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }

# Install (or refresh) and start the launchd agent for a project's broker.
broker_install() {  # <project>
  local label plist aipa_bin
  label=$(broker_label "$1")
  plist=$(broker_plist "$1")
  aipa_bin="$(aipa_kit_root)/bin/aipa"
  mkdir -p "$(dirname "$plist")" "$AIPA_LOG_DIR"
  cat > "$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$(_plist_escape "$label")</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>$(_plist_escape "$aipa_bin")</string>
    <string>broker</string>
    <string>$(_plist_escape "$1")</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key><string>$(_plist_escape "$PATH")</string>
    <key>AIPA_CONFIG_HOME</key><string>$(_plist_escape "$AIPA_CONFIG_HOME")</string>
  </dict>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ThrottleInterval</key><integer>30</integer>
  <key>StandardOutPath</key><string>$(_plist_escape "$AIPA_LOG_DIR/$1-broker.log")</string>
  <key>StandardErrorPath</key><string>$(_plist_escape "$AIPA_LOG_DIR/$1-broker.log")</string>
</dict>
</plist>
EOF
  chmod 644 "$plist"
  # Reload so a changed plist (new kit path, PATH) takes effect.
  launchctl bootout "gui/$(id -u)/$label" >/dev/null 2>&1 || true
  launchctl bootstrap "gui/$(id -u)" "$plist"
}

broker_uninstall() {  # <project>
  local label plist
  label=$(broker_label "$1")
  plist=$(broker_plist "$1")
  launchctl bootout "gui/$(id -u)/$label" >/dev/null 2>&1 || true
  rm -f "$plist"
}

broker_running() {  # <project>
  launchctl print "gui/$(id -u)/$(broker_label "$1")" 2>/dev/null | grep -q 'state = running'
}

# Age in seconds of the current token file, or nothing if there is none.
broker_token_age() {  # <project>
  local f
  f="$(aipa_run_dir "$1")/gh-token"
  [ -f "$f" ] || return 0
  echo $(( $(date +%s) - $(stat -f %m "$f" 2>/dev/null || stat -c %Y "$f") ))
}

# Wait until the broker has written a token newer than the given epoch.
broker_wait_for_token() {  # <project> <since-epoch> <timeout-seconds>
  local f deadline mtime
  f="$(aipa_run_dir "$1")/gh-token"
  deadline=$(( $(date +%s) + $3 ))
  while [ "$(date +%s)" -lt "$deadline" ]; do
    if [ -f "$f" ]; then
      mtime=$(stat -f %m "$f" 2>/dev/null || stat -c %Y "$f")
      [ "$mtime" -ge "$2" ] && return 0
    fi
    sleep 1
  done
  return 1
}
