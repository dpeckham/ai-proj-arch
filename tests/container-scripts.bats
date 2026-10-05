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

@test "review check posts the right check run for the PR head" {
  export AIPA_PROJECT_FILE="$BATS_TEST_TMPDIR/project.env"
  echo 'AIPA_REPO=dpeckham/yawnbooks' > "$AIPA_PROJECT_FILE"
  fake gh <<'EOF2'
if [ "$1" = pr ]; then echo abc1234def; exit 0; fi
echo "gh $*" >> "$FAKE_LOG"; cat >> "$FAKE_LOG"; echo posted
EOF2
  run "$BIN/aipa-review-check" qa 12 success "Testable" <<< "All paths covered"
  [ "$status" -eq 0 ]
  grep -q "gh api -X POST repos/dpeckham/yawnbooks/check-runs --input -" "$FAKE_LOG"
  grep -q '"name": "review/qa"' "$FAKE_LOG"
  grep -q '"head_sha": "abc1234def"' "$FAKE_LOG"
  grep -q '"summary": "All paths covered"' "$FAKE_LOG"
}

@test "review check rejects bad arguments" {
  run "$BIN/aipa-review-check" pm 12 success t; [ "$status" -eq 2 ]
  run "$BIN/aipa-review-check" qa 1x success t; [ "$status" -eq 2 ]
  run "$BIN/aipa-review-check" qa 12 approved t; [ "$status" -eq 2 ]
}

# A bare remote with a main branch, and a clone to run aipa-status in.
make_status_repos() {
  export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
  REMOTE="$BATS_TEST_TMPDIR/remote.git"
  git init -q --bare -b main "$REMOTE"
  git clone -q "$REMOTE" "$BATS_TEST_TMPDIR/a" 2>/dev/null
  git -C "$BATS_TEST_TMPDIR/a" config user.name "dpeckham-bot[bot]"
  git -C "$BATS_TEST_TMPDIR/a" commit -q --allow-empty -m init
  git -C "$BATS_TEST_TMPDIR/a" push -q origin HEAD:main
  export AIPA_STATUS_TEMPLATE="$ROOT/container/rootfs/usr/local/share/aipa/STATUS.md"
}

@test "status: first set creates the status branch from the template" {
  make_status_repos
  cd "$BATS_TEST_TMPDIR/a"
  run "$BIN/aipa-status" set coming-up - <<< "- #4 Import from CSV"
  [ "$status" -eq 0 ]; [[ "$output" == *"updated coming-up"* ]]
  run "$BIN/aipa-status" show
  [[ "$output" == *"- #4 Import from CSV"* ]]
  [[ "$output" == *"- None."* ]]                      # other sections untouched
  [[ "$output" == *"Updated: "*"dpeckham-bot[bot]"* ]]
  [ "$(git -C "$REMOTE" log --format=%s status | wc -l | tr -d ' ')" = 1 ]
  run git -C "$REMOTE" merge-base main status   # orphan: no history shared with main
  [ "$status" -ne 0 ]
  [ "$(git -C "$BATS_TEST_TMPDIR/a" worktree list | wc -l | tr -d ' ')" = 1 ]   # temp worktree removed
}

@test "status: two writers update different sections without losing either" {
  make_status_repos
  cd "$BATS_TEST_TMPDIR/a"
  "$BIN/aipa-status" set coming-up - <<< "- planned work" >/dev/null
  git clone -q "$REMOTE" "$BATS_TEST_TMPDIR/b"
  git -C "$BATS_TEST_TMPDIR/b" config user.name loop
  ( cd "$BATS_TEST_TMPDIR/b" && "$BIN/aipa-status" set blockers - <<< "- Q-1: needs CEO" >/dev/null )
  "$BIN/aipa-status" set recently-finished - <<< "- #3 merged" >/dev/null   # a is now behind: must refetch
  run "$BIN/aipa-status" show
  [[ "$output" == *"- planned work"* ]]
  [[ "$output" == *"- Q-1: needs CEO"* ]]
  [[ "$output" == *"- #3 merged"* ]]
}

@test "status: setting the same content again changes nothing" {
  make_status_repos
  cd "$BATS_TEST_TMPDIR/a"
  "$BIN/aipa-status" set blockers - <<< "- none" >/dev/null
  run "$BIN/aipa-status" set blockers - <<< "- none"
  [[ "$output" == *"unchanged"* ]]
}

@test "status: rejects unknown sections, empty content and markers" {
  make_status_repos
  cd "$BATS_TEST_TMPDIR/a"
  run "$BIN/aipa-status" set roadmap - <<< "x";   [ "$status" -ne 0 ]
  run "$BIN/aipa-status" set blockers - < /dev/null; [ "$status" -ne 0 ]
  run "$BIN/aipa-status" set blockers - <<< "<!-- aipa:end blockers -->"; [ "$status" -ne 0 ]
}
