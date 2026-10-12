# Benchmark: agent file access on macOS, default tools vs fsearch

One machine: M4 Pro, 64 GB, macOS 26.3, internal SSD. File caches warm (repeated runs), which is the best case for
the tree-walking tools. fsearch 0.2 (daemon, no Full Disk Access). Measured October 2026.

The corpus is a real developer folder: `~/Development`, 94 repos, 210 GB, 572k files `rg` would search, including a
24 GB TypeScript monorepo (20k tracked files) and many worktrees and copies of it. The home folder holds 10.2M
entries in all.

## 1. The tools themselves

Each command run 5 times; median wall time, from process start to exit. "Glob" and "Grep" are what Claude Code's
built-in tools run (ripgrep); `find`, `grep -r` and `mdfind` are what agents shell out to.

| Task | Default | Default time | fsearch |
|---|---|---:|---:|
| Find a file by name, in one repo | `rg --files -g` (Glob) | 64 ms | 3.7 ms |
| | `find -name` | 20 s | |
| Find a file by name, across `~/Development` | `rg --files -g` (Glob) | 2.4 s | 6.4 ms |
| | `find -name` | 127 s | |
| Find a file by name, whole home folder | `find -name` | over 300 s (timed out) | 2.9 ms |
| | `mdfind -name` (Spotlight) | 89 ms | |
| Find a file by a misspelled name | `rg --files -g` | finds nothing | 3.7 ms, right file first |
| Files containing an identifier, one repo | `rg -l` (Grep) | 320 ms | 3.8 ms |
| | `grep -rl` | 129 s | |
| Files containing an identifier, `~/Development` | `rg -l` (Grep) | 15.3 s | 3.7 ms |
| Regex over contents, one repo | `rg -l` (Grep) | 500 ms | 9.1 ms |
| Where a symbol is defined, `~/Development` | `rg -n` with a definition regex | 15.0 s | 3.1 ms (`sym:`) |

Coverage: fsearch found the expected file in every case. Its content index leaves out the contents of linked git
worktrees in broad searches (it indexes the main checkout once), so across `~/Development` `rg` listed 42 files for
an identifier and fsearch 7: the other 35 were copies in worktrees, which fsearch does read when a search is scoped
into one.

## 2. Agents doing the work

Headless Claude Code (`claude -p`, Sonnet, hooks off, no other MCP servers) started in `~/Development`, asked to find
files: by name, by a misspelled name, where a function is defined, every file referencing an identifier, three
"which file does X" questions, and one in another repo. 8 tasks, each run twice under four setups:

- **default**: Claude Code's Glob, Grep, Read and read-only Bash (`find`, `rg`, `grep`, `mdfind`, `ls`)
- **fsearch**: only the fsearch MCP tools and Read
- **both**: everything, the model picks
- **both + rule**: everything, plus one line in the system prompt saying to prefer fsearch

| Setup | Median per task | Total, 16 runs | Time in tools | Right answer | Cost | Runs that used fsearch |
|---|---:|---:|---:|---:|---:|---:|
| default | 43.3 s | 1608 s | 715 s | 15/16 | $0.91 | 0/16 |
| fsearch | 11.4 s | 189 s | 9 s | 14/16 | $0.89 | 16/16 |
| both | 32.5 s | 648 s | 474 s | 14/16 | $1.02 | 4/16 |
| both + rule | 10.2 s | 172 s | 7 s | 16/16 | $0.92 | 16/16 |

- The time saved is time spent waiting on tools; tokens and cost barely move.
- **Installing fsearch isn't enough.** With both available the model chose Glob and `find` in 12 of 16 runs (MCP
  tools sit behind tool search; the built-ins are familiar). One line of instruction fixed that, which is why
  `setup.sh --rules` writes it into each agent's global instructions.
- The slowest default run took 727 s: a `find` and `ls` hunt over 210 GB for a file in a small repo.
- Misses: fsearch alone gave a plausible neighbour file twice on one vague "which file decides X" question, since
  grep's results aren't ranked by relevance. With the rule (same tools) it got that question right both times.

## 3. A side experiment: embeddings

We also linked an embedding model into fsearch (EmbeddingGemma 2 on llama.cpp, from
[DigUp](https://github.com/ARahim3/DigUp)) and indexed the monorepo's 18k source files, one vector each: 9 minutes,
14 MB. On 67 questions describing a file without its names, it put the right file first for 36, against 18 for BM25
and none for grep on the question's words. But agents given the same kind of questions, with the repo named, got
12/12 either way: it made them faster (median 11 s vs 14 s with fsearch's plain tools, 15 s with the defaults), not
more accurate, because agents make up for weak ranking by searching again. Not worth a model in the daemon for
this; the plain index is the win.

## Caveats

- One machine, one person's files, small samples (16 runs a setup in part 2). Treat the agent numbers as
  directional; the tool timings are large enough not to need that.
- Warm caches. Cold, after a reboot, the tree walks are slower still; fsearch's index loads from disk.
- fsearch needs a one-time index (53 s for 10.2M entries here, 26 s more for the contents of 491k files) and a
  daemon (about 20-35 MB).
- `bench/micro.py` reproduces part 1 on your own files.
