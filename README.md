# ai-proj-arch

A lightweight, portable agent suite for solopreneurs who run AI-first projects.

Instead of vibe coding, the founder (as CEO) works with a **Product Manager** for each project. v1 covers a single project; a Chief of Staff across projects comes later. A team of agents does the rest: a Lead Engineer, a QA Lead, a UX/UI Designer and a Coder plan, build, verify and review the work through GitHub. Each project lives in its own repo and runs in its own container.

**Status:** product definition. No code yet.

## Design goals

- **Portable:** roles are defined as skills, slash commands and tools that run on both Claude Code and Codex
- **Minimal orchestration:** a single host script, with no server or dashboard
- **GitHub as the system of record:** issues hold the roadmap, epics and stories; PRs carry review; Actions and branch protection enforce the gates
- **No verification plan, no start:** QA defines how a story will be verified before any code is written
- **Only the human merges**

## Docs

- [Roadmap](https://github.com/dpeckham/ai-proj-arch/issues/7): v1 epics in order
- [Product brief](docs/product-brief.md): problem, roles, core loop, architecture, v1 scope, risks and decisions
- [Brainstorms](docs/brainstorms/): design discussions between the CEO and the PM (v1 session model, provisioning; the control plane is tabled)

## Prior art

- [Paperclip](https://github.com/paperclipai/paperclip): orchestration for teams of agents, with an org chart and governance
- [dbaggott/claude-plugins](https://github.com/dbaggott/claude-plugins): a GitHub workflow for Claude Code built on worktrees, draft PRs and an independent bot reviewer. **We reuse as much of it as we can**, adapted to also run on Codex

## License

[Apache License 2.0](LICENSE). See [NOTICE](NOTICE) for attribution of adapted work.
