# shellcheck shell=bash
# Provisioning: set up a project, or update it to this kit version. Idempotent:
# a second run with nothing to change changes nothing. Runs on the host as the
# CEO (it needs admin on the repo); compatible with macOS bash 3.2.
#
# Kit files are tracked in .ai-proj-arch/manifest.txt: the kit version plus the
# SHA-256 of each kit-owned file *as the kit shipped it*. That tells a file the
# project edited apart from one it didn't, so an update never silently
# overwrites the project's own changes.

PROV_MANIFEST=.ai-proj-arch/manifest.txt
# Results of prov_apply, read by the caller.
PROV_REPORT=""
export PROV_CHANGED=0
PROV_BLOCK_KEY='AGENTS.md#kit'

prov_sha() {  # <file>  -> hex digest
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
  else shasum -a 256 "$1" | cut -d' ' -f1; fi
}
prov_sha_stdin() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum | cut -d' ' -f1
  else shasum -a 256 | cut -d' ' -f1; fi
}

# The kit block of an AGENTS.md (between the markers, exclusive).
prov_agents_block() {  # <agents.md>
  [ -f "$1" ] || return 0
  awk -v b="$KIT_AGENTS_BEGIN" -v e="$KIT_AGENTS_END" '
    $0 == e { inside = 0 }
    inside { print }
    $0 == b { inside = 1 }
  ' "$1"
}

# Render every kit-owned file into an empty staging dir, exactly as a fresh
# install would write it. Whole files only; AGENTS.md's block is keyed apart.
prov_stage() {  # <kit-root(ai-proj-arch checkout)> <staging-dir>
  local root=$1 stage=$2
  mkdir -p "$stage"
  git -C "$stage" init -q
  kit_install "$root/kit" "$stage" >/dev/null
  mkdir -p "$stage/.github/workflows/aipa"
  cp "$root/gates/workflows/aipa-gate.yml" "$stage/.github/workflows/"
  cp "$root/gates/workflows/aipa/verification-gate.sh" "$stage/.github/workflows/aipa/"
  rm -rf "$stage/.git"
}

# Kit-owned whole files in a staging dir (relative paths, sorted). Excludes
# what is merged rather than owned: AGENTS.md, CLAUDE.md, the project's
# settings file, and the .claude/skills symlink.
prov_owned_files() {  # <staging-dir>
  (cd "$1" && find . -type f ! -path './AGENTS.md' ! -path './CLAUDE.md' \
      ! -path './.ai-proj-arch/project.toml' ! -path './.claude/skills/*' ! -name '.agents-block*' \
    | sed 's|^\./||' | LC_ALL=C sort)
}

prov_manifest_get() {  # <manifest> <path>  -> recorded kit hash or ""
  [ -f "$1" ] || return 0
  awk -v p="$2" '$1 != "version" && $1 !~ /^#/ && substr($0, 67) == p { print $1; exit }' "$1"
}
prov_manifest_paths() {  # <manifest>
  [ -f "$1" ] || return 0
  awk '$1 != "version" && $1 !~ /^#/ && NF >= 2 { print substr($0, 67) }' "$1"
}

# Ask what to do with a kit file the project edited. Prints k, o or s.
# Never prompts without a terminal (or in a dry run): keeps the project's copy.
prov_ask() {  # <label> <old-version> <new-version> <project's-file> <kit's-file>
  local ans
  if [ -n "${AIPA_ANSWERS_FILE:-}" ]; then   # test hook: one answer per line, consumed in order
    ans=$(head -n 1 "$AIPA_ANSWERS_FILE"); sed -i.bak 1d "$AIPA_ANSWERS_FILE"; rm -f "$AIPA_ANSWERS_FILE.bak"
    printf '%s' "${ans:-k}"; return 0
  fi
  if [ "${PROV_DRY_RUN:-0}" = 1 ] || ! [ -t 0 ] || ! [ -r /dev/tty ]; then printf k; return 0; fi
  while :; do
    {
      printf '\n%s was edited in this project (kit %s -> %s)\n' "$1" "$2" "$3"
      printf '  [k] keep yours (default)   [o] overwrite with the kit version\n'
      printf '  [d] show the diff          [s] save the kit version beside it as %s.kit-new\n' "$(basename "$1")"
      printf 'Choice [k/o/d/s]: '
    } > /dev/tty
    IFS= read -r ans < /dev/tty || ans=k
    case "${ans:-k}" in
      k | K) printf k; return 0 ;;
      o | O) printf o; return 0 ;;
      s | S) printf s; return 0 ;;
      d | D) diff -u "$4" "$5" > /dev/tty || true ;;
    esac
  done
}

# Apply the staged kit to a project checkout. Fills PROV_REPORT (a Markdown
# list for the PR) and sets PROV_CHANGED=1 if anything changed.
prov_apply() {  # <staging-dir> <repo-dir> <new-version>
  local stage=$1 repo=$2 newv=$3 man oldv p new cur old choice tmp block_new block_cur block_old
  man="$repo/$PROV_MANIFEST"
  oldv=$(awk '$1 == "version" { print $2; exit }' "$man" 2>/dev/null || true)
  PROV_REPORT="" PROV_CHANGED=0
  note() { PROV_REPORT="$PROV_REPORT- $*"$'\n'; }

  while IFS= read -r p; do
    new=$(prov_sha "$stage/$p")
    if [ ! -e "$repo/$p" ]; then
      mkdir -p "$(dirname "$repo/$p")"; cp -p "$stage/$p" "$repo/$p"
      [ -n "$oldv" ] && note "added \`$p\`"
      PROV_CHANGED=1; continue
    fi
    cur=$(prov_sha "$repo/$p")
    [ "$cur" = "$new" ] && continue                   # already the kit's version
    old=$(prov_manifest_get "$man" "$p")
    if [ -n "$old" ] && [ "$cur" = "$old" ]; then      # untouched since the kit wrote it
      cp -p "$stage/$p" "$repo/$p"; note "updated \`$p\`"; PROV_CHANGED=1; continue
    fi
    if [ -n "$old" ] && [ "$old" = "$new" ]; then      # edited locally; kit didn't change it
      continue
    fi
    choice=$(prov_ask "$p" "${oldv:-none}" "$newv" "$repo/$p" "$stage/$p")
    case "$choice" in
      o) cp -p "$stage/$p" "$repo/$p"; note "\`$p\`: had local edits; **overwritten** with the kit version (CEO's choice)"; PROV_CHANGED=1 ;;
      s) cp -p "$stage/$p" "$repo/$p.kit-new"; note "\`$p\`: has local edits; **kept**, kit version saved as \`$p.kit-new\`"; PROV_CHANGED=1 ;;
      *) note "\`$p\`: has local edits; **kept** (kit version not applied)" ;;
    esac
  done < <(prov_owned_files "$stage")

  # Files the kit no longer ships: delete if untouched, otherwise ask.
  for p in $(prov_manifest_paths "$man"); do
    [ "$p" = "$PROV_BLOCK_KEY" ] && continue
    [ -e "$stage/$p" ] && continue
    [ -e "$repo/$p" ] || continue
    if [ "$(prov_sha "$repo/$p")" = "$(prov_manifest_get "$man" "$p")" ]; then
      rm -f "$repo/$p"; note "removed \`$p\` (no longer in the kit)"; PROV_CHANGED=1
    else
      note "\`$p\` is no longer in the kit but has local edits; **left in place**"
    fi
  done

  # The AGENTS.md kit block: the same rules, keyed as AGENTS.md#kit.
  prov_agents_block "$stage/AGENTS.md" > "$stage/.agents-block"
  block_new=$(prov_sha_stdin < "$stage/.agents-block")
  block_cur=$(prov_agents_block "$repo/AGENTS.md" | prov_sha_stdin)
  block_old=$(prov_manifest_get "$man" "$PROV_BLOCK_KEY")
  if ! grep -qF "$KIT_AGENTS_BEGIN" "$repo/AGENTS.md" 2>/dev/null; then
    kit_merge_agents_md "$stage/.agents-block" "$repo/AGENTS.md"; PROV_CHANGED=1
  elif [ "$block_cur" != "$block_new" ]; then
    if [ -n "$block_old" ] && [ "$block_cur" = "$block_old" ]; then
      kit_merge_agents_md "$stage/.agents-block" "$repo/AGENTS.md"; note "updated the kit block in \`AGENTS.md\`"; PROV_CHANGED=1
    elif [ "$block_old" != "$block_new" ]; then
      prov_agents_block "$repo/AGENTS.md" > "$stage/.agents-block-cur"
      choice=$(prov_ask "AGENTS.md (kit block)" "${oldv:-none}" "$newv" "$stage/.agents-block-cur" "$stage/.agents-block")
      case "$choice" in
        o) kit_merge_agents_md "$stage/.agents-block" "$repo/AGENTS.md"; note "\`AGENTS.md\` kit block: had local edits; **overwritten** (CEO's choice)"; PROV_CHANGED=1 ;;
        s) cp "$stage/.agents-block" "$repo/AGENTS.md.kit-new"; note "\`AGENTS.md\` kit block: local edits **kept**; kit version saved as \`AGENTS.md.kit-new\`"; PROV_CHANGED=1 ;;
        *) note "\`AGENTS.md\` kit block: local edits **kept**" ;;
      esac
    fi
  fi
  if [ ! -f "$repo/CLAUDE.md" ]; then cp "$stage/CLAUDE.md" "$repo/CLAUDE.md"; PROV_CHANGED=1
  elif ! grep -qx '@AGENTS.md' "$repo/CLAUDE.md"; then printf '\n@AGENTS.md\n' >> "$repo/CLAUDE.md"; note "added \`@AGENTS.md\` to \`CLAUDE.md\`"; PROV_CHANGED=1; fi
  if [ ! -f "$repo/.ai-proj-arch/project.toml" ]; then
    mkdir -p "$repo/.ai-proj-arch"; cp "$stage/.ai-proj-arch/project.toml" "$repo/.ai-proj-arch/project.toml"; PROV_CHANGED=1
  fi
  if [ ! -L "$repo/.claude/skills" ]; then
    [ -e "$repo/.claude/skills" ] && { echo "provision: $repo/.claude/skills is a real directory; move its skills into .agents/skills" >&2; return 1; }
    mkdir -p "$repo/.claude"; ln -s ../.agents/skills "$repo/.claude/skills"; PROV_CHANGED=1
  fi

  # The new manifest records the kit's own hashes.
  tmp=$(mktemp)
  {
    printf '# ai-proj-arch kit manifest. Written by provisioning; do not edit.\n'
    printf 'version %s\n' "$newv"
    while IFS= read -r p; do printf '%s  %s\n' "$(prov_sha "$stage/$p")" "$p"; done < <(prov_owned_files "$stage")
    printf '%s  %s\n' "$block_new" "$PROV_BLOCK_KEY"
  } > "$tmp"
  if ! cmp -s "$tmp" "$man" 2>/dev/null; then
    mkdir -p "$(dirname "$man")"; mv "$tmp" "$man"; PROV_CHANGED=1
  else
    rm -f "$tmp"
  fi
}

# ------------------------------------------------------------ version check
# Every run checks for a newer ai-proj-arch release and asks before switching
# this checkout to it, then restarts itself so the new version does the work.
# Never switches without a terminal, in a dry run, from a checkout with local
# changes, or to anything but a release tag from origin.
prov_version_check() {  # <kit-root> <original-args...>
  local root=$1 cur latest ans
  shift
  [ "${AIPA_NO_UPDATE_CHECK:-0}" = 1 ] && return 0
  [ "${AIPA_UPDATED:-0}" = 1 ] && return 0
  latest=$(git -C "$root" ls-remote --tags --refs origin 'v*' 2>/dev/null \
    | sed 's|.*refs/tags/||' | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -n 1) || true
  if [ -z "$latest" ]; then
    git -C "$root" ls-remote origin >/dev/null 2>&1 \
      || { echo "provision: couldn't check for a newer kit (offline?); continuing with this version" >&2; return 0; }
    return 0   # no releases yet
  fi
  cur=$(git -C "$root" describe --tags --exact-match 2>/dev/null || true)
  if [ -z "$cur" ]; then
    echo "provision: running from a development checkout; the latest release is $latest" >&2
    return 0
  fi
  [ "$cur" = "$latest" ] && return 0
  [ "$(printf '%s\n%s\n' "$cur" "$latest" | sort -V | tail -n 1)" = "$latest" ] || return 0
  echo "ai-proj-arch $latest is available (you have $cur)."
  echo "Release notes: https://github.com/dpeckham/ai-proj-arch/releases/tag/$latest"
  if [ "${PROV_DRY_RUN:-0}" = 1 ] || ! [ -t 0 ]; then
    echo "(not updating: dry run or no terminal)"; return 0
  fi
  printf 'Update the kit before provisioning? [Y/n] '
  IFS= read -r ans || ans=n
  case "${ans:-y}" in n | N | no) return 0 ;; esac
  [ -z "$(git -C "$root" status --porcelain)" ] \
    || { echo "provision: $root has local changes; not switching versions" >&2; return 0; }
  git -C "$root" fetch --quiet --tags origin
  git -C "$root" -c advice.detachedHead=false checkout --quiet "refs/tags/$latest"
  echo "switched to $latest; restarting"
  AIPA_UPDATED=1 exec bash "$root/bin/aipa" provision "$@"
}

# ------------------------------------------------------------- orchestration
prov_step() { printf '\n== %s\n' "$*"; }
prov_do() {  # <description> <command...>: run it, or just say so in a dry run
  local desc=$1
  shift
  if [ "${PROV_DRY_RUN:-0}" = 1 ]; then echo "would: $desc"; return 0; fi
  echo "$desc"
  "$@"
}

# Mint a bot token scoped to one repo, or fail (not installed there).
prov_bot_token() {  # <owner> <name>
  DNBG_REVIEWER_CONFIG_DIR="$AIPA_BOT_DIR" DNBG_REVIEWER_REPOSITORIES="$2" \
    bash "$KIT_ROOT/vendor/dnbg/dnbg-workflow/skills/reviewer/mint-token.sh" "$1" 2>/dev/null
}

prov_preflight() {  # <repo>
  local login status
  prov_step "Preflight"
  login=$(gh api user --jq .login 2>/dev/null) || die "gh isn't logged in. Run: gh auth login"
  echo "gh: logged in as $login"
  rt_require
  echo "container runtime: running"
  [ -f "$AIPA_BOT_DIR/config.json" ] && [ -f "$AIPA_BOT_DIR/private-key.pem" ] \
    || die "no bot App configured in $AIPA_BOT_DIR (see docs/container.md)"
  aipa_require_private_file "$AIPA_BOT_DIR/private-key.pem" "the bot App private key"
  if ! gh repo view "$1" >/dev/null 2>&1; then
    die "$1 doesn't exist or isn't visible to $login. Create it first: gh repo create $1 --private"
  fi
  [ "$(gh repo view "$1" --json viewerPermission --jq .viewerPermission)" = ADMIN ] \
    || die "$login needs admin rights on $1 to apply the gates"
  if ! prov_bot_token "${1%%/*}" "${1#*/}" >/dev/null; then
    die "the bot App ($(jq -r .slug "$AIPA_BOT_DIR/config.json")) isn't installed on $1. Add the repo here, then re-run: https://github.com/settings/installations"
  fi
  echo "bot App: installed on $1"
  status=$(gh api "repos/$1/rulesets" 2>&1 >/dev/null || true)
  case "$status" in
    *"Upgrade to GitHub Pro"*) die "$1 is private and this account can't enforce rulesets on private repos. Upgrade to GitHub Pro (or make the repo public); without it every gate is advisory" ;;
  esac
  echo "rulesets: available"
}

# Post neutral review checks on a CEO-authored kit update PR: they satisfy the
# required checks without pretending an agent reviewed it. The CEO still merges.
prov_kit_pr_checks() {  # <repo> <pr>
  local token sha role
  token=$(prov_bot_token "${1%%/*}" "${1#*/}") || return 1
  sha=$(gh pr view "$2" --repo "$1" --json headRefOid --jq .headRefOid)
  for role in qa eng ux; do
    jq -n --arg name "review/$role" --arg sha "$sha" \
      '{name: $name, head_sha: $sha, status: "completed", conclusion: "neutral",
        output: {title: "Kit update: not an agent review",
                 summary: "This PR updates the ai-proj-arch kit and was opened by provisioning for the CEO. No agent reviewed it; the CEO decides whether to merge."}}' \
      | GH_TOKEN=$token gh api -X POST "repos/$1/check-runs" --input - >/dev/null
  done
}

prov_kit() {  # <repo>
  local repo=$1 tmp work stage version branch default first pr body report
  prov_step "Kit files"
  version=$(aipa_kit_version)
  tmp=$(mktemp -d); work="$tmp/repo"; stage="$tmp/stage"
  gh repo clone "$repo" "$work" -- --quiet 2>/dev/null || die "could not clone $repo"
  default=$(git -C "$work" symbolic-ref --short refs/remotes/origin/HEAD | sed 's|^origin/||')
  # Commit straight to the default branch only on a first install to a repo
  # whose gates aren't on yet; anything else is a PR the CEO merges.
  first=0
  if [ ! -f "$work/$PROV_MANIFEST" ] && ! gh api "repos/$repo/rulesets" --jq '.[].name' 2>/dev/null | grep -qx 'aipa: protect main'; then
    first=1
  fi
  prov_stage "$KIT_ROOT" "$stage"
  prov_apply "$stage" "$work" "$version"
  if [ "$PROV_CHANGED" = 0 ]; then
    echo "kit $version: already installed, nothing to change"; rm -rf "$tmp"; return 0
  fi
  [ -n "$PROV_REPORT" ] && printf '%s' "$PROV_REPORT"
  if [ "${PROV_DRY_RUN:-0}" = 1 ]; then
    echo "would: commit kit $version ($( [ $first = 1 ] && echo "directly to $default, before the gates" || echo "as a PR for the CEO to merge"))"
    git -C "$work" status --short | head -n 20; rm -rf "$tmp"; return 0
  fi
  git -C "$work" add -A
  if [ "$first" = 1 ]; then
    git -C "$work" commit --quiet -m "Install the ai-proj-arch kit $version"
    git -C "$work" push --quiet origin "HEAD:$default"
    echo "installed kit $version on $default (before the gates are switched on)"
  else
    branch="aipa/kit-$version"
    git -C "$work" switch --quiet -c "$branch"
    git -C "$work" commit --quiet -m "Update the ai-proj-arch kit to $version"
    git -C "$work" push --quiet --force origin "$branch"
    report=${PROV_REPORT:-"- Kit files refreshed."}
    # shellcheck disable=SC2016  # backticks are Markdown
    body=$(printf 'Updates the ai-proj-arch kit to %s. Opened by provisioning for the CEO.\n\n## Changes\n\n%s\nFiles with local edits were handled as listed above; nothing was overwritten without your choice.\n\nThe `review/*` checks are **neutral** placeholders posted by provisioning: no agent reviewed this kit update. Merge it once you are happy with the diff.\n' "$version" "$report")
    pr=$(gh pr list --repo "$repo" --head "$branch" --state open --json number --jq '.[0].number // empty')
    if [ -n "$pr" ]; then
      gh pr edit "$pr" --repo "$repo" --body "$body" >/dev/null
    else
      pr=$(gh pr create --repo "$repo" --base "$default" --head "$branch" \
        --title "Update the ai-proj-arch kit to $version" --body "$body" | grep -oE '[0-9]+$')
    fi
    prov_kit_pr_checks "$repo" "$pr" || warn "could not post the placeholder review checks on PR #$pr"
    echo "kit update PR: https://github.com/$repo/pull/$pr (merge it when ready)"
  fi
  rm -rf "$tmp"
}

prov_status_branch() {  # <repo>
  local tmp
  prov_step "Status branch"
  if gh api "repos/$1/branches/status" >/dev/null 2>&1; then
    echo "status branch: exists"; return 0
  fi
  if [ "${PROV_DRY_RUN:-0}" = 1 ]; then echo "would: create the status branch with a starter STATUS.md"; return 0; fi
  tmp=$(mktemp -d)
  git -C "$tmp" init --quiet -b status
  sed "s/^# Status: <project>$/# Status: ${1#*/}/" "$KIT_ROOT/container/rootfs/usr/local/share/aipa/STATUS.md" > "$tmp/STATUS.md"
  git -C "$tmp" add STATUS.md
  git -C "$tmp" -c user.name="$(gh api user --jq .login)" -c user.email="$(gh api user --jq '.id|tostring')+$(gh api user --jq .login)@users.noreply.github.com" \
    commit --quiet -m "Start STATUS.md"
  # Authenticate through gh, never the OS keychain helper from global config.
  git -C "$tmp" -c credential.helper= -c 'credential.helper=!gh auth git-credential' \
    push --quiet "https://github.com/$1.git" status
  rm -rf "$tmp"
  echo "status branch: created"
}

prov_gates() {  # <repo> [extra apply.sh args...]
  local repo=$1
  shift
  prov_step "Gates"
  if [ "${PROV_DRY_RUN:-0}" = 1 ]; then echo "would: apply labels and the two rulesets (gates/apply.sh)"; return 0; fi
  "$KIT_ROOT/gates/apply.sh" "$repo" "$@"
}

prov_host() {  # <project> <repo> [--main-dir <dir>]
  local project=$1 repo=$2
  shift 2
  prov_step "Host and container"
  if [ "${PROV_DRY_RUN:-0}" = 1 ]; then
    echo "would: aipa create $project --repo $repo $* (config, host checkout, image $(aipa_image_ref), volume, container)"
    return 0
  fi
  local name want have ans
  name=$(aipa_container_name "$project")
  if [ "$(rt_container_state "$name")" != absent ]; then
    want=$(rt_image_digest "$(aipa_image_ref)"); have=$(rt_container_image_digest "$name")
    if [ -n "$want" ] && [ "$want" != "$have" ] && [ -t 0 ]; then
      printf '%s was created from an older image. Recreate it now? Its home volume is kept, but a running PM session or work loop stops. [y/N] ' "$name"
      IFS= read -r ans || ans=n
      case "$ans" in y | Y | yes) set -- "$@" --recreate ;; esac
    fi
  fi
  bash "$KIT_ROOT/bin/aipa" create "$project" --repo "$repo" "$@"
}
