"""Times the commands behind an agent's default file tools against fsearch, on your own files.

  python3 bench/micro.py --repo ~/code/big-repo --root ~/code \\
      --name someFile.ts --ident someIdentifier --symbol someFunction [--runs 5] [--slow]

--name: a file name that exists in the repo; --ident: an identifier in some file's contents; --symbol: a function or
class defined somewhere under --root. --slow adds find, grep -r and a whole-home find (minutes each, capped at 300 s).
Prints one line per command: first-run and median wall time, and whether the output named a file that has --name in
it (for name searches) or any output at all (for content searches).
"""
import argparse, os, shutil, statistics, subprocess, time

p = argparse.ArgumentParser()
p.add_argument("--repo", required=True)
p.add_argument("--root", required=True)
p.add_argument("--name", required=True)
p.add_argument("--ident", required=True)
p.add_argument("--symbol", required=True)
p.add_argument("--runs", type=int, default=5)
p.add_argument("--slow", action="store_true")
a = p.parse_args()
R, D, H = (os.path.realpath(os.path.expanduser(x)) for x in (a.repo, a.root, "~"))
FS = shutil.which("fsearch") or os.path.expanduser("~/.local/bin/fsearch")
stem, ext = os.path.splitext(a.name)
typo = (stem[:-2] + stem[-1] if len(stem) > 4 else stem) + ext

cases = [
    ("name, repo", a.name, [("rg --files -g", ["rg", "--files", "-g", f"**/{a.name}", R]), ("fsearch", [FS, f"{a.name} in:{R}"])]
     + ([("find -name", ["find", R, "-name", a.name])] if a.slow else [])),
    ("name, root", a.name, [("rg --files -g", ["rg", "--files", "-g", f"**/{a.name}", D]), ("fsearch", [FS, f"{a.name} in:{D}"])]
     + ([("find -name", ["find", D, "-name", a.name])] if a.slow else [])),
    ("name, home", a.name, [("mdfind -name", ["mdfind", "-onlyin", H, "-name", a.name]), ("fsearch", [FS, f"{a.name} in:{H}"])]
     + ([("find -name", ["find", H, "-name", a.name])] if a.slow else [])),
    ("typo name, root", a.name, [("rg --files -g", ["rg", "--files", "-g", f"**/{typo}", D]), ("fsearch", [FS, f"{typo} in:{D}"])]),
    ("contents, repo", None, [("rg -l", ["rg", "-l", a.ident, R]), ("fsearch", [FS, f"grep:{a.ident} in:{R}"])]
     + ([("grep -rl", ["grep", "-rl", "--exclude-dir=node_modules", "--exclude-dir=.git", a.ident, R])] if a.slow else [])),
    ("contents, root", None, [("rg -l", ["rg", "-l", a.ident, D]), ("fsearch", [FS, f"grep:{a.ident} in:{D}"])]),
    ("definition, root", None, [("rg -n def regex", ["rg", "-n", rf"(function|const|class|def|fn|func)\s+{a.symbol}\b", D]),
                                ("fsearch sym:", [FS, f"sym:{a.symbol} in:{D}"])]),
]


def run(argv):
    t = time.perf_counter()
    try:
        out = subprocess.run(argv, capture_output=True, text=True, timeout=300).stdout
    except subprocess.TimeoutExpired:
        return 300_000.0, ""
    return (time.perf_counter() - t) * 1000, out


print(f"{'case':18} {'command':16} {'first':>10} {'median':>10}  found")
for case, expect, tools in cases:
    for tool, argv in tools:
        times, found = [], False
        for i in range(a.runs):
            ms, out = run(argv)
            times.append(ms)
            if i == 0:
                found = (expect in out) if expect else bool(out.strip())
            if ms >= 300_000:
                break
        print(f"{case:18} {tool:16} {times[0]:8.1f}ms {statistics.median(times):8.1f}ms  {found}")
