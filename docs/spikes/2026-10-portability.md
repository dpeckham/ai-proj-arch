# Spike: Portability (#1)

Oct 5, 2026 · Status: **In progress**. The container section is done. Authentication, skills, headless runs and the bot token are still to test.

Tracks [#1](https://github.com/dpeckham/ai-proj-arch/issues/1). Each result is **Pass**, **Fail**, or **Pass with a workaround**, with the commands used.

## Environment

| Item | Version |
| --- | --- |
| Host | macOS 27 (Darwin 27.0.0), Apple silicon |
| `apple/container` | 1.5.0 |
| Image | `docker.io/library/debian:stable-slim` (arm64) |
| tmux, git (container) | 3.5a, 2.47.3 |
| Claude Code (container) | 2.1.289, official installer, as a non-root `agent` user |
| Codex (container) | 0.160.1, `codex-aarch64-unknown-linux-musl` from GitHub releases |

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

## Harness authentication (to test next, needs the CEO)

Researched in the official docs. Not yet tested in the container.

| Harness | Proposed method | Notes |
| --- | --- | --- |
| Claude Code | Run `claude setup-token` **on the host**, then pass the token into the container as `CLAUDE_CODE_OAUTH_TOKEN` | A one-year token that uses your subscription (Pro, Max, Team or Enterprise) and only makes model requests. Not read in `--bare` mode. ([docs](https://code.claude.com/docs/en/authentication)) |
| Codex | `codex login --device-auth` **inside the container** | Device-code sign-in, with no browser needed in the container. Credentials go to `$CODEX_HOME/auth.json` on container storage, which survives a stop and start (C6). An API key is the alternative (`codex login --with-api-key`, or `CODEX_API_KEY`) |

**Secret handling to test:** the Claude token lives in a host file outside any repo (for example `~/.config/ai-proj-arch/<project>.env`, mode 600) and is passed with `container exec --env-file`. It must never be printed into a transcript, committed, or baked into an image.

## Still to test

- [ ] Authentication for both harnesses (above)
- [ ] Skills: Claude Code through the `.claude/skills` symlink, Codex through `.agents/skills`, and `CLAUDE.md` importing `AGENTS.md`
- [ ] Subagents on both harnesses
- [ ] Headless runs: `claude -p` and `codex exec` exit statuses, flags for unattended use, and how the result is returned
- [ ] Bot identity: `reviewer-setup` and `mint-token.sh` from dbaggott/claude-plugins, minting tokens on the host, and refreshing them before the roughly one-hour expiry
- [ ] Dan's skills on Codex
