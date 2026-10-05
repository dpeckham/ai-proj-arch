#!/usr/bin/env bash
# End-to-end check of a real project container. Needs apple/container, the bot
# App, and a project already set up with `aipa create` and `aipa start`.
#
#   tests/integration/e2e.sh <project> [--push] [--harness]
#
#   --push     also push (then delete) a throwaway branch as the bot, and check
#              that a workflow change is rejected
#   --harness  also run one tiny prompt through Claude Code and Codex
#
# Never prints a token. Leaves no branches or files behind.
set -euo pipefail

PROJECT=${1:?usage: e2e.sh <project> [--push] [--harness]}
shift
PUSH=0 HARNESS=0
for a in "$@"; do
  case "$a" in
    --push) PUSH=1 ;;
    --harness) HARNESS=1 ;;
    *) echo "unknown option: $a" >&2; exit 2 ;;
  esac
done

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=../../lib/aipa/common.sh
. "$ROOT/lib/aipa/common.sh"
aipa_load_project "$PROJECT"
NAME=$(aipa_container_name "$PROJECT")
WORK="/home/agent/work/$AIPA_REPO_NAME"

pass=0 fail=0
check() {  # <description> <command...>
  local desc=$1
  shift
  if "$@" >/dev/null 2>&1; then
    printf 'ok    %s\n' "$desc"; pass=$((pass + 1))
  else
    printf 'FAIL  %s\n' "$desc"; fail=$((fail + 1))
  fi
}
in_agent() { container exec --user agent --env HOME=/home/agent --workdir "$WORK" "$NAME" bash -c "$1"; }
in_agent_harness() {
  container exec --env-file "$AIPA_HARNESS_ENV" --user agent --env HOME=/home/agent --workdir "$WORK" "$NAME" bash -c "$1"
}
expect_output() {  # <expected> <cmd...>
  local want=$1 got
  shift
  got=$("$@" 2>/dev/null) || return 1
  [ "$got" = "$want" ]
}

echo "== $PROJECT ($AIPA_REPO) in $NAME"
check "container is running" expect_output running \
  bash -c "container inspect '$NAME' | jq -r '.[0].status.state'"
check "agents run as the non-root user 'agent'" expect_output agent in_agent 'id -un'
check "tools are installed" in_agent 'git --version && gh --version && tmux -V && claude --version && codex --version && bwrap --version'
check "the bot token is present" in_agent 'test -s /run/aipa/gh-token'
check "/run/aipa is read-only" bash -c "! container exec --user agent '$NAME' sh -c 'echo x > /run/aipa/probe' 2>/dev/null"
check "gh acts as the bot" expect_output "$(jq -r .slug "$AIPA_BOT_DIR/config.json")[bot]" \
  in_agent 'gh api graphql -f query="{viewer{login}}" --jq .data.viewer.login'
check "the token covers only this repo" expect_output "$AIPA_REPO_NAME" \
  in_agent 'gh api /installation/repositories --jq "[.repositories[].name] | join(\",\")"'
check "git commits are authored as the bot" in_agent 'git config user.name | grep -q "\[bot\]$"'
check "the agent clone exists and fetches" in_agent 'git fetch --quiet origin'
check "main on the host is a fast-forward-only checkout" in_agent 'aipa-sync-main'
check "a detached tmux session survives its creator exiting" \
  bash -c "container exec --user agent --env HOME=/home/agent '$NAME' tmux new-session -d -s e2e-probe 'sleep 300' && sleep 1 && container exec --user agent --env HOME=/home/agent '$NAME' tmux has-session -t e2e-probe && container exec --user agent --env HOME=/home/agent '$NAME' tmux kill-session -t e2e-probe"

if [ "$PUSH" = 1 ]; then
  branch="aipa/e2e-$(date +%s)"
  check "push a throwaway branch as the bot" in_agent "
    git switch -q -c '$branch' origin/main &&
    git commit -q --allow-empty -m 'e2e: throwaway commit' &&
    git push -q origin '$branch'"
  check "a workflow change is rejected for the bot" in_agent "
    mkdir -p .github/workflows && printf 'on: push\njobs: {}\n' > .github/workflows/e2e-probe.yml &&
    git add .github/workflows/e2e-probe.yml && git commit -q -m 'e2e: workflow probe' &&
    ! git push -q origin '$branch' 2>/dev/null"
  check "clean up the throwaway branch" in_agent "
    git push -q origin --delete '$branch' && git switch -q main && git branch -q -D '$branch'"
fi

if [ "$HARNESS" = 1 ]; then
  check "Claude Code answers a prompt" expect_output E2E-OK \
    in_agent_harness 'claude -p "Reply with the word E2E-OK only."'
  check "Codex answers a prompt" expect_output E2E-OK \
    in_agent 'codex exec --sandbox danger-full-access "Reply with the word E2E-OK only." 2>/dev/null'
fi

echo "== $pass passed, $fail failed"
[ "$fail" -eq 0 ]
