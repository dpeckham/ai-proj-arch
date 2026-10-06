# The project kit

The kit is everything an ai-proj-arch project carries in its own repo ([#4](https://github.com/dpeckham/ai-proj-arch/issues/4)). It lives in `kit/` here, and provisioning ([#3](https://github.com/dpeckham/ai-proj-arch/issues/3)) installs it. Until provisioning exists, `kit_install` in `lib/aipa/kit.sh` does the file-level part.

| In the project | From | What it is |
| --- | --- | --- |
| `.agents/skills/aipa-*` | `kit/.agents/skills/` | Role skills: `aipa-pm`, `aipa-lead-engineer`, `aipa-qa-lead`, `aipa-ux-designer`, `aipa-coder`, and `aipa-review-round` (how any reviewer runs one round) |
| `.agents/skills/{git-workflow,issue-workflow,coding-practices,velocity-tradeoff}` | Dan Baggott's [claude-plugins](https://github.com/dbaggott/claude-plugins) at `9a4c0b7` | Patched for headless runs and one shared bot identity. Every change is marked `ai-proj-arch:`. The originals are in `vendor/dnbg/upstream/` |
| `.agents/scripts/` | Dan's scripts, unmodified | `pr-round.sh`, `pr-threads.sh`, `fetch-pr-state.sh` and friends |
| `.claude/skills` | symlink to `../.agents/skills` | One set of skills for both harnesses: Codex reads `.agents/skills`, Claude Code follows the link |
| `.claude/agents/*.md`, `.codex/agents/*.toml` | rendered from `kit/agents/*.md` | The consultant subagents (`lead-engineer`, `qa-lead`, `ux-designer`) in each harness's format |
| `AGENTS.md` (kit block), `CLAUDE.md` | `kit/AGENTS.kit.md`, `kit/CLAUDE.md` | Always-on rules, including Dan's, between `aipa:begin kit` and `aipa:end kit` markers. `CLAUDE.md` imports `AGENTS.md` |
| `.github/ISSUE_TEMPLATE/`, `pull_request_template.md` | `kit/.github/` | Roadmap, Epic and Story (with `## Verification plan`) templates, and the as-built PR template |
| `.agents/THIRD_PARTY_NOTICES.md`, `LICENSE.dnbg` | `kit/.agents/` | Apache-2.0 attribution for the adapted files |

In the container image (not the repo): `aipa-status` reads and updates `STATUS.md` on the `status` branch, so the PM and the work loop each update only their own sections, safely, even at the same time. `aipa-review-check` posts a reviewer's verdict as a check.

## How Dan's workflow was adapted

His workflow assumes an interactive operator, a reviewer bot separate from the author, and agents that watch PRs. Here, every agent is the same bot, verdicts are check runs, and the work loop orchestrates. So:

- **Pickers and questions** (`AskUserQuestion`) → the run's final report, plus a comment on the story if it blocks
- **Watching PRs** (`watch-pr.sh`, background tasks) → removed; the work loop runs each role once per round
- **`--approve` and `--request-changes`** (GitHub rejects both on the bot's own PRs) → a `COMMENT` review for inline findings, plus a `review/<role>` check for the verdict
- **Filtering by login** (one login for everyone) → role tags (`**[QA]**`, `**[ENG]**`, `**[UX]**`, `**[CODER]**`) on every comment, and `pr-round.sh … __none__`
- **Claiming with `@me` and a session id** → the work loop claims, and the run id comes from `AIPA_RUN_ID`
- **Enforcement hooks** → instructions in `AGENTS.md`, and the GitHub gates (#5)

## Verified live on `dpeckham/aipa-sandbox` (Oct 6, 2026)

| Role | Harness | Result |
| --- | --- | --- |
| PM | Claude Code | Created the Roadmap, an Epic and two Stories, with plans from the `lead-engineer` and verification plans from the `qa-lead` subagents. It moved both to `state:verification-ready`, created the `status` branch, wrote "Coming up", and raised two decisions and a behavior change for the CEO |
| PM | Codex | Edited the Roadmap's checklist, added an Epic and a Story with both kinds of plan, and updated "Coming up" in order |
| Coder | Claude Code | Implemented a story in a worktree and opened PR #14 as the bot (draft, then ready). Ran every verification-plan case and the plan's mutation check. The gate passed |
| Reviewer `eng` | Claude Code | Probed edge cases in a scratch worktree, removed it, and posted `review/eng` |
| Reviewer `qa` | Codex | Posted `review/qa` |
| Reviewer `ux` | Codex | Probed the CLI output and posted `review/ux` |

All three `review/*` checks came from the bot App and passed. The PR stayed BLOCKED for the CEO's merge, as designed. The reviewers found that `pr-round.sh` needs `pr-verdict.sh`, which is now shipped, and a test guards against missing script dependencies.

Not yet run live: the Coder on Codex, QA and UX on Claude Code, and a review round with findings followed by a fix round. The work loop (#6) will drive those.
