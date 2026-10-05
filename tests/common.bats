#!/usr/bin/env bats
load helpers

setup() {
  setup_isolated
  load_lib
}

@test "project names: lowercase, digits and dashes only" {
  run aipa_validate_project yawnbooks;   [ "$status" -eq 0 ]
  run aipa_validate_project my-app-2;    [ "$status" -eq 0 ]
  run aipa_validate_project Yawn;        [ "$status" -ne 0 ]
  run aipa_validate_project "a b";       [ "$status" -ne 0 ]
  run aipa_validate_project -lead;       [ "$status" -ne 0 ]
  run aipa_validate_project "../etc";    [ "$status" -ne 0 ]
  run aipa_validate_project "";          [ "$status" -ne 0 ]
}

@test "config values are read literally, never executed" {
  f="$BATS_TEST_TMPDIR/p.env"
  printf 'AIPA_REPO=$(touch %s/pwned)\n' "$BATS_TEST_TMPDIR" > "$f"
  run aipa_config_get "$f" AIPA_REPO
  [ "$output" = "\$(touch $BATS_TEST_TMPDIR/pwned)" ]
  [ ! -e "$BATS_TEST_TMPDIR/pwned" ]
}

@test "the last value for a key wins and missing keys are empty" {
  f="$BATS_TEST_TMPDIR/p.env"
  printf 'K=one\nK=two\n' > "$f"
  run aipa_config_get "$f" K;       [ "$output" = two ]
  run aipa_config_get "$f" MISSING; [ -z "$output" ]
}

@test "load_project splits owner and name" {
  write_project yb dpeckham/yawnbooks /tmp/main
  aipa_load_project yb
  [ "$AIPA_REPO_OWNER" = dpeckham ]
  [ "$AIPA_REPO_NAME" = yawnbooks ]
  [ "$AIPA_MAIN_DIR" = /tmp/main ]
}

@test "load_project rejects a bad repo or a relative main dir" {
  write_project yb 'dpeckham/yawn;rm -rf' /tmp/main
  run aipa_load_project yb; [ "$status" -ne 0 ]
  write_project yb dpeckham/a/b /tmp/main
  run aipa_load_project yb; [ "$status" -ne 0 ]
  write_project yb dpeckham/yawnbooks relative/dir
  run aipa_load_project yb; [ "$status" -ne 0 ]
  run aipa_load_project nosuch; [ "$status" -ne 0 ]
  [[ "$output" == *"not set up"* ]]
}

@test "atomic private write creates a 600 file and replaces it" {
  d="$BATS_TEST_TMPDIR/run"; mkdir -p "$d"
  echo first | aipa_write_private_atomic "$d/tok"
  echo second | aipa_write_private_atomic "$d/tok"
  [ "$(cat "$d/tok")" = second ]
  [ -z "$(find "$d/tok" -perm -g+r)" ] && [ -z "$(find "$d/tok" -perm -o+r)" ]
  [ "$(ls -A "$d" | wc -l | tr -d ' ')" = 1 ]   # no temp files left behind
}

@test "secrets readable by others are refused" {
  f="$BATS_TEST_TMPDIR/key.pem"; echo k > "$f"
  chmod 644 "$f"
  run aipa_require_private_file "$f" "the key"; [ "$status" -ne 0 ]
  [[ "$output" == *"chmod 600"* ]]
  chmod 600 "$f"
  run aipa_require_private_file "$f" "the key"; [ "$status" -eq 0 ]
}
