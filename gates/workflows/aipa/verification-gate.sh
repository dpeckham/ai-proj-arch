#!/usr/bin/env bash
# Gate: no verification plan, no start.
#
# Fails a pull request opened by an agent (the bot) unless every story it closes
#   1. is labeled state:verification-ready, state:in-progress or state:in-review, and
#   2. has a "## Verification plan" section with real content.
# Pull requests from humans (the CEO) pass with a note.
#
# Installed into each project at .github/workflows/aipa/verification-gate.sh,
# where the bot cannot change it: GitHub refuses any push from an App without
# the `workflows` permission that touches .github/workflows/. The workflow runs
# it from the base branch (pull_request_target), never from the PR's code.
#
# Env: REPO (owner/name), PR_NUMBER, GH_TOKEN. Optional GITHUB_STEP_SUMMARY.
set -euo pipefail

READY_STATES="state:verification-ready state:in-progress state:in-review"

summary() { printf '%s\n' "$*" >> "${GITHUB_STEP_SUMMARY:-/dev/null}"; printf '%s\n' "$*"; }

# Print the body of the "Verification plan" section: from a heading whose text
# starts with "Verification plan" (any level, any case) to the next heading of
# the same or a higher level.
plan_section() {
  awk '
    BEGIN { inside = 0; level = 0 }
    /^#+[ \t]/ {
      n = match($0, /^#+/); lvl = RLENGTH
      text = tolower(substr($0, lvl + 1)); sub(/^[ \t]+/, "", text)
      if (inside && lvl <= level) { inside = 0 }
      if (!inside && index(text, "verification plan") == 1) { inside = 1; level = lvl; next }
    }
    inside { print }
  '
}

# A plan counts when it has at least one line of real content: not blank, not
# an HTML comment, and not a placeholder such as TBD, TODO, N/A or "...".
plan_has_content() {
  plan_section | sed -e 's/<!--.*-->//g' | awk '
    /<!--/ { incomment = 1 }
    incomment { if (/-->/) incomment = 0; next }
    {
      line = $0
      gsub(/^[ \t]*([-*+]|[0-9]+[.)])?[ \t]*(\[[ xX]\])?[ \t]*/, "", line)
      gsub(/[ \t*_`]+$/, "", line); gsub(/^[*_`]+/, "", line)
      l = tolower(line)
      if (l == "" || l ~ /^(tbd|todo|n\/a|na|none|\.\.\.|…|-)$/) next
      found = 1
    }
    END { exit found ? 0 : 1 }
  '
}

main() {
  : "${REPO:?REPO is required}" "${PR_NUMBER:?PR_NUMBER is required}"
  local owner=${REPO%%/*} name=${REPO#*/} pr author_type author issues count failures=0

  # shellcheck disable=SC2016  # GraphQL variables, not shell
  pr=$(gh api graphql -F owner="$owner" -F name="$name" -F number="$PR_NUMBER" -f query='
    query($owner: String!, $name: String!, $number: Int!) {
      repository(owner: $owner, name: $name) {
        pullRequest(number: $number) {
          author { login __typename }
          closingIssuesReferences(first: 20) {
            nodes { number title state body labels(first: 50) { nodes { name } } }
          }
        }
      }
    }')
  author=$(printf '%s' "$pr" | jq -r '.data.repository.pullRequest.author.login')
  author_type=$(printf '%s' "$pr" | jq -r '.data.repository.pullRequest.author.__typename')

  summary "## Verification-plan gate"
  if [ "$author_type" != Bot ]; then
    summary "Pull request by $author (not an agent): the gate does not apply."
    return 0
  fi

  issues=$(printf '%s' "$pr" | jq -c '.data.repository.pullRequest.closingIssuesReferences.nodes')
  count=$(printf '%s' "$issues" | jq 'length')
  if [ "$count" -eq 0 ]; then
    summary "**Fail:** this pull request doesn't close a story. Add \`Closes #<story>\` to its description."
    return 1
  fi

  local i number title state labels body ok_state s
  for ((i = 0; i < count; i++)); do
    number=$(printf '%s' "$issues" | jq -r ".[$i].number")
    title=$(printf '%s' "$issues" | jq -r ".[$i].title")
    state=$(printf '%s' "$issues" | jq -r ".[$i].state")
    labels=$(printf '%s' "$issues" | jq -r ".[$i].labels.nodes[].name")
    body=$(printf '%s' "$issues" | jq -r ".[$i].body // \"\"")

    ok_state=0
    for s in $READY_STATES; do
      printf '%s\n' "$labels" | grep -qxF "$s" && ok_state=1
    done

    if [ "$state" != OPEN ]; then
      summary "- **Fail** #$number ($title): the story is $state, not open."
      failures=$((failures + 1))
    elif [ "$ok_state" = 0 ]; then
      summary "- **Fail** #$number ($title): not labeled as ready. Needs one of: $READY_STATES."
      failures=$((failures + 1))
    elif ! printf '%s\n' "$body" | plan_has_content; then
      summary "- **Fail** #$number ($title): no verification plan. Add a \"## Verification plan\" section with real content."
      failures=$((failures + 1))
    else
      summary "- **Pass** #$number ($title)"
    fi
  done

  [ "$failures" -eq 0 ]
}

# Run main only when executed, so tests can source the functions.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
