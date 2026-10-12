# fsearch for coding agents

A skill that gives Claude Code, Codex, Cursor and OpenCode fast file search on macOS through
[fsearch](https://github.com/noahdunnagan/fsearch), Noah Dunnagan's indexed whole-disk search, instead of walking
the tree with Glob, Grep, `find` and `rg` on every call.

On a 210 GB folder of 94 repos:

| | default tools | fsearch |
|---|---:|---:|
| find a file by name | 2.4 s (`rg --files`), 127 s (`find`) | 6 ms |
| find it by a misspelled name | nothing | 4 ms |
| files containing an identifier | 15.3 s (`rg`) | 4 ms |
| where a function is defined | 15.0 s (`rg`) | 3 ms |
| **an agent's locate task, median** | **43 s** | **10 s** |

Same answers, same token cost: the time was all spent waiting on tools. On a small repo `rg` is just as fast
(about 9 ms here); the win grows with the tree. [BENCHMARK.md](BENCHMARK.md) has the full
numbers, the method and the caveats.

## Install

```sh
npx skills add gregkop/agent-fsearch          # the skill, for every agent you have
~/.agents/skills/fsearch/scripts/setup.sh --dry-run --rules   # see what setup would change
~/.agents/skills/fsearch/scripts/setup.sh --rules             # then do it
```

`setup.sh` (Apple Silicon):

1. installs fsearch from its latest release into `~/.local/bin`, checking the release's SHA-256;
2. registers `fsearch mcp` with Claude Code, Codex, Cursor and OpenCode, whichever you have;
3. with `--rules`, adds a short rule to each agent's global instructions (`~/.claude/CLAUDE.md`,
   `~/.codex/AGENTS.md`, `~/.config/opencode/AGENTS.md`; Cursor's go in its settings, by hand).

Every step is skipped when it's already done, and the rule sits between markers so it's easy to find and remove.

**Don't skip `--rules`.** With fsearch merely available, agents still reached for their built-in tools in 12 of 16
runs. With the rule they used fsearch every time, and were fastest.

Or skip the skill and do it by hand:

```sh
curl -L https://github.com/noahdunnagan/fsearch/releases/latest/download/fsearch-aarch64-apple-darwin.tar.gz | tar xz && ./fsearch install
claude mcp add -s user fsearch -- ~/.local/bin/fsearch mcp
```

## What the skill teaches

When to use fsearch's `find_files`, `grep` and `multi_grep` (or the `fsearch` CLI) and how to write queries, plus
where it doesn't look, so agents know when to fall back to `rg`: git-ignored files and build output, linked git
worktrees in broad searches (scope into the worktree instead), and protected folders without Full Disk Access.
See [skills/fsearch/SKILL.md](skills/fsearch/SKILL.md).

## Credits

[fsearch](https://github.com/noahdunnagan/fsearch) by Noah Dunnagan (MIT) does the work; this repo only packages it
for agents and measures it. The embedding side experiment in BENCHMARK.md used [DigUp](https://github.com/ARahim3/DigUp)'s
model and llama.cpp build.

MIT
