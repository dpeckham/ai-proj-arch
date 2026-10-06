#!/usr/bin/env bats
load helpers

setup() {
  setup_isolated
  # shellcheck source=../lib/aipa/kit.sh
  . "$ROOT/lib/aipa/kit.sh"
  # shellcheck source=../lib/aipa/provision.sh
  . "$ROOT/lib/aipa/provision.sh"
  KIT_ROOT=$ROOT
  STAGE="$BATS_TEST_TMPDIR/stage"; prov_stage "$ROOT" "$STAGE"
  REPO_DIR="$BATS_TEST_TMPDIR/repo"; git init -q -b main "$REPO_DIR"
}

# A second kit version: a copy of the stage with edits applied by the caller.
stage2() { rm -rf "$BATS_TEST_TMPDIR/stage2"; cp -R "$STAGE" "$BATS_TEST_TMPDIR/stage2"; STAGE2="$BATS_TEST_TMPDIR/stage2"; }

@test "stage holds the kit plus the gate workflow, and no merged files are owned" {
  [ -f "$STAGE/.github/workflows/aipa-gate.yml" ]
  [ -x "$STAGE/.github/workflows/aipa/verification-gate.sh" ]
  run prov_owned_files "$STAGE"
  [[ "$output" == *".agents/skills/aipa-pm/SKILL.md"* ]]
  [[ "$output" != *"AGENTS.md"$'\n'* ]] && [[ "$output" != *"CLAUDE.md"* ]] && [[ "$output" != *"project.toml"* ]]
}

@test "first install writes everything and a manifest; a second run changes nothing" {
  prov_apply "$STAGE" "$REPO_DIR" 0.1.0
  [ "$PROV_CHANGED" = 1 ]
  [ -f "$REPO_DIR/.agents/skills/aipa-coder/SKILL.md" ] && [ -L "$REPO_DIR/.claude/skills" ]
  [ -f "$REPO_DIR/.ai-proj-arch/project.toml" ] && grep -qF '<!-- aipa:begin kit -->' "$REPO_DIR/AGENTS.md"
  grep -q '^version 0.1.0$' "$REPO_DIR/$PROV_MANIFEST"
  grep -q '  AGENTS.md#kit$' "$REPO_DIR/$PROV_MANIFEST"
  [ "$(grep -c '  .agents/skills/' "$REPO_DIR/$PROV_MANIFEST")" -gt 10 ]
  prov_apply "$STAGE" "$REPO_DIR" 0.1.0
  [ "$PROV_CHANGED" = 0 ] && [ -z "$PROV_REPORT" ]
}

@test "a project's own file at a kit path is kept on first install without a terminal" {
  mkdir -p "$REPO_DIR/.github"; echo "our template" > "$REPO_DIR/.github/pull_request_template.md"
  prov_apply "$STAGE" "$REPO_DIR" 0.1.0 < /dev/null
  [ "$(cat "$REPO_DIR/.github/pull_request_template.md")" = "our template" ]
  [[ "$PROV_REPORT" == *"pull_request_template.md"*"kept"* ]]
}

@test "update: untouched files follow the kit, edited ones ask (overwrite, save beside, keep)" {
  prov_apply "$STAGE" "$REPO_DIR" 0.1.0
  echo "project edit" >> "$REPO_DIR/.agents/skills/aipa-qa-lead/SKILL.md"
  echo "project edit" >> "$REPO_DIR/.agents/skills/aipa-ux-designer/SKILL.md"
  echo "project edit" >> "$REPO_DIR/.agents/skills/aipa-coder/SKILL.md"
  stage2
  for s in aipa-pm aipa-qa-lead aipa-ux-designer aipa-coder; do echo "kit v2 line" >> "$STAGE2/.agents/skills/$s/SKILL.md"; done
  printf 'o\ns\nk\n' > "$BATS_TEST_TMPDIR/answers"   # files are visited in sorted order: coder, qa-lead, ux-designer
  AIPA_ANSWERS_FILE="$BATS_TEST_TMPDIR/answers" prov_apply "$STAGE2" "$REPO_DIR" 0.2.0
  grep -q "kit v2 line" "$REPO_DIR/.agents/skills/aipa-pm/SKILL.md"                     # untouched -> updated
  [ "$(tail -1 "$REPO_DIR/.agents/skills/aipa-coder/SKILL.md")" = "kit v2 line" ]        # o: overwritten
  grep -q "project edit" "$REPO_DIR/.agents/skills/aipa-qa-lead/SKILL.md"               # s: kept...
  grep -q "kit v2 line" "$REPO_DIR/.agents/skills/aipa-qa-lead/SKILL.md.kit-new"        # ...kit beside it
  grep -q "project edit" "$REPO_DIR/.agents/skills/aipa-ux-designer/SKILL.md"           # k: kept
  ! grep -q "kit v2 line" "$REPO_DIR/.agents/skills/aipa-ux-designer/SKILL.md"
  [[ "$PROV_REPORT" == *"aipa-pm/SKILL.md"* ]] && [[ "$PROV_REPORT" == *"overwritten"* ]] && [[ "$PROV_REPORT" == *"kit-new"* ]]
}

@test "update: a local edit to a file the kit didn't change is left alone silently" {
  prov_apply "$STAGE" "$REPO_DIR" 0.1.0
  echo "project edit" >> "$REPO_DIR/.agents/skills/aipa-pm/SKILL.md"
  stage2; echo "x" >> "$STAGE2/.agents/skills/aipa-coder/SKILL.md"
  prov_apply "$STAGE2" "$REPO_DIR" 0.2.0 < /dev/null
  grep -q "project edit" "$REPO_DIR/.agents/skills/aipa-pm/SKILL.md"
  [[ "$PROV_REPORT" != *"aipa-pm"* ]]
}

@test "update: files dropped from the kit are removed if untouched, kept if edited" {
  prov_apply "$STAGE" "$REPO_DIR" 0.1.0
  echo "edit" >> "$REPO_DIR/.agents/scripts/pr-sources.sh"
  stage2; rm "$STAGE2/.agents/scripts/fetch-tree.sh" "$STAGE2/.agents/scripts/pr-sources.sh"
  prov_apply "$STAGE2" "$REPO_DIR" 0.2.0 < /dev/null
  [ ! -e "$REPO_DIR/.agents/scripts/fetch-tree.sh" ]
  [ -e "$REPO_DIR/.agents/scripts/pr-sources.sh" ]
  [[ "$PROV_REPORT" == *"removed"*"fetch-tree.sh"* ]] && [[ "$PROV_REPORT" == *"pr-sources.sh"*"left in place"* ]]
  ! grep -q 'fetch-tree.sh' "$REPO_DIR/$PROV_MANIFEST"
}

@test "update: the AGENTS.md kit block follows the kit unless edited, and the rest is kept" {
  printf '# Project\n\nOur own rules.\n' > "$REPO_DIR/AGENTS.md"
  prov_apply "$STAGE" "$REPO_DIR" 0.1.0
  stage2; sed -i.bak 's/## How this project is run/## How this project is run (v2)/' "$STAGE2/AGENTS.md"; rm -f "$STAGE2/AGENTS.md.bak"
  prov_apply "$STAGE2" "$REPO_DIR" 0.2.0 < /dev/null
  grep -q "(v2)" "$REPO_DIR/AGENTS.md" && grep -q "Our own rules." "$REPO_DIR/AGENTS.md"
  sed -i.bak 's/^- \*\*Only the CEO merges.\*\*/- **Only the CEO merges, always.**/' "$REPO_DIR/AGENTS.md"; rm -f "$REPO_DIR/AGENTS.md.bak"
  stage2; sed -i.bak 's/(v2)/(v3)/' "$STAGE2/AGENTS.md"; rm -f "$STAGE2/AGENTS.md.bak"
  prov_apply "$STAGE2" "$REPO_DIR" 0.3.0 < /dev/null
  grep -q "always." "$REPO_DIR/AGENTS.md" && ! grep -q "(v3)" "$REPO_DIR/AGENTS.md"
  [[ "$PROV_REPORT" == *"AGENTS.md"*"kit block"*"kept"* ]]
}

@test "the project's settings file is created once and never overwritten" {
  prov_apply "$STAGE" "$REPO_DIR" 0.1.0
  printf '[harness]\ncoder = "codex"\n' > "$REPO_DIR/.ai-proj-arch/project.toml"
  prov_apply "$STAGE" "$REPO_DIR" 0.1.0
  grep -q 'coder = "codex"' "$REPO_DIR/.ai-proj-arch/project.toml"
}

# A kit checkout whose origin has release tags.
kit_with_tags() {
  export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
  git init -q --bare -b main "$BATS_TEST_TMPDIR/kit.git"
  K="$BATS_TEST_TMPDIR/kit"; git clone -q "$BATS_TEST_TMPDIR/kit.git" "$K" 2>/dev/null
  git -C "$K" commit -q --allow-empty -m one && git -C "$K" tag v0.1.0
  git -C "$K" commit -q --allow-empty -m two && git -C "$K" tag v0.10.0
  git -C "$K" push -q origin main --tags
}

@test "version check: an older release tag hears about the newer one, but never switches without a terminal" {
  kit_with_tags
  git -C "$K" -c advice.detachedHead=false checkout -q v0.1.0
  run prov_version_check "$K" yb < /dev/null
  [ "$status" -eq 0 ]
  [[ "$output" == *"v0.10.0 is available (you have v0.1.0)"* ]]
  [[ "$output" == *"not updating"* ]]
  [ "$(git -C "$K" describe --tags --exact-match)" = v0.1.0 ]
}

@test "version check: quiet on the latest release; a note on a dev checkout; skippable" {
  kit_with_tags
  git -C "$K" -c advice.detachedHead=false checkout -q v0.10.0
  run prov_version_check "$K" yb < /dev/null;  [ -z "$output" ]
  git -C "$K" switch -q main; git -C "$K" commit -q --allow-empty -m dev
  run prov_version_check "$K" yb < /dev/null;  [[ "$output" == *"development checkout"*"v0.10.0"* ]]
  AIPA_NO_UPDATE_CHECK=1 run prov_version_check "$K" yb < /dev/null; [ -z "$output" ]
}
