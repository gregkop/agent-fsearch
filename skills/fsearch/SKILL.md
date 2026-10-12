---
name: fsearch
description: Fast indexed file search for coding agents on macOS, through fsearch (names in ~0.1 ms, typo-tolerant, indexed content grep, symbol definitions, git status). Use it whenever you need to find a file, see where something is defined or used, grep a codebase, or look across many repos or the whole disk on a Mac, and especially when Glob, Grep, find or rg are slow (big monorepos, a folder of many repos, a home directory). Also use it to set fsearch up for Claude Code, Codex, Cursor or OpenCode, or when the user asks why file search is slow on macOS.
---

# fsearch for agents

fsearch keeps a live index of every file on the Mac (names, plus the contents of text files) in a small daemon, so
a search is a lookup instead of a walk of the tree. On a 210 GB folder of 94 repos, finding a file by name took
2.4 s with `rg --files` and 127 s with `find`, and 6 ms with fsearch; a content grep took 15 s with `rg` and 4 ms
with fsearch. In headless Claude Code sessions doing locate tasks, the median task went from 43 s to 10 s at the
same cost. See the repo's BENCHMARK.md for the numbers and how they were measured.

## Which interface you have

1. **MCP tools** (best): `find_files`, `grep`, `multi_grep` from an `fsearch` MCP server (in Claude Code they appear
   as `mcp__fsearch__find_files` and so on, possibly behind tool search). Use them for every name or content search.
2. **CLI**: `fsearch` on PATH (`~/.local/bin/fsearch`). Use it through the shell; it prints one path, or one
   `path:line: text` match, per line.
3. **Neither**: fsearch isn't installed. Tell the user what it is and offer `scripts/setup.sh` (below); don't
   install it unasked, since it puts a daemon on their machine. Meanwhile, use the usual tools.

Check with `command -v fsearch` if you're unsure.

## Using the MCP tools

- `find_files` with `query`: file names, fuzzy and typo-tolerant over the whole path. All words must match.
  Inline filters: `*.ts`, `src/`, `src/**/*.rs`, `!test/`, `git:modified`. A lone `name/` finds folders. An empty
  query lists files changed in git, then ones worked on lately.
- `grep` with `query`: file contents. Give a bare identifier or a literal piece of one line, not code syntax.
  Regexes are detected (`\b`, `.*`, `a|b`) or forced with `regex: true`. Smart case. Prefix filters go first:
  `'*.ts !test/ createInvoice'`, or a file name to search one file (`'main.rs parse'`). Definitions come first.
- `multi_grep` with `patterns`: several literal spellings at once (`['prepareUpload', 'prepare_upload']`), OR'd.
- `path`: the folder to search. Relative to the project, absolute, or `"/"` for the whole disk. Default: the
  project.

Results come best first. Read the top file instead of searching again with small variations.

## Using the CLI

```
fsearch 'invoice totals'                    # names: all words, fuzzy
fsearch 'subtractIntervls in:~/Development' # typos forgiven; in: scopes to a folder
fsearch 'grep:calculateTotals in:.'         # contents (indexed), here and below
fsearch 'grep:"payment declined" in:.'      # a phrase: quote it
fsearch 'regex:fn\s+\w+_dir ext:rs'         # regex over contents
fsearch 'sym:createAttemptPolicy'           # where it's defined
fsearch 'type:image size:>5mb mtime:<7d'    # metadata
fsearch 'git:modified in:~/Developer/app'   # git status
fsearch 'src/**/*.{c,h} !test/ init'        # globs, in or out
```

`grep:` takes one token, or a quoted phrase: other words still filter file *names*, so `grep:fn parse` means
"files named like parse that contain fn". Without `in:` a search covers the whole disk; `in:.` is the current
folder. Add `--json` for machine-readable hits (path, kind, size, mtime, score, git status). The first search after
install starts the daemon, which lists the disk once (about a minute for 10M files); searches made meanwhile wait
or say so. For the full query language, read `references/queries.md`.

## What it doesn't see, and when to fall back

fsearch's content index is ripgrep's file set, minus a few things. When a search comes back empty but you expect
a match, check whether the file is one of these before concluding it doesn't exist, and fall back to `rg` for it:

- Files git ignores, build output outside repos, lockfiles, minified bundles, JSON of 100 KB and up, and text over
  1 MB (10 MB inside git repos). Names are always indexed: `find_files` still finds them.
- **Linked git worktrees** in broad searches: a folder holding a repo and its worktrees indexes the main checkout
  once. Searches scoped *into* a worktree (`path` or `in:` pointing inside it) read it directly. So when you work in
  a worktree, scope to it.
- **Protected folders** (Mail, Messages, Safari and so on) when fsearch has no Full Disk Access. They're skipped,
  never prompted for.

Grep results aren't ranked by relevance to a vague question: a search for common words matches thousands of files
in no useful order. For "where do we handle X?" questions, search the most distinctive identifier or phrase you
can think of, try its spellings with `multi_grep`, or find likely names with `find_files` first.

## Setting it up for a user

`scripts/setup.sh` (macOS on Apple Silicon) does three things, each skipped if already done:

1. Installs fsearch from its GitHub releases into `~/.local/bin`.
2. Registers `fsearch mcp` with each agent it finds: Claude Code, Codex, Cursor and OpenCode.
3. With `--rules`, adds a short rule to each agent's global instructions (`~/.claude/CLAUDE.md`,
   `~/.codex/AGENTS.md`, `~/.config/opencode/AGENTS.md`), telling the agent to prefer the fsearch tools.

The rule matters. In testing, with fsearch merely available beside the built-in tools, the model reached for Glob
and `find` in 12 of 16 runs, because MCP tools sit behind tool search and the built-ins are familiar. With the rule
it used fsearch every time and finished fastest. Run `scripts/setup.sh --dry-run` first to show the user what
will change, and get their go-ahead before running it for real.

Afterwards, mention Full Disk Access: to index protected folders, grant it to `~/.local/bin/fsearch` in System
Settings > Privacy & Security, and run `fsearch install --login` to start the daemon at login.
