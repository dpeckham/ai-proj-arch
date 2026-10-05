#!/usr/bin/env bats
load helpers

setup() {
  setup_isolated
  load_lib
  write_project yb dpeckham/yawnbooks /tmp/main
  aipa_load_project yb
  # A stand-in for the vendored mint-token.sh.
  MINT="$BATS_TEST_TMPDIR/mint.sh"
  aipa_mint_script() { printf '%s' "$MINT"; }
  fake launchctl <<'EOF2'
echo "launchctl $*" >> "$FAKE_LOG"
EOF2
}

@test "mint writes a repo-scoped token, private, without printing it" {
  cat > "$MINT" <<'EOF2'
echo "args=$* repos=$DNBG_REVIEWER_REPOSITORIES cfg=$DNBG_REVIEWER_CONFIG_DIR" >> "$FAKE_LOG"
echo ghs_TESTTOKEN123
EOF2
  run broker_mint_once yb
  [ "$status" -eq 0 ]
  [[ "$output" != *ghs_* ]]
  tok="$(aipa_run_dir yb)/gh-token"
  [ "$(cat "$tok")" = ghs_TESTTOKEN123 ]
  [ -z "$(find "$tok" -perm -g+r)" ] && [ -z "$(find "$tok" -perm -o+r)" ]
  grep -q "args=dpeckham repos=yawnbooks cfg=$AIPA_BOT_DIR" "$FAKE_LOG"
}

@test "a failed or garbled mint keeps the previous token" {
  mkdir -p "$(aipa_run_dir yb)"
  echo ghs_OLD > "$(aipa_run_dir yb)/gh-token"
  printf 'exit 1\n' > "$MINT"
  run broker_mint_once yb; [ "$status" -ne 0 ]
  printf 'echo "<html>error</html>"\n' > "$MINT"
  run broker_mint_once yb; [ "$status" -ne 0 ]
  [ "$(cat "$(aipa_run_dir yb)/gh-token")" = ghs_OLD ]
}

@test "the launchd plist is valid, escaped, and reloaded" {
  export PATH="$PATH:/odd&<path>"
  broker_install yb
  plist=$(broker_plist yb)
  plutil -lint "$plist"
  grep -q '/odd&amp;&lt;path&gt;' "$plist"
  grep -q "<string>broker</string>" "$plist"
  grep -q "launchctl bootout gui/$(id -u)/com.ai-proj-arch.broker.yb" "$FAKE_LOG"
  grep -q "launchctl bootstrap gui/$(id -u) $plist" "$FAKE_LOG"
}

@test "uninstall removes the plist" {
  broker_install yb
  broker_uninstall yb
  [ ! -e "$(broker_plist yb)" ]
}

@test "waiting for a token succeeds only for a fresh one" {
  mkdir -p "$(aipa_run_dir yb)"
  echo ghs_x > "$(aipa_run_dir yb)/gh-token"
  touch -t 202001010000 "$(aipa_run_dir yb)/gh-token"
  run broker_wait_for_token yb "$(date +%s)" 2; [ "$status" -ne 0 ]
  echo ghs_y > "$(aipa_run_dir yb)/gh-token"
  run broker_wait_for_token yb "$(( $(date +%s) - 5 ))" 2; [ "$status" -eq 0 ]
}
