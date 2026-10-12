#!/bin/bash
# Sets up fsearch (github.com/noahdunnagan/fsearch) for the coding agents on this Mac:
#   1. installs fsearch into ~/.local/bin from its latest GitHub release (checksum verified), unless it's there
#   2. registers `fsearch mcp` with each agent found: Claude Code, Codex, Cursor, OpenCode
#   3. with --rules, adds a short rule to each agent's global instructions telling it to prefer the fsearch tools
# Each step is skipped when already done. --dry-run prints what would change and changes nothing.
#
#   setup.sh [--dry-run] [--rules] [--no-install]
set -euo pipefail

DRY=0 RULES=0 INSTALL=1
for a in "$@"; do
  case $a in
    --dry-run) DRY=1 ;;
    --rules) RULES=1 ;;
    --no-install) INSTALL=0 ;;
    -h|--help) sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option $a" >&2; exit 2 ;;
  esac
done

BIN="$HOME/.local/bin/fsearch"
REPO=noahdunnagan/fsearch
ASSET=fsearch-aarch64-apple-darwin.tar.gz
MARK="fsearch-agent-rule"

say() { printf '%s\n' "$*"; }
run() { if [[ $DRY == 1 ]]; then say "  would run: $*"; else "$@"; fi; }

if [[ $(uname -s) != Darwin ]]; then say "fsearch is macOS only"; exit 1; fi

# 1. fsearch itself
if [[ -x $BIN ]]; then
  say "fsearch: installed at $BIN"
elif command -v fsearch >/dev/null; then
  BIN=$(command -v fsearch)
  say "fsearch: installed at $BIN"
elif [[ $INSTALL == 0 ]]; then
  say "fsearch: not installed (skipped: --no-install)"
  exit 1
elif [[ $(uname -m) != arm64 ]]; then
  say "fsearch: release builds are Apple Silicon only; on Intel, build it: git clone https://github.com/$REPO && cd fsearch && cargo build --release && ./target/release/fsearch install"
  exit 1
else
  say "fsearch: installing the latest release of $REPO"
  if [[ $DRY == 0 ]]; then
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT
    base="https://github.com/$REPO/releases/latest/download"
    curl -fsSL -o "$tmp/$ASSET" "$base/$ASSET"
    curl -fsSL -o "$tmp/$ASSET.sha256" "$base/$ASSET.sha256"
    want=$(awk '{print $1}' "$tmp/$ASSET.sha256")
    have=$(shasum -a 256 "$tmp/$ASSET" | awk '{print $1}')
    if [[ $want != "$have" ]]; then say "checksum mismatch: expected $want, got $have"; exit 1; fi
    tar -xzf "$tmp/$ASSET" -C "$tmp"
    "$tmp/fsearch" install
  else
    say "  would download $ASSET, check its sha256, and run fsearch install"
  fi
fi

# 2. MCP registration
json_add() { # file, python snippet editing `d` (a dict)
  local file=$1 code=$2
  run python3 - "$file" "$code" <<'EOF'
import json, os, sys
path, code = sys.argv[1], sys.argv[2]
try:
    d = json.load(open(path)) if os.path.exists(path) and os.path.getsize(path) else {}
except ValueError:
    print(f"  can't parse {path} (comments?): add the fsearch server to it by hand: {code.split('=', 1)[1].strip()}")
    sys.exit(0)
exec(code)
os.makedirs(os.path.dirname(path), exist_ok=True)
tmp = path + ".tmp"
json.dump(d, open(tmp, "w"), indent=2)
open(tmp, "a").write("\n")
os.replace(tmp, path)
EOF
}

if command -v claude >/dev/null; then
  if claude mcp get fsearch >/dev/null 2>&1; then say "Claude Code: fsearch MCP already registered"
  else say "Claude Code: registering fsearch MCP (user scope)"; run claude mcp add -s user fsearch -- "$BIN" mcp; fi
fi
if command -v codex >/dev/null; then
  if codex mcp get fsearch >/dev/null 2>&1; then say "Codex: fsearch MCP already registered"
  else say "Codex: registering fsearch MCP"; run codex mcp add fsearch -- "$BIN" mcp; fi
fi
if [[ -d $HOME/.cursor ]]; then
  f=$HOME/.cursor/mcp.json
  if [[ -f $f ]] && grep -q '"fsearch"' "$f"; then say "Cursor: fsearch MCP already in $f"
  else say "Cursor: adding fsearch MCP to $f"; json_add "$f" "d.setdefault('mcpServers', {})['fsearch'] = {'command': '$BIN', 'args': ['mcp']}"; fi
fi
f=$HOME/.config/opencode/opencode.json
if [[ -f $f ]] || command -v opencode >/dev/null; then
  if [[ -f $f ]] && grep -q '"fsearch"' "$f"; then say "OpenCode: fsearch MCP already in $f"
  else say "OpenCode: adding fsearch MCP to $f"; json_add "$f" "d.setdefault('mcp', {})['fsearch'] = {'type': 'local', 'command': ['$BIN', 'mcp'], 'enabled': True}"; fi
fi

# 3. The rule. Agents keep reaching for their built-in Glob/Grep/find unless told: in testing, fsearch got used in
# 4 of 16 runs without it and 16 of 16 with it.
RULE="<!-- $MARK -->
## File search

To find files or search their contents, use the fsearch MCP tools (find_files, grep, multi_grep), or the
\`fsearch\` CLI when they aren't loaded: they're indexed across the whole disk and answer in milliseconds. Don't use
Glob, Grep, find or rg for that; they walk the tree on every call. Fall back to rg only for what fsearch leaves out
(git-ignored files, build output, big JSON or lockfiles), or when it says it's still indexing.
<!-- /$MARK -->"

if [[ $RULES == 1 ]]; then
  for f in "$HOME/.claude/CLAUDE.md" "$HOME/.codex/AGENTS.md" "$HOME/.config/opencode/AGENTS.md"; do
    agent_dir=$(dirname "$f")
    [[ -d $agent_dir ]] || continue
    if [[ -f $f ]] && grep -q "$MARK" "$f"; then say "rule: already in $f"; continue; fi
    if [[ -f $f ]] && grep -qi "fsearch" "$f"; then say "rule: $f already mentions fsearch; left alone"; continue; fi
    say "rule: adding to $f"
    if [[ $DRY == 0 ]]; then
      { [[ -s $f ]] && printf '\n'; printf '%s\n' "$RULE"; } >> "$f"
    fi
  done
  [[ -d $HOME/.cursor ]] && say "rule: Cursor keeps global rules in its settings (Rules > User Rules): paste the rule there by hand"
else
  say "rule: skipped (add --rules to tell agents to prefer fsearch: without it they mostly don't)"
fi

say ""
say "Done. The first search starts the daemon, which indexes the disk once (about a minute)."
say "For protected folders (Mail, Messages, …), grant Full Disk Access to $BIN in System Settings > Privacy & Security."
