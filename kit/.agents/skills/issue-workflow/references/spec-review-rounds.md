# Issue workflow: answering a spec review
<!-- Adapted for ai-proj-arch from dbaggott/claude-plugins (Apache-2.0):
     dnbg-workflow/skills/issue-workflow/references/spec-review-rounds.md at
     9a4c0b7. The background wait is removed; the original is in
     vendor/dnbg/upstream/. -->

Part of the `issue-workflow` skill. Read this when a reviewer is reviewing your
issue bodies as specs, posting a verdict per issue per round with findings you
answer. `references/creating.md` covers writing a body in the first place; the
reviewer's side is the `issue-reviewer` skill.

This is not the review of the PRs that resolve an issue — those arrive as PR
reviews and are answered through `git-workflow`'s `references/review-rounds.md`.

## What a round looks like

One comment per issue, carrying a verdict — `READY` or `CHANGES REQUESTED` — the
`lastEditedAt` it was reviewed against, and findings with IDs: `<issue>-B<n>`
blocking, `<issue>-O<n>` observations. `CHANGES REQUESTED` means at least one
blocking finding; observations do not block a `READY`.

Check that published `lastEditedAt` against your body's current value. If the body
moved after it, the round straddled an edit and was made against text you have
already replaced — say so rather than answering findings that may no longer apply.

## Answering

**Edit the body first, then comment.** The comment is the receipt for edits
already made. Reversing it makes the reviewer read a body that does not yet carry
what you claimed, and report a fix missing that is not.

**Respond per finding ID**, dispositioning each one:

- **Fixed** — point at what changed in the body. The reviewer reads the diff, so
  the response need not reproduce it.
- **Rejected, with reasoning** — a legitimate outcome, not a stalling move. A
  reviewer who accepts the reasoning converges on it.

A finding answered with neither is undispositioned, and a round of those is what
halts the review.

**Do not edit the body again after posting the response.** The body is quiescent
from that moment: the receipt is fixed and the reviewer is reading against it. An
edit you genuinely need afterwards opens a **new round** — make it, then say so in
a fresh comment.

## Waiting for the next round

*ai-proj-arch:* don't wait or poll. Post your response, write your report and exit. Whoever runs the review (the PM, or the work loop) runs you again for the next round.

## Where it ends

The review converges when every blocking finding is dispositioned and the reviewer
accepts the disposition; the final verdict says so. It can also halt — a round
that disposes nothing new leaves the remainder as an operator decision.

Fold anything the review established that changes what a resolver should build
into the body, per "Maintaining issues" in `SKILL.md`: a fact living only in a
comment is invisible to the handoff. Picking the issue up is then
`references/resolving.md`.
