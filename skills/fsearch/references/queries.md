# fsearch query language

From fsearch's README (github.com/noahdunnagan/fsearch), for the CLI (`fsearch '<query>'`) and the daemon's
`q` field. The MCP tools take the same filters inline.

## Words

- Words are fuzzy and forgive a typo at any letter, two in words of 8+ letters (`mian.rs` finds `main.rs`).
  Several words can spell one name. Accented names match however they were stored.
- `'exact` exact match, `^prefix`, `suffix$`, `!exclude`.

## Filters

| Filter | Meaning |
|---|---|
| `ext:rs` | extension |
| `type:image` | kind of file: `image`, `video`, `audio`, `doc`, `code`, `archive`, `font` |
| `kind:dir` | entry kind: file, dir, link |
| `in:~/Developer` | only under this folder (`.` works in the CLI) |
| `size:>5mb` | size, with `<`, `>`, units |
| `mtime:<7d` | modified within |
| `re:pat` | regex over the name (case-insensitive) |
| `path:pat` | regex over the whole path (case-insensitive) |
| `grep:text` | contents, literal (smart case). One token, or a quoted phrase: `grep:"payment declined"` |
| `regex:pat` | contents, regex within a line, as in ripgrep |
| `sym:name` | where a symbol is defined |
| `limit:50` | how many results |
| `git:modified` | also `staged`, `untracked`, `clean`, `tracked`, `ignored`, `conflict` |
| `src/**/*.{c,h}` | glob the path must match; `!test/` must not |

## Other commands

```
fsearch status            # index size, Full Disk Access, readiness
fsearch install [--login] # copy to ~/.local/bin; --login starts the daemon at login
fsearch mcp               # MCP server on stdio
fsearch stdio             # JSON lines on stdin/stdout
```

## JSON API (socket or `fsearch stdio`)

```json
{"q": "fsearch main", "limit": 20, "offset": 20}
{"op": "grep", "pattern": "apply_dir", "in": "~/Developer", "context": 2}
{"q": "main.rs", "boost": true, "near": "~/Developer/app/src/lib.rs", "git": true}
{"op": "recent", "in": "~/Developer/app"}
```

The socket is `~/Library/Application Support/FSearch/fsearch.sock`.
