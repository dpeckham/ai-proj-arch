# GitHub gates

The process is enforced by GitHub, not by prompts, so it holds the same way for Claude Code, Codex and anything else ([#5](https://github.com/dpeckham/ai-proj-arch/issues/5)).

| Gate | How it's enforced |
| --- | --- |
| **No verification plan, no start** | The `aipa-gate` Action posts the required check `gate/verification-plan`. It fails any agent PR unless every story it closes is open, is labeled `state:verification-ready`, `state:in-progress` or `state:in-review`, and has a `## Verification plan` section with real content |
| **Separate reviewer verdicts** | Required checks `review/qa`, `review/eng` and `review/ux`. These are accepted **only from the bot App**. A commit status with the same name from any other account doesn't count. Use `neutral` for "not applicable" (for example `review/ux` with no UI change); it satisfies the check |
| **Only the CEO merges** | The ruleset "aipa: only the CEO merges" lets no one update `main` except the repository admin role (the CEO), and only through a pull request. The bot can't merge even when every check is green |
| **Even the CEO can't merge red** | The ruleset "aipa: protect main" (PR required, all checks green, no force-push or deletion) has **no** bypass actors. The CEO's bypass covers only the merge restriction above, so a merge can never skip a failing check |
| **Agents can't weaken the gates** | The bot App has no Workflows permission, and GitHub rejects any push from it that touches `.github/workflows/`, including the gate script in `.github/workflows/aipa/`. The workflow uses `pull_request_target`, so it always runs the gate from `main`, never from the PR |

Private repos need **GitHub Pro** (or Team). Without it, GitHub refuses rulesets on private repos and every gate becomes advisory.

## How the CEO merges

Every merge is an explicit bypass of "only the CEO merges":

- **Web UI:** tick the bypass checkbox in the merge box, then merge
- **CLI:** `gh pr merge <n> --merge --admin`

This only works when every required check is green. With a red check, GitHub refuses even the CEO: "4 of 4 required status checks have not succeeded".

## Applying the gates

```bash
gates/apply.sh <owner>/<repo> [--check <ci-job-name>]...
```

Run it on the host as the CEO. It creates or updates the labels and both rulesets, and re-running it changes nothing. Use `--check` to add the project's CI job as a required check. Commit `gates/workflows/aipa-gate.yml` to `.github/workflows/`, and `gates/workflows/aipa/` to `.github/workflows/aipa/`, before applying the rulesets. Provisioning ([#3](https://github.com/dpeckham/ai-proj-arch/issues/3)) does both.

Reviewer roles post their verdicts from inside the container with:

```bash
aipa-review-check <qa|eng|ux> <pr> <success|failure|neutral> "<title>" < summary.md
```

## Verified on `dpeckham/aipa-sandbox` (Oct 5, 2026)

| Test | Result |
| --- | --- |
| CEO pushes straight to `main` | Rejected: "Cannot update this protected ref" |
| Bot PR that closes no story | Gate fails: "doesn't close a story" |
| Bot PR closing a ready story with a plan | Gate passes |
| Story whose plan is only "TBD" and a comment | Gate fails. Passes after the plan is written and the PR is edited |
| CEO posts a `review/qa` commit status | Ignored. The PR stays blocked |
| Bot posts `review/qa`, `review/eng`, `review/ux` (including `neutral`) | Required checks satisfied |
| Bot merges with every check green (`gh pr merge` and the REST merge endpoint) | Refused |
| CEO merges a green PR with the bypass | Merged; the story closed automatically |
| CEO merges a red PR with the bypass | Refused |
| `gates/apply.sh` run twice | Rulesets updated in place; still exactly 2 |

## Known limitations

- **One identity for every agent.** All agents act as the same bot, so GitHub can't tell QA's `review/qa` from one a Coder might post, or who applied a state label. The gate does check that the plan has real content, but which role posts which verdict is up to the work loop ([#6](https://github.com/dpeckham/ai-proj-arch/issues/6)), not GitHub
- **Editing a story doesn't re-run the gate.** After fixing a story's plan or label, edit the PR description, push, or re-run the check. The work loop should do this itself
- **The CEO's own PRs need the same checks.** Kit updates opened by provisioning need `review/*` verdicts too. Have the agents review them like any other PR
