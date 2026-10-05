# Git workflow: review rounds

<!-- Adapted for ai-proj-arch from dbaggott/claude-plugins (Apache-2.0):
     dnbg-workflow/skills/git-workflow/references/review-rounds.md at 9a4c0b7.
     Upstream's watch and operator picker are replaced by one headless fix
     round per run; "Responding to reviewers" is kept with marked changes. -->

Part of the `git-workflow` skill. *ai-proj-arch:* read this when the work loop
runs you, the Coder, to address a review round on your PR. There is no watch
and no operator picker. Each run handles **one** round, then exits, and the loop
runs you again if more findings come in.

## Reading the round

The loop's prompt gives you the PR, the head SHA you last pushed (empty on the
first round) and the time the round started. **Read the whole round in one call:**

```bash
"<skill-dir>/../../scripts/pr-round.sh" <owner>/<repo> <n> "<last-pushed-sha-or-empty>" <since-iso> __none__
```

Every agent posts as the same bot login, so pass the slug `__none__` (it matches
no one) so that nobody's comments are filtered out. The script prints these sections:

- **`── diff ──`** — what changed since your last push.
- **`── activity ──`** — `"kind":"review"` is a review body; `"kind":"inline"` a finding filed on a line of the diff. Inline findings don't appear in `gh pr view --json reviews`, so read them here. Each inline object's `id` is the REST comment id. It isn't the `PRRT_…` thread id, which is in `── threads ──`.
- **`── threads ──`** — every unresolved thread. A reviewer reads an open thread as outstanding work.
- **The `_src` fields** — an empty section means "nothing there" only where its status reads `ok`.

**Ignore its `verdict`, `verdict_sha`, `at_head` and `reviewed_after_head` fields.**
They come from PR reviews, and here verdicts are check runs. The verdict for this
round is each reviewer's check on the head SHA you were reviewed at:

```bash
gh pr checks <n> --repo <owner>/<repo>
```

Each comment begins with its author's role tag (`**[QA]**`, `**[ENG]**`,
`**[UX]**`). That's how you tell the reviewers apart, since they share one login.

## Handling the round

- **No open findings, and every `review/*` check is `success`** (UX may be `neutral`): nothing to do. Say so in your report and exit. Only the CEO merges.
- **Findings:** address every in-scope finding in this run. Fix it in the branch by default. Push once, at the end of the round, after re-running the relevant parts of the story's verification plan.
- **Scope creep, or a finding you think is wrong:** decline it with a short, reasoned reply in its thread, and list it in your report for the CEO. Don't silently skip it.
- **A finding you can't resolve without a decision** (the story's plan was wrong, or a requirement conflicts): comment on the story with the question, list it as a blocker in your report, and exit without pushing a half-fix.

Then write your report (format in `references/merge.md`, "Report back") and exit.

## Responding to reviewers

*ai-proj-arch:* start every comment and reply with `**[CODER]**`, and address a reviewer by their role tag (`[QA]`, `[ENG]`, `[UX]`). `@`-mentioning the bot reaches nobody.

**Put the answer where the next review will look**, and prefer the durable forms — **enforceable > prose > nothing**, applied to review:

1. **A test.** It proves the claim and fails loudly if it stops being true. Best answer to "are you sure this handles X?" by a wide margin.
2. **The code.** If the concern is real, the fix *is* the answer.
3. **The PR body.** For what you verified and how, what scope you checked, why one approach beat another. This is the as-built record, and the right home for evidence and provenance.

**Reply in the thread itself.** *ai-proj-arch: don't resolve it; the reviewer who opened it resolves it on their next round once they're satisfied, so an open thread keeps meaning outstanding work for that role.* A top-level PR comment does not close a thread, and an unresolved thread is how a reviewer tracks outstanding work — so answering at the top level leaves the finding looking untouched no matter how thoroughly you fixed it. Use the `PRRT_…` id from the round packet's `── threads ──` section:

```bash
gh api graphql -f query='mutation($t:ID!,$b:String!){addPullRequestReviewThreadReply(
  input:{pullRequestReviewThreadId:$t,body:$b}){clientMutationId}}' -f t=<thread-id> -f b='**[CODER]** <reply>'
```

*ai-proj-arch:* say in the reply whether you fixed it (with the commit) or are declining it. A thread you are declining to act on stays open with your reasoning in it — that is a disagreement to surface, not a box to tick.

**A code comment is the last resort, and only when it would have earned its place anyway.** A reviewer's question is not a licence to add prose that fails the bar every comment has to clear: *will this still be true after the next change, and does it change what someone does?* An answer that exists only because someone asked once is transient state — if the only action a changing world requires is deleting the line, it was never a comment — and it will read as inexplicable defensiveness to the next person. If the answer is a *current, non-obvious constraint a future editor needs*, it was already worth a comment before the review; if it isn't, the PR body is where it goes.

When a finding you have already answered is re-raised, say so once and point at where the answer lives. Don't re-litigate it, and don't read the repetition as the answer having been rejected.

