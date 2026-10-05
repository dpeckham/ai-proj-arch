#!/usr/bin/env bats
# The scripts baked into the image, run on the host with test paths.
load helpers

setup() {
  setup_isolated
  BIN="$ROOT/container/rootfs/usr/local/bin"
  export AIPA_TOKEN_FILE="$BATS_TEST_TMPDIR/gh-token"
}

@test "credential helper answers get with the current token" {
  echo ghs_ONE > "$AIPA_TOKEN_FILE"
  run "$BIN/git-credential-aipa" get <<< $'protocol=https\nhost=github.com\n'
  [ "$status" -eq 0 ]
  [ "$output" = $'username=x-access-token\npassword=ghs_ONE' ]
  echo ghs_TWO > "$AIPA_TOKEN_FILE"   # a rotated token is used immediately
  run "$BIN/git-credential-aipa" get <<< ''
  [[ "$output" == *password=ghs_TWO ]]
}

@test "credential helper ignores store and erase, and fails without a token" {
  run "$BIN/git-credential-aipa" store <<< ''; [ "$status" -eq 0 ]; [ -z "$output" ]
  run "$BIN/git-credential-aipa" get <<< ''
  [ "$status" -ne 0 ]
  [[ "$output" == *"no bot token"* ]]
}

@test "gh wrapper exports the token, and an explicit GH_TOKEN wins" {
  fake realgh <<'EOF2'
echo "GH_TOKEN=$GH_TOKEN args=$*"
EOF2
  export AIPA_GH_REAL="$FAKES/realgh"
  echo ghs_FILE > "$AIPA_TOKEN_FILE"
  run "$BIN/gh" pr list
  [ "$output" = "GH_TOKEN=ghs_FILE args=pr list" ]
  GH_TOKEN=ghs_ENV run "$BIN/gh" api user
  [ "$output" = "GH_TOKEN=ghs_ENV args=api user" ]
}

# A bare "GitHub" remote, a host checkout of main, and a project file.
make_repos() {
  export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
  REMOTE="$BATS_TEST_TMPDIR/remote.git"
  git init -q --bare -b main "$REMOTE"
  git clone -q "$REMOTE" "$BATS_TEST_TMPDIR/seed" 2>/dev/null
  git -C "$BATS_TEST_TMPDIR/seed" commit -q --allow-empty -m one
  git -C "$BATS_TEST_TMPDIR/seed" push -q origin HEAD:main
  export AIPA_MAIN="$BATS_TEST_TMPDIR/main"
  git clone -q "$REMOTE" "$AIPA_MAIN"
  export AIPA_PROJECT_FILE="$BATS_TEST_TMPDIR/project.env"
  echo 'AIPA_REPO=dpeckham/yawnbooks' > "$AIPA_PROJECT_FILE"
  export AIPA_SYNC_REMOTE_URL="$REMOTE"
}

advance_remote() {
  git -C "$BATS_TEST_TMPDIR/seed" commit -q --allow-empty -m "$1"
  git -C "$BATS_TEST_TMPDIR/seed" push -q origin HEAD:main
}

@test "sync fast-forwards main and reports when already current" {
  make_repos
  advance_remote two
  run "$BIN/aipa-sync-main"
  [ "$status" -eq 0 ]; [[ "$output" == "main fast-forwarded"* ]]
  [ "$(git -C "$AIPA_MAIN" log -1 --format=%s)" = two ]
  [ "$(git -C "$AIPA_MAIN" rev-parse origin/main)" = "$(git -C "$AIPA_MAIN" rev-parse HEAD)" ]
  run "$BIN/aipa-sync-main"
  [[ "$output" == "main is up to date"* ]]
}

@test "sync refuses local changes, another branch, or divergence" {
  make_repos
  advance_remote two
  echo change >> "$AIPA_MAIN/file"; git -C "$AIPA_MAIN" add file
  run "$BIN/aipa-sync-main"; [ "$status" -ne 0 ]; [[ "$output" == *"local changes"* ]]
  git -C "$AIPA_MAIN" reset -q --hard
  git -C "$AIPA_MAIN" switch -q -c feature
  run "$BIN/aipa-sync-main"; [ "$status" -ne 0 ]; [[ "$output" == *"not main"* ]]
  git -C "$AIPA_MAIN" switch -q main
  git -C "$AIPA_MAIN" commit -q --allow-empty -m local-only
  run "$BIN/aipa-sync-main"; [ "$status" -ne 0 ]
  [ "$(git -C "$AIPA_MAIN" log -1 --format=%s)" = local-only ]
}

@test "sync rejects a malformed repo in the project file" {
  make_repos
  echo 'AIPA_REPO=evil;touch /tmp/x' > "$AIPA_PROJECT_FILE"
  run "$BIN/aipa-sync-main"; [ "$status" -ne 0 ]; [[ "$output" == *"no valid AIPA_REPO"* ]]
}
