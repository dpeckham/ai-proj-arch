#!/usr/bin/env bats
load helpers

setup() {
  setup_isolated
  # shellcheck source=../container/rootfs/usr/local/bin/aipa-loop
  . "$ROOT/container/rootfs/usr/local/bin/aipa-loop"
  REPO=o/r
}

facts() {  # reset, then set S_* from KEY=VALUE args
  S_STORY="" S_NEEDS_CEO=0 S_PR="" S_DRAFT=0 S_GATE="" S_ROUNDS=0 S_CAP=3
  S_REVIEW_qa="" S_REVIEW_eng="" S_REVIEW_ux=""
  local kv; for kv in "$@"; do eval "S_${kv%%=*}=\"\${kv#*=}\""; done
}

@test "decide: nothing ready means idle; a fresh story means implement" {
  facts;                 [ "$(decide)" = idle ]
  facts STORY=5;         [ "$(decide)" = implement ]
  facts STORY=5 PR=9 DRAFT=1; [ "$(decide)" = implement ]   # interrupted Coder run
}

@test "decide: a needs-ceo story waits for the CEO" {
  facts STORY=5 NEEDS_CEO=1 PR=9 GATE=success
  [ "$(decide)" = "wait-ceo blocked" ]
}

@test "decide: the gate must pass before any review" {
  facts STORY=5 PR=9;               [ "$(decide)" = "wait-checks gate" ]
  facts STORY=5 PR=9 GATE=pending;  [ "$(decide)" = "wait-checks gate" ]
  facts STORY=5 PR=9 GATE=failure;  [[ "$(decide)" == "block gate/verification-plan failed"* ]]
}

@test "decide: reviewers run in order qa, eng, ux, each once per head" {
  facts STORY=5 PR=9 GATE=success;                                [ "$(decide)" = "review qa" ]
  facts STORY=5 PR=9 GATE=success REVIEW_qa=success;              [ "$(decide)" = "review eng" ]
  facts STORY=5 PR=9 GATE=success REVIEW_qa=failure REVIEW_eng=success; [ "$(decide)" = "review ux" ]
  facts STORY=5 PR=9 GATE=success REVIEW_qa=cancelled;            [ "$(decide)" = "review qa" ]
}

@test "decide: all green waits for the CEO's merge; ux may be neutral" {
  facts STORY=5 PR=9 GATE=success REVIEW_qa=success REVIEW_eng=success REVIEW_ux=neutral
  [ "$(decide)" = wait-merge ]
}

@test "decide: findings get a fix round until the cap, then block" {
  facts STORY=5 PR=9 GATE=success REVIEW_qa=failure REVIEW_eng=success REVIEW_ux=success ROUNDS=1
  [ "$(decide)" = fix ]
  facts STORY=5 PR=9 GATE=success REVIEW_qa=success REVIEW_eng=failure REVIEW_ux=success ROUNDS=3 CAP=3
  [[ "$(decide)" == "block review rounds reached the cap (3)"* ]]
}

@test "config: harness and cap come from project.toml with defaults" {
  CONFIG=$'# comment\n[harness]\ncoder = "codex"   # inline comment\nqa="claude"\n\n[loop]\nreview_rounds = 5\n'
  [ "$(harness_for coder)" = codex ]
  [ "$(harness_for qa)" = claude ]
  [ "$(harness_for ux)" = claude ]          # default
  [ "$(config_get loop review_rounds 3)" = 5 ]
  CONFIG=""
  [ "$(config_get loop review_rounds 3)" = 3 ]
  CONFIG=$'[harness]\neng = "gpt"\n'
  run harness_for eng; [ "$status" -ne 0 ]
}

# A fake gh: issue list/view and pr list answer from fixture files.
fake_github() {
  F="$BATS_TEST_TMPDIR/gh"; mkdir -p "$F"
  fake gh <<EOF2
F="$F"
EOF2
  cat >> "$FAKES/gh" <<'EOF2'
args="$*"
case "$args" in
  "issue list --repo o/r --label roadmap"*) cat "$F/roadmap" ;;
  "issue list --repo o/r --label story"*) cat "$F/stories" ;;
  "issue view "*) n=$3; cat "$F/epic-$n" 2>/dev/null || true ;;
  "pr list"*) cat "$F/prs" 2>/dev/null || true ;;
  *) echo "unexpected gh $args" >&2; exit 1 ;;
esac
EOF2
}

@test "story order follows the Roadmap's epics, then each epic's checklist" {
  fake_github
  printf '## Epics\n- [ ] https://github.com/o/r/issues/20 B\n- [x] #10 A\nNot a checklist #99\n' > "$F/roadmap"
  printf -- '- [ ] https://github.com/o/r/issues/22\n- [ ] #21\n' > "$F/epic-20"
  printf -- '- [x] #11\n' > "$F/epic-10"
  [ "$(story_order | tr '\n' ' ')" = "22 21 11 " ]
}

@test "snapshot: the story in flight wins over ready ones" {
  fake_github
  printf '' > "$F/roadmap"
  printf '%s\n' "3 story,state:verification-ready" "7 story,state:in-review" > "$F/stories"
  CONFIG=""
  snapshot
  [ "$S_STORY" = 7 ]
}

@test "snapshot: otherwise the first ready story in roadmap order, skipping others" {
  fake_github
  printf -- '- [ ] #30\n' > "$F/roadmap"
  printf -- '- [ ] #4\n- [ ] #5\n- [ ] #6\n' > "$F/epic-30"
  printf '%s\n' "4 story,state:planned" "5 story,state:verification-ready,needs-ceo" "6 story,state:verification-ready" > "$F/stories"
  CONFIG=""
  snapshot
  [ "$S_STORY" = 5 ] && [ "$S_NEEDS_CEO" = 1 ]
  [ -z "$S_PR" ]
}
