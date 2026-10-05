# ai-proj-arch

A lightweight, portable agent suite for solopreneurs who run AI-first projects.

Instead of vibe coding, the founder (as CEO) works with a **Product Manager** for each project. v1 covers a single project; a Chief of Staff across projects comes later. A team of agents does the rest: a Lead Engineer, a QA Lead, a UX/UI Designer and a Coder plan, build, verify and review the work through GitHub. Each project lives in its own repo and runs in its own container.

**Status:** early. Project containers, the `start`/`shell` helpers and the token broker work on `apple/container`. Provisioning, role skills, gates and the work loop are next (see the roadmap).

## Design goals

- **Portable:** roles are defined as skills, slash commands and tools that run on both Claude Code and Codex
- **Minimal orchestration:** a single host script, with no server or dashboard
- **GitHub as the system of record:** issues hold the roadmap, epics and stories; PRs carry review; Actions and branch protection enforce the gates
- **No verification plan, no start:** QA defines how a story will be verified before any code is written
- **Only the human merges**

## Try it

Run a project in its own container, then talk to it through tmux:

```bash
bin/aipa create <project> --repo <owner>/<name>
bin/aipa shell <project>
```

See [docs/container.md](docs/container.md) for setup (the bot App and harness credentials) and the security model.

## Docs

- [Roadmap](https://github.com/dpeckham/ai-proj-arch/issues/7): v1 epics in order
- [Product brief](docs/product-brief.md): problem, roles, core loop, architecture, v1 scope, risks and decisions
- [Brainstorms](docs/brainstorms/): design discussions between the CEO and the PM (v1 session model, provisioning; the control plane is tabled)

## Prior art

- [Paperclip](https://github.com/paperclipai/paperclip): orchestration for teams of agents, with an org chart and governance
- [dbaggott/claude-plugins](https://github.com/dbaggott/claude-plugins): a GitHub workflow for Claude Code built on worktrees, draft PRs and an independent bot reviewer. **We reuse as much of it as we can**, adapted to also run on Codex

## License

[Apache License 2.0](LICENSE). See [NOTICE](NOTICE) for attribution of adapted work.
