#!/usr/bin/env bash
# Apply the ai-proj-arch gates to a repository: labels and the two rulesets on
# the default branch. Idempotent: re-running updates in place. Runs on the host
# as the CEO (it needs admin rights on the repo), never inside a container.
#
#   gates/apply.sh <owner>/<repo> [--check <name>]...
#
#   --check  an extra required status check (for example the project's CI job)
#
# The workflow files (.github/workflows/aipa-gate.yml and .github/workflows/aipa/)
# are committed by provisioning, not by this script.
set -euo pipefail

GATES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ACTIONS_APP_ID=15368          # GitHub Actions: the only allowed source of gate/*
ADMIN_ROLE_ID=5               # repository "admin" role: the CEO

die() { printf 'gates: %s\n' "$*" >&2; exit 1; }

REPO=${1:-}
case "$REPO" in
  */*) ;;
  *) die "usage: gates/apply.sh <owner>/<repo> [--check <name>]..." ;;
esac
shift
EXTRA_CHECKS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --check) [ -n "${2:-}" ] || die "--check needs a name"; EXTRA_CHECKS+=("$2"); shift 2 ;;
    *) die "unknown option: $1" ;;
  esac
done

BOT_CONFIG="${AIPA_BOT_DIR:-${AIPA_CONFIG_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/ai-proj-arch}/bot}/config.json"
BOT_APP_ID=$(sed -n 's/.*"app_id"[[:space:]]*:[[:space:]]*"\{0,1\}\([0-9][0-9]*\)"\{0,1\}.*/\1/p' "$BOT_CONFIG" 2>/dev/null | head -n 1)
[ -n "$BOT_APP_ID" ] || die "no app_id in $BOT_CONFIG"

json_str() { printf '"%s"' "$(printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')"; }

# ------------------------------------------------------------------- labels
while IFS=$'\t' read -r name color desc; do
  case "$name" in "" | \#*) continue ;; esac
  gh label create "$name" --repo "$REPO" --color "$color" --description "$desc" --force >/dev/null
  echo "label   $name"
done < "$GATES_DIR/labels.tsv"

# ----------------------------------------------------------------- rulesets
required_checks() {
  local first=1 c
  emit() {  # <context> <integration-id|"">
    [ "$first" = 1 ] || printf ','
    first=0
    if [ -n "$2" ]; then
      printf '{"context":%s,"integration_id":%s}' "$(json_str "$1")" "$2"
    else
      printf '{"context":%s}' "$(json_str "$1")"
    fi
  }
  emit gate/verification-plan "$ACTIONS_APP_ID"
  emit review/qa "$BOT_APP_ID"
  emit review/eng "$BOT_APP_ID"
  emit review/ux "$BOT_APP_ID"
  for c in ${EXTRA_CHECKS[@]+"${EXTRA_CHECKS[@]}"}; do emit "$c" ""; done
}

ceo_bypass='[{"actor_id":'"$ADMIN_ROLE_ID"',"actor_type":"RepositoryRole","bypass_mode":"pull_request"}]'
on_default_branch='{"ref_name":{"include":["~DEFAULT_BRANCH"],"exclude":[]}}'

# Everyone, the CEO included, goes through a pull request with every check
# green. No bypass: the CEO's bypass on the other ruleset only lets them merge,
# so the routine "bypass" click can never skip a red check.
protect_main() {
  cat <<JSON
{
  "name": "aipa: protect main",
  "target": "branch",
  "enforcement": "active",
  "conditions": $on_default_branch,
  "bypass_actors": [],
  "rules": [
    {"type": "deletion"},
    {"type": "non_fast_forward"},
    {"type": "pull_request", "parameters": {
      "required_approving_review_count": 0,
      "dismiss_stale_reviews_on_push": false,
      "require_code_owner_review": false,
      "require_last_push_approval": false,
      "required_review_thread_resolution": false
    }},
    {"type": "required_status_checks", "parameters": {
      "strict_required_status_checks_policy": false,
      "do_not_enforce_on_create": false,
      "required_status_checks": [$(required_checks)]
    }}
  ]
}
JSON
}

# Nobody but the CEO can update the default branch, so the bot can never
# merge, even with every check green.
ceo_merges() {
  cat <<JSON
{
  "name": "aipa: only the CEO merges",
  "target": "branch",
  "enforcement": "active",
  "conditions": $on_default_branch,
  "bypass_actors": $ceo_bypass,
  "rules": [
    {"type": "update", "parameters": {"update_allows_fetch_and_merge": false}}
  ]
}
JSON
}

apply_ruleset() {  # <name> <json-producing function>
  local id
  id=$(gh api "repos/$REPO/rulesets" --jq ".[] | select(.name == \"$1\") | .id" | head -n 1)
  if [ -n "$id" ]; then
    "$2" | gh api -X PUT "repos/$REPO/rulesets/$id" --input - >/dev/null
    echo "ruleset $1 (updated)"
  else
    "$2" | gh api -X POST "repos/$REPO/rulesets" --input - >/dev/null
    echo "ruleset $1 (created)"
  fi
}

apply_ruleset "aipa: protect main" protect_main
apply_ruleset "aipa: only the CEO merges" ceo_merges
