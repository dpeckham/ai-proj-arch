---
name: git-workflow
description: How to change any tracked file in a covered repo — worktree, draft PR, review rounds, merge handoff, post-merge cleanup. Load before you edit, write, or modify any tracked file in a covered repo (application code, skills, plugins, docs, configs, tests — anything that would show up in `git status`), and when opening a PR (including pairing PRs across repos for one multi-repo change), marking one ready, watching for or addressing review feedback, or cleaning up after a merge. The trigger is a tracked file changing, not the user's choice of words.
---
<!-- Adapted for ai-proj-arch from dbaggott/claude-plugins (Apache-2.0):
     dnbg-workflow/skills/git-workflow/SKILL.md at 9a4c0b7. Changes are marked
     "ai-proj-arch:"; the original is in vendor/dnbg/upstream/. -->

# Git workflow

> **ai-proj-arch:** In this project you usually run as the **Coder**, headless, started by the work loop for one story. Nobody is there to answer during the run, so wherever this skill says to ask or tell the operator, write it in your final report instead. If it blocks the story, also comment on the story issue. **Only the CEO merges.**

This is the standard flow for any code change in a covered repo. *ai-proj-arch:
every repo you work in is covered.* Never modify the main checkout directly;
always work in a worktree. (In the container, `/work/main` is the CEO's view of
`main`: never edit it, and never create worktrees from it.)

## This flow is GitHub-only

Every step below drives `gh` — `gh pr`, `gh api`, GraphQL `reviewThreads` — so
on another forge it is not merely degraded, it cannot run at all. Before step 1,
read the host of the repo you are about to change:

```bash
git remote get-url origin
```

**If the host is not `github.com`, stop and decline.** Say that this flow is
GitHub-only, name the host you actually found, and fall back to whatever flow
the project already uses. Do not run a `gh` command against it first, and do not
translate the flow to `glab` or another forge's CLI.

These are **not** a decline:

- **No `origin`.** A local-only repo, or one whose remotes are named something
  else, makes no forge claim either way. Don't degrade and don't assume GitHub —
  proceed and let the operator direct.
- **Several remotes.** `origin` decides, matching what the enforcement hooks do.

`velocity-tradeoff` ships in this same plugin and is **not** GitHub-only — it
mentions no forge and applies wherever you are. Declining is per skill, never
per plugin.

## Starting a change

**If this work originates from an existing issue** (the task named an issue number or URL), load `issue-workflow` and claim the issue *before* the steps below — claiming and the freshness probe come before the worktree, not after. Don't let "the work ends in file edits" pull you straight here; issue pickup is the entry action, this flow is just the destination.

1. `git fetch origin` — fetches all refs so later diffs against other branches don't surprise you with stale data.
2. `gh pr list --repo <repo> --state open` — if any open PR might touch the files you're about to change, check its diff (`gh pr diff <num>`) and either coordinate or hold off. Independent staleness check from the fetch above: that one catches a stale base, this one catches concurrent work — without it, two PRs against the same node in the same file can both rebase cleanly and one becomes a wasted no-op the moment the other merges.
3. Re-read any files you touched in a prior session — code may have changed.
4. `git worktree add .worktrees/<branch-name> -b <branch-name> origin/<default-branch>` — the default branch comes from the settings read below; don't assume `main`. If the change spans repos, the branch name is the pairing key; see "Multi-repo changes" below before picking it.
5. Make changes in the worktree.
6. Commit.
7. **Self-review the branch, and address what it finds** — before pushing:
   - **Against the standards** — the set the always-on "Coding standards stack" rule had you load. `git diff origin/<default-branch>...<branch-name>`, read against those files re-opened rather than recalled: you wrote the diff from memory of them, so memory is what needs checking. Where a standard names something countable, grep the diff for it instead of eyeballing.
   - **For defects, with the harness's code-review tool.** In Claude Code that is `/code-review origin/<default-branch>...<branch-name>`. Name both ends: the branch's upstream stops meaning the base once the branch is pushed, and the review may run from a checkout other than the worktree, where `HEAD` is not your branch. Leave the effort level to whatever the operator last chose, except never `ultra`, which is a billed cloud run the operator starts themselves. Don't pass `--fix` — findings need triage, not blanket application.

   Fix a finding in this branch by default. Decline one that is wrong or out of scope, with a one-line reason. One pass: the fixes go to the reviewer with everything else rather than back through the tool. Where the harness has no code-review tool, the standards pass is the whole stage — say so when you announce the PR. *ai-proj-arch: in a headless run, skip the code-review tool; the standards pass is the whole stage.*
8. Push, and **open the PR as a draft** (`gh pr create --draft ...`).
9. After each commit, update the PR description if needed so it reflects the **as-built** state, written per **"Writing the PR description"** below — we do not narrate the development history in the description.
10. *ai-proj-arch:* When the self-review is done and the change meets the story's acceptance criteria and verification plan, mark the PR ready (`gh pr ready <number> --repo <repo>`). Then write your report (the format is in `references/merge.md`, "Report back") and **exit. Don't watch for reviews.** The work loop starts the reviewers, and runs you again for each round of findings, following `references/review-rounds.md`.
11. *ai-proj-arch:* If you can't finish (blocked, the story is wrong, a decision is needed), leave the PR in draft. Comment on the story with what's needed, say the same in your report, and exit.
12. Never merge. Only the CEO merges PRs.

Worktrees live in `.worktrees/` inside the repo. Ensure `.worktrees` is in `.gitignore`.

**`.worktrees/` is the default, not a constant.** It is configurable, so if a `dnbg-workflow` note at session start names a different worktree root, that note wins and every `.worktrees/` in this skill means the root it names — including the `git worktree add` in step 4 and the `git worktree remove` in the post-merge cleanup. With no such note, the literal above is what this session uses.

**Concurrent work is the norm — other worktrees are not a finding.** `.worktrees/` routinely holds branches from other sessions, other agents, and the operator's own in-flight work. Their presence is expected, needs no report, and is not evidence anything is wrong. Never touch one you didn't create.

What *is* worth raising is a concrete collision: step 2's open-PR check, or a sibling worktree, shows work landing on the same files or the same design surface as yours. Flag that with the specific overlap — "`<branch>` also edits `src/auth.ts:40-70`" — so the operator can decide whether to coordinate. The signal is the conflict, not the parallelism.

## Know the repo's merge settings

Later steps depend on how this particular repo is configured: which branch to fork from, how the merge command is composed, whether a push dismisses an approval, and what the post-merge cleanup still has to do. **Read them, don't assume them** — these settings vary between an org's repos and a personal account's, and between two repos in the same account.

Read once per repo, early:

```bash
gh api repos/<owner>/<repo> --jq \
  '{default_branch, allow_auto_merge, allow_squash_merge, allow_merge_commit,
    allow_rebase_merge, delete_branch_on_merge}'
```

| Field | What it decides |
| --- | --- |
| `default_branch` | what you branch from and target — not necessarily `main` |
| `allow_auto_merge` | whether `gh pr merge --auto` works at all |
| `allow_squash_merge` / `allow_merge_commit` / `allow_rebase_merge` | which merge flag to hand the operator, and whether the branch tip ends up an ancestor of the base (which decides `-d` vs `-D` locally) |
| `delete_branch_on_merge` | whether the remote branch still needs deleting after the merge |

Throughout this skill and its references, `<skill-dir>` is the directory that holds this `SKILL.md` (*ai-proj-arch:* `.agents/skills/git-workflow`), not the directory of a reference file you are reading. The scripts sit beside the skills rather than inside one, so the same `../../scripts/` reaches them from every skill that shares them.

*ai-proj-arch:* **Verdicts here are check runs, not PR reviews.** Every agent acts as the same bot, and GitHub doesn't let a PR's author approve it. So each reviewer role posts a check instead: `review/qa`, `review/eng`, `review/ux`. HEAD is approved **iff** all of the following are true on the **current head SHA**:
- `gate/verification-plan` is `success`
- `review/qa` and `review/eng` are `success`
- `review/ux` is `success` or `neutral` (neutral means no UI change)

```bash
gh pr checks <num> --repo <owner>/<repo>
```

Checks belong to a commit, so a push leaves the new head with no `review/*` checks until the reviewers run again. That's the "is this verdict still current?" answer for free.

For a multi-repo change, read this **per repo**. Siblings genuinely differ, and a setting borrowed from the wrong one produces a merge command that fails or a cleanup step that silently does nothing.

## Writing the PR description

The description reflects the **as-built** state, rewritten after each commit — and every claim in it must be *true and earned*. A reviewer who catches one inflated claim discounts the whole description, so the asymmetry is stark: under-claiming costs nothing, over-claiming costs trust.

- **Name what you verified, and how — don't imply more.** "Typechecks (`tsc`)" and "CI green" are not "tested"; "eyeballed one case on dev" is not "verified end-to-end." State the check you actually ran; if you didn't run one, don't phrase the body so it reads as if you did.
- **Don't assert coverage you don't have.** No unit runner for a file? Say its helpers are covered by typecheck + manual, not that they're "tested." Never describe intended or aspirational tests as existing ones.
- **Don't state impact without evidence.** Performance, cost, "fixes X for all inputs" — back it with the measurement or the reasoning, or hedge it. A confident-sounding number with no source is an over-claim.
- **Claim only the scope you checked.** The over-claim usually starts one step earlier, as an unexamined assumption written up as fact: that a change generalizes, that it fixes the root cause (not just the symptom you reproduced), that the correlation you saw is the cause, that nothing else is affected. Verify the assumption, or state the scope you actually verified ("fixes the observed case; other inputs unchecked"; "removes the symptom — root cause not confirmed"). An assumption is not a result.
- **Surface gaps, not just wins.** Known limitations, unverified branches, and deferred follow-ups belong in the body — these are as-built facts about the result, not the development narrative ruled out above; omitting them reads as "all handled," and the next reader inherits the surprise.

When unsure whether a claim is earned, weaken it or cut it — a description a reviewer can trust line-for-line is worth more than an impressive one they have to second-guess.

**Claim less, rather than more precisely.** The bar above pushes toward accuracy, and accuracy pushes toward checkable detail — a count, a percentage, a file list. Each of those is something a reviewer can verify, and verifying it costs a round whether or not it was worth stating. Ask what they do differently for having it: a number that scopes the diff earns its place; a number that only describes the work does not. Precision about a quantity that moves is the worst case, since it is guaranteed to drift where a true loose claim survives the next commit.

**If the only fix is to correct the message, the message was the defect.** When a finding's whole remedy is editing prose that ships — this description, a commit message, a changelog fragment — and nobody acts on the detail, cut the claim instead of correcting it. Correcting keeps the liability and spends the round again the next time it drifts.

**Where the number *is* the evidence, keep it and bound what it supports.** A measurement an argument rests on cannot be loosened away without taking the argument with it. State what it does and does not establish — "observed once in nine cycles, which is a floor on the rate rather than an estimate of it" — so a reader cannot over-read it and a later count cannot falsify a claim you never made. That is the third option whenever cutting would cost the point.

**If a `## dnbg-workflow <version>` note appeared at session start, end the description with the version stamp it names:**

```
<!-- dnbg-workflow <version> -->
```

It renders invisibly. Re-state it on every rewrite, carrying the rewriting session's version rather than the original. With no note, leave the stamp off — do not take the version from the manifest or from memory, since nothing downstream can tell a guessed version from a read one.

## Multi-repo changes

When one logical change spans repos (e.g. an infrastructure change plus the application change it enables), pair the PRs so a list view shows what goes with what:

1. **Same branch name in every repo.** Pick the branch name once and reuse it verbatim for each repo's worktree. It's the join key: it exists before any PR does (no ordering problem), it shows in `gh pr list`, and `gh search prs --owner <owner> head:<branch-name>` returns the whole set.
2. **Shared title tag.** Prefix every sibling PR's title with the branch name in brackets — `[<branch-name>] <title>`. github.com's PR list doesn't show branch names, so the tag is what makes the pairing visible there. The tag *is* the branch name, not a separate slug — one join key, derivable in both directions.

3. **Every sibling references the issue by full URL; exactly one closes it.** When the set resolves an issue, put the issue URL in *each* PR's body — the sibling's opening line is a good home ("The infrastructure half of `<issue URL>`"). Only the PR that actually completes the work carries a closing keyword (`Closes <issue URL>`); the others just mention it.

   The mention is the only thing that makes a sibling discoverable from the issue — every route back to it is driven by the mention, so a sibling that omits it cannot be found from the issue at all, and anyone working from that issue sees a set that looks complete and is not. The branch name pairs the PRs to each other; the issue URL ties the set to the issue. Both are needed.

Single-repo PRs (the common case) stay untagged — the tag's presence is itself the signal that siblings exist in other repos.

If a change turns multi-repo midway — the first PR is already open when you discover a second repo needs to change — reuse its branch name for the new worktree and retitle the open PR to add the tag (`gh pr edit <num> --repo <repo> --title "..."`) when you open the sibling.

## After opening a draft PR

*ai-proj-arch (replaces the operator picker):* If you made a substantive design change mid-implementation, such as a departure from the story's Plan, a contract or interface change, or anything a reviewer would be surprised by, say so before marking the PR ready. Write it in a PR comment headed `**[CODER]** Design change`, and in your report, so the CEO and the reviewers learn the design moved before they review it. Per `issue-workflow`'s "Surface design changes that emerge mid-implementation", a change big enough to need the PM's or CEO's agreement means leaving the PR in draft and reporting a blocker instead.

Then follow steps 10 and 11 above. Never offer the CEO an option to run `gh pr ready` themselves.

## Issue and PR references

Full GitHub URLs, always — per the always-on rule "Reference issues and PRs by full URL". The rationale and the memory-file exception live there.

## When a PR merges

The post-merge cleanup is in `references/merge.md`, and it runs before any new work. Reach it from `references/review-rounds.md` when a review comes back clean or its watch reports the PR closed, and straight from here when you are simply told a PR merged — a resumed session, or one that only ever opened the PR.

## After rebase or merge

Always review incoming changes after rebasing or merging. Don't assume the prior state is still accurate — read the changed files before answering questions about them.

## Related skills

Optional — everything above is actionable without them.

- **Your project's coding standards.** The comment bar and the
  `enforceable > prose > nothing` ordering used in `references/review-rounds.md` come
  from somewhere. *ai-proj-arch:* the `coding-practices` skill carries them, along
  with anything in this repo's `AGENTS.md`.
