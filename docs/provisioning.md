# Provisioning

One command sets up a project, or updates it to the kit version you're running ([#3](https://github.com/dpeckham/ai-proj-arch/issues/3)). It's idempotent: run it again any time, and with nothing to change it changes nothing.

```bash
bin/aipa provision <project> --repo <owner>/<name>     # first time
bin/aipa provision <project>                            # later: the repo is remembered
bin/aipa provision <project> --dry-run                  # show what it would do
```

Options:
- `--main-dir <dir>`: the host checkout of `main` (default `~/aipa/<project>`)
- `--check <ci-job>`: an extra required check, repeatable
- `--no-update-check`: skip the release check

Run it on your Mac as yourself. It needs admin on the repo, and the bot never gets admin. It uses `bash`, `git` and `gh`, plus `jq`, `openssl` and `curl`, which ship with macOS, for the bot token. Git authenticates through `gh`, never the macOS keychain.

## What it does, in order

| Step | What it checks, then does |
| --- | --- |
| **Release check** | Is there a newer ai-proj-arch release than the tag you're on? If so, it asks, switches this checkout to the release tag, and restarts on the new version. It never switches without a terminal, in a dry run, with local changes, or to anything but a release tag from `origin`. On a development checkout it just names the latest release |
| **Preflight** | `gh` is logged in. The container runtime is running. The bot App's key exists and is private. You're an admin on the repo. The bot App is installed on it (if not, it prints where to add it). The account can enforce rulesets: private repos need GitHub Pro, and it stops if they can't be enforced |
| **Kit files** | Renders the kit (skills, scripts, subagents for both harnesses, templates, the `AGENTS.md` block, `CLAUDE.md`, the gate workflow) and applies it to a fresh clone using the manifest (below). On a **first install** to a repo without the gates, it commits straight to the default branch. Otherwise it opens or updates a PR titled "Update the ai-proj-arch kit to <version>" |
| **Gates** | Labels and the two rulesets (`gates/apply.sh`) |
| **Status branch** | Creates `status` with a starter `STATUS.md` if it's missing |
| **Host and container** | `aipa create`: the project config, the host checkout of `main`, the image for this kit version, the home volume and the container. If the container is from an older image, it asks before recreating it. The home volume is kept |

## The manifest and your edits

`.ai-proj-arch/manifest.txt` records the kit version and the SHA-256 of every kit-owned file **as the kit shipped it**. On an update:

| The file in your repo | The kit's version | What happens |
| --- | --- | --- |
| Matches what the kit last shipped | Changed | Updated |
| Edited by you | Unchanged | Left alone, silently |
| Edited by you | Changed | **Asks:** keep yours (default), overwrite, show the diff, or save the kit's version beside it as `<file>.kit-new`. With no terminal, or in a dry run, it keeps yours. Every choice is listed in the update PR |
| Dropped from the kit | — | Removed if untouched, left in place if edited |

The kit block in `AGENTS.md` follows the same rules. Everything outside it is yours. `.ai-proj-arch/project.toml` (which harness runs each role, the round cap) is created once and never overwritten.

## Kit update PRs

A kit update PR is opened by you, as the CEO, so no agent writes the gate files. But "protect main" still requires `review/qa`, `review/eng` and `review/ux`. So provisioning posts all three as **neutral** checks from the bot, titled "Kit update: not an agent review": they satisfy the required checks without pretending anyone reviewed it. You read the diff and merge it, with the bypass, like any other PR.

## Verified (Oct 6, 2026)

| Repo | Result |
| --- | --- |
| `dpeckham/aipa-sandbox` (kit installed earlier without a manifest, gates on) | Opened kit update PR #18. Only the manifest was new, and an outdated skill file was reported as a local edit and kept. The gate passed, the neutral checks satisfied the required checks, and the CEO merged it. A second run reported "already installed, nothing to change" |
| `dpeckham/yawnbooks` (first install, no gates) | Dry run first. Then: kit committed to `main`, both rulesets created, the `status` branch created. The container was found to be outdated and recreated with its home volume kept. The e2e check passed 11 of 11, and the work loop reported `idle` (no stories yet) |

Unit tests: `tests/provision.bats` covers the first install, idempotency, the update rules for edited, untouched and dropped files and the `AGENTS.md` block, the settings file, and the release check.
