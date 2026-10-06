#!/usr/bin/env bats
load helpers

GATE_REL=gates/workflows/aipa/verification-gate.sh

setup() {
  setup_isolated
  # shellcheck source=../gates/workflows/aipa/verification-gate.sh
  . "$ROOT/$GATE_REL"
}

has_plan() { printf '%s\n' "$1" | plan_has_content; }

@test "a plan with real content counts" {
  run has_plan $'## Spec\nx\n\n## Verification plan\n\n- Run `go test ./...` and expect the new case to pass\n\n## Acceptance criteria\n- y'
  [ "$status" -eq 0 ]
}

@test "heading level and case don't matter, extra words are fine" {
  run has_plan $'### verification Plan (QA)\n1. Import the sample file and compare totals'
  [ "$status" -eq 0 ]
}

@test "missing, empty, placeholder or comment-only plans don't count" {
  run has_plan $'## Spec\nsomething'; [ "$status" -ne 0 ]
  run has_plan $'## Verification plan\n\n## Acceptance criteria\n- real text here'; [ "$status" -ne 0 ]
  run has_plan $'## Verification plan\n- TBD\n- [ ] TODO\n_N/A_\n...'; [ "$status" -ne 0 ]
  run has_plan $'## Verification plan\n<!-- QA: describe how this will be verified -->\n<!--\nmulti-line\n-->'; [ "$status" -ne 0 ]
}

@test "content under a deeper subheading still belongs to the plan" {
  run has_plan $'## Verification plan\n### Unit\n- Add a test for rounding\n## Notes\n- n'
  [ "$status" -eq 0 ]
}

@test "content after the next same-level heading doesn't count" {
  run has_plan $'## Verification plan\n\n## Notes\n- this is not a plan'
  [ "$status" -ne 0 ]
}

# A fake gh that answers the GraphQL query with a fixture.
gh_returns() {  # <json>
  printf '%s' "$1" > "$BATS_TEST_TMPDIR/pr.json"
  fake gh <<EOF2
cat "$BATS_TEST_TMPDIR/pr.json"
EOF2
}

pr_json() {  # <author-type> <issues-json>
  printf '{"data":{"repository":{"pullRequest":{"author":{"login":"x","__typename":"%s"},"closingIssuesReferences":{"nodes":%s}}}}}' "$1" "$2"
}

story() {  # <number> <state> <label> <body>
  printf '{"number":%s,"title":"Story %s","state":"%s","body":%s,"labels":{"nodes":[{"name":"story"},{"name":"%s"}]}}' \
    "$1" "$1" "$2" "$(printf '%s' "$4" | jq -Rs .)" "$3"
}

run_gate() { REPO=o/r PR_NUMBER=7 run bash "$ROOT/$GATE_REL"; }

@test "human pull requests pass without a story" {
  gh_returns "$(pr_json User '[]')"
  run_gate
  [ "$status" -eq 0 ]; [[ "$output" == *"does not apply"* ]]
}

@test "an agent pull request without a story fails" {
  gh_returns "$(pr_json Bot '[]')"
  run_gate
  [ "$status" -ne 0 ]; [[ "$output" == *"doesn't close a story"* ]]
}

@test "an agent pull request passes only with a ready story that has a plan" {
  plan=$'## Verification plan\n- Run the importer on the sample and check the balance'
  gh_returns "$(pr_json Bot "[$(story 3 OPEN state:verification-ready "$plan")]")"
  run_gate; [ "$status" -eq 0 ]; [[ "$output" == *"Pass"*"#3"* ]]

  gh_returns "$(pr_json Bot "[$(story 3 OPEN state:planned "$plan")]")"
  run_gate; [ "$status" -ne 0 ]; [[ "$output" == *"not labeled as ready"* ]]

  gh_returns "$(pr_json Bot "[$(story 3 OPEN state:in-progress $'## Verification plan\n- TBD')]")"
  run_gate; [ "$status" -ne 0 ]; [[ "$output" == *"no verification plan"* ]]

  gh_returns "$(pr_json Bot "[$(story 3 CLOSED state:in-review "$plan")]")"
  run_gate; [ "$status" -ne 0 ]; [[ "$output" == *"not open"* ]]
}

@test "every linked story must pass" {
  plan=$'## Verification plan\n- Check the totals match the bank statement'
  gh_returns "$(pr_json Bot "[$(story 3 OPEN state:in-progress "$plan"),$(story 4 OPEN state:idea "$plan")]")"
  run_gate
  [ "$status" -ne 0 ]; [[ "$output" == *"Pass"*"#3"* ]]; [[ "$output" == *"Fail"*"#4"* ]]
}
