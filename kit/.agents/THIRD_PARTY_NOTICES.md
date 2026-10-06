# Third-party notices

Parts of the ai-proj-arch kit in `.agents/` are adapted from
[dbaggott/claude-plugins](https://github.com/dbaggott/claude-plugins) by Dan
Baggott and contributors, at commit `9a4c0b72c83ac8307d66338808f32077a923136c`,
licensed under the Apache License, Version 2.0 (full text: `LICENSE.dnbg`).

| Files | Status |
| --- | --- |
| `skills/git-workflow/` | Modified. Changes marked "ai-proj-arch:" |
| `skills/issue-workflow/` | Modified. Changes marked "ai-proj-arch:" |
| `skills/coding-practices/` | Modified. Changes marked "ai-proj-arch:" |
| `skills/velocity-tradeoff/` | Modified. Changes marked "ai-proj-arch:" |
| `skills/aipa-review-round/` | Derived from upstream `skills/reviewer/` |
| `scripts/fetch-tree.sh`, `fetch-pr-state.sh`, `pr-round.sh`, `pr-verdict.sh`, `lib-activity.sh`, `pr-threads.sh`, `pr-sources.sh` | Unmodified (`pr-verdict.sh` only because `pr-round.sh` calls it; its review-based verdict is not used) |

The rest of the kit is part of ai-proj-arch, also licensed under Apache 2.0.
