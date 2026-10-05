#!/usr/bin/env bats
load helpers

setup() {
  setup_isolated
  # shellcheck source=../lib/aipa/kit.sh
  . "$ROOT/lib/aipa/kit.sh"
  OUT="$BATS_TEST_TMPDIR/out"
}

@test "every kit subagent renders for both harnesses" {
  kit_render_agents "$ROOT/kit/agents" "$OUT"
  for f in "$ROOT"/kit/agents/*.md; do
    n=$(basename "$f" .md)
    [ -f "$OUT/.claude/agents/$n.md" ]
    [ -f "$OUT/.codex/agents/$n.toml" ]
  done
}

@test "Codex agent files are valid TOML with the source's fields" {
  kit_render_agents "$ROOT/kit/agents" "$OUT"
  python3 - "$OUT/.codex/agents" "$ROOT/kit/agents" <<'PY'
import sys, tomllib, pathlib
out, src = map(pathlib.Path, sys.argv[1:])
for t in out.glob("*.toml"):
    d = tomllib.loads(t.read_text())
    assert set(d) == {"name", "description", "developer_instructions"}, d.keys()
    s = (src / f"{d['name']}.md").read_text()
    assert d["description"] in s and d["developer_instructions"].strip() in s
PY
}

@test "Claude agent files start with the frontmatter Claude Code reads" {
  kit_render_agents "$ROOT/kit/agents" "$OUT"
  f="$OUT/.claude/agents/qa-lead.md"
  [ "$(sed -n 1p "$f")" = "---" ]
  [ "$(sed -n 2p "$f")" = "name: qa-lead" ]
  [[ "$(sed -n 3p "$f")" == "description: QA Lead consultant."* ]]
  grep -q "Edit the source, not this file" "$f"
}

@test "quotes and backslashes in a description are escaped for TOML" {
  mkdir -p "$BATS_TEST_TMPDIR/src"
  printf -- '---\nname: odd\ndescription: Say "hi" \\ bye\n---\nBody.\n' > "$BATS_TEST_TMPDIR/src/odd.md"
  kit_render_agents "$BATS_TEST_TMPDIR/src" "$OUT"
  python3 -c 'import tomllib,sys; d=tomllib.load(open(sys.argv[1],"rb")); assert d["description"]=="Say \"hi\" \\ bye", d' "$OUT/.codex/agents/odd.toml"
}

@test "bad sources are refused" {
  mkdir -p "$BATS_TEST_TMPDIR/src"
  printf -- '---\nname: Bad Name\ndescription: d\n---\nB\n' > "$BATS_TEST_TMPDIR/src/x.md"
  run kit_render_agents "$BATS_TEST_TMPDIR/src" "$OUT"; [ "$status" -ne 0 ]
  rm "$BATS_TEST_TMPDIR/src/x.md"
  printf -- "---\nname: y\ndescription: d\n---\nhas ''' inside\n" > "$BATS_TEST_TMPDIR/src/y.md"
  run kit_render_agents "$BATS_TEST_TMPDIR/src" "$OUT"; [ "$status" -ne 0 ]
  rm "$BATS_TEST_TMPDIR/src/y.md"
  printf -- '---\nname: z\ndescription: d\n---\nB\n' > "$BATS_TEST_TMPDIR/src/other.md"
  run kit_render_agents "$BATS_TEST_TMPDIR/src" "$OUT"; [ "$status" -ne 0 ]; [[ "$output" == *"must match"* ]]
}

new_repo() { git init -q -b main "$1"; }

@test "install lays out skills, scripts, agents, templates and instructions" {
  R="$BATS_TEST_TMPDIR/repo"; new_repo "$R"
  kit_install "$ROOT/kit" "$R"
  [ -f "$R/.agents/skills/aipa-pm/SKILL.md" ]
  [ -f "$R/.agents/skills/git-workflow/references/review-rounds.md" ]
  [ -x "$R/.agents/scripts/pr-round.sh" ]
  [ "$(readlink "$R/.claude/skills")" = ../.agents/skills ]
  [ -f "$R/.claude/skills/aipa-coder/SKILL.md" ]          # resolves through the link
  [ -f "$R/.claude/agents/qa-lead.md" ] && [ -f "$R/.codex/agents/qa-lead.toml" ]
  [ -f "$R/.github/ISSUE_TEMPLATE/story.md" ] && [ -f "$R/.github/pull_request_template.md" ]
  [ "$(cat "$R/CLAUDE.md")" = "@AGENTS.md" ]
  grep -qF '<!-- aipa:begin kit -->' "$R/AGENTS.md"
  [ -f "$R/.agents/LICENSE.dnbg" ] && [ -f "$R/.agents/THIRD_PARTY_NOTICES.md" ]
}

@test "install keeps the project's own AGENTS.md and CLAUDE.md content" {
  R="$BATS_TEST_TMPDIR/repo"; new_repo "$R"
  printf '# Yawnbooks\n\nUse go 1.25.\n' > "$R/AGENTS.md"
  printf 'Project notes.\n' > "$R/CLAUDE.md"
  kit_install "$ROOT/kit" "$R"
  grep -q 'Use go 1.25.' "$R/AGENTS.md"
  grep -q 'Project notes.' "$R/CLAUDE.md"
  grep -qx '@AGENTS.md' "$R/CLAUDE.md"
}

@test "re-installing replaces only the kit block" {
  R="$BATS_TEST_TMPDIR/repo"; new_repo "$R"
  printf '# P\n\nmine before\n' > "$R/AGENTS.md"
  kit_install "$ROOT/kit" "$R"
  printf 'mine after\n' >> "$R/AGENTS.md"
  kit_install "$ROOT/kit" "$R"
  [ "$(grep -cF '<!-- aipa:begin kit -->' "$R/AGENTS.md")" = 1 ]
  grep -q 'mine before' "$R/AGENTS.md" && grep -q 'mine after' "$R/AGENTS.md"
  [ "$(grep -cx '@AGENTS.md' "$R/CLAUDE.md")" = 1 ]
}

@test "install refuses a real .claude/skills directory" {
  R="$BATS_TEST_TMPDIR/repo"; new_repo "$R"
  mkdir -p "$R/.claude/skills/mine"
  run kit_install "$ROOT/kit" "$R"
  [ "$status" -ne 0 ]; [[ "$output" == *"not a symlink"* ]]
}

@test "every kit skill has a name matching its directory and a description" {
  for d in "$ROOT"/kit/.agents/skills/*/; do
    n=$(basename "$d")
    [ "$(kit_frontmatter_get "$d/SKILL.md" name)" = "$n" ]
    [ -n "$(kit_frontmatter_get "$d/SKILL.md" description)" ]
  done
}

@test "shipped skills don't tell agents to mint tokens, approve, or watch" {
  run grep -rnE 'mint-token|--approve|--request-changes|run_in_background|watch-pr\.sh|AskUserQuestion|pr-verdict' "$ROOT/kit/.agents/skills"
  # Mentions are allowed only where a line explains that it must NOT be done.
  bad=$(printf '%s\n' "$output" | grep -vE 'never|Never|don.t|isn.t|not |no |No |won.t' || true)
  [ -z "$bad" ] || { echo "$bad"; false; }
}
