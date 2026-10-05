# Brainstorm: Communication channel

Oct 5, 2026 · CEO + PM · Status: Open

How the CEO, the Chief of Staff (CoS) and each project's PM talk to each other, including the daily report. This is the last open question in the [product brief](../product-brief.md).

**How to use this doc:** each question below has my recommendation. Write your answer under **CEO:**, the same way you did in the brief. Leave it blank to accept my recommendation. When you're done, I'll fold the results into the brief.

## Starting proposal

Everything goes through GitHub and Markdown files. Nothing reaches into a live agent session.

```mermaid
sequenceDiagram
    autonumber
    participant PM as PM (container)
    participant GH as GitHub (project repo)
    participant CoS as Chief of Staff (host)
    participant HQ as HQ repo (Markdown)
    actor CEO

    PM->>GH: Post status: shipped, ready to merge, blocked, questions for the CEO
    Note over CoS: Daily, on a host schedule
    CoS->>GH: Read each project's latest status, plus PRs and checks
    CoS->>HQ: Write the daily report (reports/YYYY-MM-DD.md)
    CEO->>HQ: Read the report in MDViewer, write answers inline
    CoS->>GH: Post each answer on the issue it belongs to
    GH->>PM: On its next run, the PM reads the answer and continues
```

## A correction to my earlier claim

I said this design means the host never touches a container. That's only half true. Someone still has to **start** the PM so it can write its status and read your answers. The difference is:

- **One-shot headless runs** (the host runs one command in the container, and the PM does one task and exits). This is easy, and both `apple/container` and LXC can do it.
- **Live, interactive sessions** that the host has to broker. This is the hard part, and the proposal still avoids it.

That leads to the most important question in this brainstorm (Q1).

## Questions

### Q1. What keeps the agents working when nobody is talking to them?

"Autonomous" needs something to start the PM, Coder and reviewers when there's work to do. Today the brief doesn't say what that is.

| Option | How it works | Trade-off |
| --- | --- | --- |
| **A. Supervisor in each container** (recommended) | A small script in the container checks GitHub for changes (new comment, PR ready, check failed), with backoff, and starts the right role headless when something changed | Simple and portable. Idle checks cost only GitHub API calls, not tokens. It is a light heartbeat, so the non-goal would need rewording |
| B. Host schedules everything | The host script starts each role in each container on a timer | Puts all control in one place, but the host has to know every role's state |
| C. GitHub Actions trigger runs | Webhooks or Actions start agents on events | Fastest reaction, but agents would run on GitHub's runners instead of in your containers |

**PM recommendation:** A. Change the non-goal to "no always-on LLM sessions". A supervisor that polls GitHub is allowed.

**CEO:**

### Q2. Where does each PM post its status?

| Option | Trade-off |
| --- | --- |
| **A. A pinned "Status" issue per project, one comment per update** (recommended) | Keeps the roadmap issue clean, gives you a full history, easy for the CoS to find |
| B. Comments on the roadmap issue | One fewer issue, but status gets mixed with roadmap discussion |
| C. A `STATUS.md` file committed to the repo | Readable in your `main` mount, but every update is a commit, and it needs a PR or a bypass of the gates |

**PM recommendation:** A. Each update uses a fixed template: Shipped, Ready to merge, In progress, Blocked, **Questions for the CEO** (each with an ID such as `Q-3`), and Risks.

**CEO:**

### Q3. When does the PM post a status update?

**PM recommendation:** The PM posts when something changes that you'd care about: a PR is ready to merge, work is blocked, or there's a question for you. If a project's last update is older than 24 hours when the report runs, the host asks that PM for a fresh one with a one-shot run.

**CEO:**

### Q4. Does the CoS trust the PM's status?

**PM recommendation:** Trust but verify. The CoS checks what each PM claims against GitHub before putting it in the report. For example, a PR reported as "ready to merge" must have every required check passing, and "shipped" must match merged PRs. Anything that doesn't match goes in the report as a discrepancy.

**CEO:**

### Q5. How does the daily report reach you?

**PM recommendation:** The CoS writes `reports/YYYY-MM-DD.md` in a **private HQ repo** and commits it. The host opens it in MDViewer at a time you set. It runs on `launchd` on macOS and a `systemd` timer on Linux. The report puts **what needs you first** (merges and questions), then one section per project.

**CEO:**

### Q6. How do you answer, and how do the answers reach the PM?

The answer has to be verifiably **yours**. All agents share one bot identity, so if your answers were posted by the bot, any agent (including a prompt-injected one) could fake a "CEO decision".

| Option | Trade-off |
| --- | --- |
| **A. Answer inline in the report, then the host posts the answers under your GitHub account** (recommended) | Same workflow you used on the brief. A plain script posts your text word for word, not an LLM. PMs treat only comments from your account as decisions |
| B. Tell the CoS in chat, and it posts for you | Convenient, but an LLM is then writing words in your name |
| C. Answer directly on GitHub | Works today with no tooling, but you have to jump between repos |

**PM recommendation:** A as the main path, with C always available. Use B only to draft, and you confirm before anything is posted.

**CEO:**

### Q7. What does the CoS keep in the HQ repo?

**PM recommendation:** A private repo (for example `dpeckham/hq`) with:

- `portfolio.md`: your projects, their priority order and one-line goals. You own this file, and the CoS reads it
- `reports/`: one daily report per day
- `decisions.md`: decisions that cut across projects

**CEO:**

### Q8. What about something urgent between daily reports?

**PM recommendation:** No push notifications in v1. You can ask for an on-demand report from the host script at any time. Notifications (macOS, ntfy, email) come later.

**CEO:**

## Out of scope for this brainstorm

- Which harness runs which role (part of the portability test)
- Report contents beyond the sections listed in Q2 and Q5. We'll refine these once real reports exist
