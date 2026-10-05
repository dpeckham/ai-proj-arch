# Spike: Portability (#1)

Oct 5, 2026 · Status: **Done, pending two CEO settings changes** (see Bot identity → Open items).

Tracks [#1](https://github.com/dpeckham/ai-proj-arch/issues/1). Each result is **Pass**, **Fail**, or **Pass with a workaround**, with the commands used.

## Environment

| Item | Version |
| --- | --- |
| Host | macOS 27 (Darwin 27.0.0), Apple silicon |
| `apple/container` | 1.5.0 |
| Image | `docker.io/library/debian:stable-slim` (arm64) |
| tmux, git (container) | 3.5a, 2.47.3 |
| Claude Code (container) | 2.1.289, official installer, as a non-root `agent` user |
| Codex (container) | 0.160.1, the full `codex-package-aarch64-unknown-linux-musl` from GitHub releases, plus Debian's `bubblewrap` |

**Setup note:** on first use, `container system start` asks to install a default kernel, which fails in a non-interactive shell. Run `container system start --enable-kernel-install`. Provisioning (#3) should check this and print that command.

## Container

| # | Question | Result |
| --- | --- | --- |
| C1 | The container stays running with nobody attached | **Pass.** Its main process is `sleep infinity`. The real image (#2) should use a proper init, such as `tini`, so signals and zombie processes are handled |
| C2 | A tmux session survives the terminal being closed, and you can reattach to it | **Pass.** The test opened a session through `container exec -it`, then killed the exec client with `kill -9`, with no tmux detach first. The session was still listed and a new `container exec -it … tmux attach -t pm` reattached. The killed client stays listed as "(attached)", so `shell` should use `tmux new-session -A -D -s pm` to drop stale clients |
| C3 | A background process keeps running after the terminal is closed | **Pass.** A `nohup` loop started inside the session kept writing a heartbeat file (8, then 12 lines, 4 seconds apart) after the client was killed |
| C4 | The bind mount works in both directions | **Pass.** Host to container and container to host both work. Files created by root in the container appear on the host owned by the host user (uid 501) |
| C5 | Worktrees must not live in the mounted checkout | **Confirmed, and the design changes.** See below |
| C6 | Container state survives a stop and start | **Pass for files, as expected for processes.** Files in the container (for example `~/.local/bin`, `~/persist.txt`) survive `container stop` and `container start`. tmux and background processes don't, so the PM session and the work loop must be restarted after a start. The work loop is restartable by design |

### C5: worktrees and the mounted checkout

**Test A:** create a worktree inside the container from the mounted `main` checkout.

```text
$ git worktree add /root/wt-a -b spike-a        # in the container, from /work/main/repo
host$ git worktree list
…/mount/repo  f07e174 [main]
/root/wt-a    f07e174 [spike-a] prunable
host$ git worktree prune -n -v
Removing worktrees/wt-a: gitdir file points to non-existent location
```

The worktree's metadata lives in the mounted `.git`, pointing at a container path the host can't see. Any `git worktree prune`, or the automatic prune in `git gc`, run on the host would **delete the container's worktree metadata**.

**Test B:** the container keeps its own clone on container storage and creates worktrees from that. The mounted checkout is a separate, plain clone.

```text
$ git clone /work/main/repo /root/repo && git -C /root/repo worktree add /root/wt-b -b spike-b
host$ git -C …/mount/repo worktree list
…/mount/repo  f07e174 [main]            # no foreign worktrees
```

**Decision for #2 and #6:** the agents work from their **own clone on container storage**. The bind-mounted directory is a plain `main` checkout that only ever runs `git pull --ff-only` after a merge, and nothing creates worktrees from it.

## Harness authentication

| # | Question | Result |
| --- | --- | --- |
| A1 | Claude Code in the container without copying host credentials | **Pass.** The CEO ran `claude setup-token` on the host and saved the token to `~/.config/ai-proj-arch/spike.env` (folder 700, file 600) with `read -rs`, so it never echoed or reached shell history. It's passed per command with `container exec --env-file`. Nothing is stored in the container or the image. The token is never printed. It's a one-year subscription token that only makes model requests ([docs](https://code.claude.com/docs/en/authentication)) |
| A2 | Codex in the container | **Pass.** `codex login --device-auth` inside the container; `codex login status` reports "Logged in using ChatGPT". Credentials are in `~/.codex/auth.json` on container storage, which survives a stop and start (C6) |
| A3 | Missing auth makes a run fail clearly | **Pass.** Without credentials, `claude -p` and `codex exec` both exit 1 |

## Skills, instructions and subagents

| # | Question | Result |
| --- | --- | --- |
| S1 | Claude Code reads `AGENTS.md` through a `CLAUDE.md` containing only `@AGENTS.md` | **Pass.** It returned the marker that's defined only in `AGENTS.md` |
| S2 | Codex reads `AGENTS.md` | **Pass** |
| S3 | Claude Code finds skills through the `.claude/skills -> ../.agents/skills` symlink | **Pass.** The skill was listed and its content used |
| S4 | Codex finds skills in `.agents/skills/` | **Pass with a workaround.** Codex lists the skill, but with its own sandbox (`read-only` or `workspace-write`) it **can't read files** inside `apple/container`, even though `bwrap` alone works. It answered "filesystem access failed". With `--sandbox danger-full-access` it works. Also, the bare `codex` binary is not enough: install the full `codex-package` (which includes `codex-code-mode-host`) and `bubblewrap` |
| S5 | Subagents on both harnesses | **Pass, with different formats.** Claude Code reads `.claude/agents/<name>.md` (frontmatter plus instructions). Codex reads `.codex/agents/<name>.toml` (`name`, `description`, `developer_instructions`). Both delegated to a `lead-engineer` subagent. **Kit impact:** keep one source per subagent and have provisioning generate both files |

## Headless runs

| # | Question | Result |
| --- | --- | --- |
| H1 | Unattended permissions | **Claude Code:** `--permission-mode bypassPermissions` works as the non-root `agent` user. An allowlist (`--allowedTools`) is **not** a boundary: under `acceptEdits` with only `git status` allowed, Claude still removed a file. **Codex:** `--sandbox danger-full-access` (see S4). **Decision:** inside the container, both harnesses run with full access, and **the container is the security boundary.** It holds only one repo and a short-lived token for that repo |
| H2 | Exit status is trustworthy | **Only for crashes, not for task success.** In `workspace-write` mode Codex replied "Unable to create cx-ws.txt" and **still exited 0**. **Kit impact:** the work loop must never treat exit 0 as "done". It checks the result on GitHub (a PR exists, checks were posted) or in structured output |
| H3 | Getting the result back | **Pass.** Claude Code: `--output-format json` (includes `total_cost_usd`, usage and `session_id`). Codex: `-o <file>` writes the last message, and `--json` streams events, including usage |
| H4 | Gotcha | Claude Code's `--allowedTools` takes several values and swallowed a prompt placed after it. Always put the prompt first |
| H5 | Gotcha | `container exec` looks up executables using the image's `PATH`, not `--env PATH`. Use absolute paths, or set `PATH` in the image |

## Dan's plugins on Codex

| # | Question | Result |
| --- | --- | --- |
| D1 | Do the skills load on Codex unchanged? | **Pass.** All of `coding-practices`, `git-workflow`, `issue-reviewer`, `issue-workflow`, `reviewer`, `reviewer-setup`, `velocity-tradeoff` and `work-summary` were listed. Codex read `git-workflow` and stated its worktree rule correctly. Tested at upstream commit `9a4c0b7` |
| D2 | Do their helper scripts resolve? | **Pass, if we keep the layout.** The skills call `<skill-dir>/../../scripts/…`. Copying upstream `scripts/` to `.agents/scripts/` makes every path resolve unchanged |
| D3 | Claude-only dependencies | A short list, from a grep of the skills: `AskUserQuestion` (5 places; in headless runs the runner pre-answers these in the prompt, as Dan's README describes), `run_in_background` for `watch-pr.sh` (1 place; our work loop does the waiting, so agents don't need to), `${CLAUDE_PLUGIN_ROOT}` (1 place, in `issue-workflow/references/resolving.md`), and `CLAUDE.md` mentions (wording only). The two enforcement hooks don't carry over; #5 replaces them with GitHub gates |
| D4 | Tooling note | Copying files from macOS with `tar` adds `com.apple.provenance` xattr headers that GNU tar warns about. Provisioning should use `COPYFILE_DISABLE=1` or `--no-xattrs` |

## Bot identity

The bot is the existing **`dpeckham-bot`** App (App ID 5186605), named by the convention `<github-username>-bot`. A new private key was generated and is stored at `~/.config/ai-proj-arch/bot/private-key.pem` (folder 700, file 600). The download in `~/Downloads` was deleted. The key never enters a container. A throwaway App created earlier (`aipa-bot-dpeckham`) had its local key deleted. The CEO is deleting the App itself.

| # | Question | Result |
| --- | --- | --- |
| B1 | Mint an installation token on the host from the key | **Pass.** A JWT is signed with `openssl` and exchanged at `/app/installations/<id>/access_tokens`, following Dan's `mint-token.sh`. Tokens are captured into variables and never printed. They expire in 1 hour |
| B2 | Scope a token to one repo | **Pass.** Minting with `{"repositories":["yawnbooks"]}` returns a token for that repo only. With it, a write to `my-ai-org` (in the same installation) gets `403 Resource not accessible by integration`, and so does a write to `ai-proj-arch` (not installed). Reads of **public** repos still work, as they do for anyone |
| B3 | Deliver the token to the container without the key | **Pass.** The host writes the token to a file in a folder that's 700 on the host. Inside the container the file appears owned by `agent` (uid 1000) and is readable. A `:ro` bind mount is enforced: a write from the container fails with "Read-only file system" |
| B4 | `git` and `gh` act as the bot | **Pass.** A credential helper reads the token file **on every call**, so a refreshed file takes effect without restarting anything. Clone, push of a test branch, `gh api` and `gh pr list` all worked as `dpeckham-bot[bot]`. The test branch was deleted |
| B5 | Commit author shows the bot | Use the email `337727585+dpeckham-bot[bot]@users.noreply.github.com`. The number is the bot's **user** ID (`gh api 'users/dpeckham-bot[bot]' --jq .id`), not the App ID. Provisioning should look it up |
| B6 | Agents can't change workflows | **Pass, and it's a gate.** Pushing a commit that adds `.github/workflows/x.yml` was rejected: "refusing to allow a GitHub App to create or update workflow … without `workflows` permission". **Consequence:** agents can't add or change CI. They propose workflow changes in a PR description or issue, and the CEO (or provisioning, which runs as the CEO) commits them |

**Token broker (design confirmed by B3 and B4, built in #2):** a host process started by `start` mints a repo-scoped token about every 45 minutes and atomically replaces the file in the read-only mount. Containers never hold the key.

**Open items for the CEO**
- [ ] `dpeckham-bot` has **Checks: read**. Reviewer roles need **Checks: write** to post `review/qa`, `review/eng` and `review/ux`. Change it in the App's permissions, then accept the request on the installation
- [ ] The installation covers `yawnbooks` and `my-ai-org`, but not `ai-proj-arch`. Add `ai-proj-arch` if agents will work on this repo too
- [ ] The App also has read access to security events and vulnerability alerts, which Paperclip used. That's harmless and useful for the OSV audit work. Keep it or remove it

## Summary for #4 and #6

1. Agents work from their own clone on container storage. The mounted `main` is a plain checkout that only fast-forwards (C5)
2. Both harnesses run with full access **inside** the container. The container, holding one repo and a token for that repo only, is the boundary (S4, H1)
3. Never trust exit 0. Check the outcome on GitHub (H2)
4. Subagents need two generated formats, `.claude/agents/*.md` and `.codex/agents/*.toml` (S5)
5. Copy upstream `scripts/` to `.agents/scripts/` so Dan's skills work unchanged (D2). Pre-answer `AskUserQuestion` decisions in runner prompts (D3)
6. Codex needs its full package plus `bubblewrap`. Use absolute paths with `container exec` (S4, H5)
7. Tokens are scoped to one repo, delivered through a read-only file, and refreshed by a host broker. Agents can't touch workflows (B2–B6)
