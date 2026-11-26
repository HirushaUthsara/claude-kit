"""Section-level retrieval over the Obsidian vault. Stdlib only, built for hooks (fast, tiny output).

  vault.py find <words...> [-n N] [-p PROJECT]   ranked pointers, no content
  vault.py get <note> [heading]                  one section (no heading: outline with line ranges)
  vault.py session                               SessionStart hook: index of the cwd's project
  vault.py hook                                  UserPromptSubmit hook: <=5 pointers if a strong match
  vault.py log <note> <text>                     append a dated line under '## Updates', bump `updated`
  vault.py subagent                              SubagentStart hook: tell subagents how to run this script
  vault.py selftest

Config: ~/.claude/claude-kit/vault.json (or $CLAUDE_KIT_DIR/vault.json)
  {"vault_dir": "<path to the vault>", "projects": {"<repo folder name>": "<folder under Projects/>"}}
$VAULT_DIR overrides vault_dir. Notes under Projects/<name>/ belong to that project.
"""
import json
import marshal
import math
import os
import pathlib
import re
import sys

KIT = pathlib.Path(os.environ.get("CLAUDE_KIT_DIR") or pathlib.Path.home() / ".claude" / "claude-kit")
try:
    CONFIG = json.loads((KIT / "vault.json").read_text(encoding="utf-8"))
except (OSError, ValueError):
    CONFIG = {}
VAULT = pathlib.Path(os.environ.get("VAULT_DIR") or CONFIG.get("vault_dir") or "")
CACHE = KIT / "vault-cache.marshal"
# Repo folder name -> vault project folder. Unmapped cwd gets the project list only.
PROJECTS = CONFIG.get("projects", {})
RUN = f'python -I -S "{pathlib.Path(__file__).resolve()}"'
STOP = set("""a an and are as at be but by can do does for from get got has have how i if in into is it its
me my no not of on or our please should so that the their then there these this to up use was we what when where
which who why will with you your also any all about tell show give let lets need want make check now just more
same like see one two new did done does yes ok okay go still ahead again""".split())
# Generic coding words: say nothing about which project knowledge is needed, so they never trigger the hook.
GENERIC = set("""write function list fix typo readme run test tests commit changes change explain error refactor
loop look code file files add remove update create delete issue problem work works working help try find read think
plan idea way thing things something line lines python script method class variable value return print string
number true false review clean simplify rename move format""".split())
# Calibrated 2026-10-13 on 7 domain vs 7 generic prompts: domain top >= 25, generic <= 16 after GENERIC.
HOOK_MAX, HOOK_MIN_TERMS, HOOK_MIN_SCORE = 5, 3, 22.0
HEADING = re.compile(r"^(#{1,6})\s+(.*)")


def terms(text):
    out = []
    for tok in re.findall(r"[a-z0-9][a-z0-9_.\-/]*[a-z0-9]|[a-z0-9]", text.lower()):
        parts = [p for p in re.split(r"[_.\-/]", tok) if len(p) > 1]
        for t in [tok] + (parts if len(parts) > 1 else []):
            if len(t) > 1 and t not in STOP:
                out.append(t)
    return out


def summary_of(lines):
    for i, line in enumerate(lines):
        if line.lower().startswith("> [!summary]"):
            body = [line[12:].strip()]
            for nxt in lines[i + 1:]:
                if not nxt.startswith(">"):
                    break
                body.append(nxt.lstrip("> ").strip())
            return short(" ".join(b for b in body if b))
    # No summary callout: first plain paragraph line after the H1 title.
    after_title = False
    for line in lines:
        if line.startswith("# "):
            after_title = True
        elif (after_title and line.strip() and not line.startswith((">", "|", "-", "#", "```", "!", "Part of"))
              and len(line) > 40):
            return short(line.strip())
    return ""


def short(text, limit=110):
    if len(text) <= limit:
        return text
    cut = re.search(rf"^(.{{30,{limit}}}?[.!?])(\s|$)", text)
    return cut.group(1) if cut else text[:limit].rsplit(" ", 1)[0] + "…"


def parse(path):
    lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    title, sections, stack, fence = path.stem, [], [], False
    start, heads = 0, []
    def close(end):
        if end > start:
            body = "\n".join(lines[start:end])
            sections.append({"note": title, "path": " › ".join(heads) or "(top)", "start": start + 1,
                             "end": end, "tok": max(1, len(body) // 4),
                             "tf": count(terms(title) * 3 + terms(" ".join(heads)) * 2 + terms(body))})
    for i, line in enumerate(lines):
        if line.startswith("```"):
            fence = not fence
        m = None if fence else HEADING.match(line)
        if m and len(m.group(1)) > 1:  # H1 is the note title: stays in (top) with the summary
            close(i)
            level = len(m.group(1))
            stack = [s for s in stack if s[0] < level] + [(level, m.group(2).strip())]
            start, heads = i, [h for lv, h in stack if lv > 1]
    close(len(lines))
    project = path.parent.name if path.parent.parent.name == "Projects" else ""
    for s in sections:
        s["project"] = project
    return {"title": title, "project": project, "summary": summary_of(lines), "sections": sections}


def count(ts):
    d = {}
    for t in ts:
        d[t] = d.get(t, 0) + 1
    return d


def files():
    return sorted(p for p in VAULT.rglob("*.md") if ".obsidian" not in p.parts and "Templates" not in p.parts)


def load():
    stamp = {str(p): p.stat().st_mtime for p in files()}
    try:
        with CACHE.open("rb") as f:
            cache = marshal.load(f)
        code = pathlib.Path(__file__).stat().st_mtime
        if cache["stamp"] == stamp and cache["code"] == code:
            return cache
        old = cache["parsed"] if cache["code"] == code else {}  # parser changed: re-parse everything
    except (OSError, EOFError, KeyError, ValueError, TypeError):
        old = {}
    # Incremental: re-parse only notes whose mtime changed; df/avg are cheap to recompute.
    parsed = {p: old[p] if p in old and old[p][0] == m else [m, parse(pathlib.Path(p))] for p, m in stamp.items()}
    notes = [parsed[p][1] for p in sorted(parsed)]
    secs = [s for n in notes for s in n["sections"]]
    df = count(t for s in secs for t in s["tf"])
    avg = sum(sum(s["tf"].values()) for s in secs) / max(1, len(secs))
    cache = {"stamp": stamp, "code": pathlib.Path(__file__).stat().st_mtime, "parsed": parsed, "notes": notes, "secs": secs, "df": df, "avg": avg}
    CACHE.parent.mkdir(parents=True, exist_ok=True)
    with CACHE.open("wb") as f:
        marshal.dump(cache, f)
    return cache


def search(cache, query, project=None):
    n = len(cache["secs"])
    # Drop terms that are in >25% of sections: they can't discriminate (project names, "prod", ...).
    q = [t for t in dict.fromkeys(terms(query)) if 0 < cache["df"].get(t, 0) <= n * 0.25]
    idf = {t: math.log(1 + (n - cache["df"][t] + 0.5) / (cache["df"][t] + 0.5)) for t in q}
    hits = []
    for s in cache["secs"]:
        tf, length = s["tf"], sum(s["tf"].values())
        matched = [t for t in q if t in tf]
        if not matched:
            continue
        score = sum(idf[t] * tf[t] * 2.2 / (tf[t] + 1.2 * (0.25 + 0.75 * length / cache["avg"])) for t in matched)
        score *= 1 + 0.3 * (len(matched) - 1)
        if project and s["project"] == project:
            score *= 1.5
        hits.append((score, len(matched), s))
    hits.sort(key=lambda h: -h[0])
    return hits, len(q)


def pointer(s):
    return f"[[{s['note']}]] › {s['path']} (L{s['start']}-{s['end']}, ~{s['tok']} tok)"


def cwd_project(cwd):
    for part in reversed(pathlib.Path(cwd or os.getcwd()).parts):
        if part in PROJECTS:
            return PROJECTS[part]
    return None


def cmd_find(args):
    n, project, words = 8, None, []
    it = iter(args)
    for a in it:
        if a == "-n":
            n = int(next(it))
        elif a == "-p":
            project = next(it)
        else:
            words.append(a)
    hits, _ = search(load(), " ".join(words), project or cwd_project(None))
    for score, _, s in hits[:n]:
        print(f"{score:5.1f}  {pointer(s)}")
    if not hits:
        print("no match")


def resolve(cache, name):
    notes = cache["notes"]
    exact = [x for x in notes if x["title"].lower() == name.lower()]
    found = exact or [x for x in notes if name.lower() in x["title"].lower()]
    if len(found) != 1:
        sys.exit(f"note '{name}': {len(found)} matches " + "; ".join(x["title"] for x in found[:8]))
    return found[0]


def cmd_get(args):
    cache = load()
    note = resolve(cache, args[0])
    secs = note["sections"]
    if len(args) < 2:
        print(f"# {note['title']}: {note['summary']}")
        for s in secs:
            print(f"L{s['start']}-{s['end']} ~{s['tok']} tok  {s['path']}")
        return
    want = " ".join(args[1:]).lower()
    match = [s for s in secs if want in s["path"].lower()]
    if not match:
        sys.exit(f"no heading containing '{want}' in {note['title']}; run get without a heading for the outline")
    # A heading match also returns its subsections (contiguous lines up to the last match).
    first, last = match[0], [s for s in match if s["path"].startswith(match[0]["path"])][-1]
    path = next(p for p in files() if p.stem == note["title"])
    lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    print(f"[{note['title']} L{first['start']}-{last['end']}]")
    print("\n".join(lines[first["start"] - 1:last["end"]]))


def cmd_session(_):
    data = read_stdin_json() if not sys.stdin.isatty() else {}
    project = cwd_project(data.get("cwd"))
    cache = load()
    print(f"Vault script: {RUN} <find|get|log> ...")
    if not project:
        names = sorted({x["project"] for x in cache["notes"] if x["project"]})
        print("Obsidian vault projects: " + ", ".join(names) + ". Use the vault skill to look things up.")
        return
    print(f"Obsidian vault index for {project} (fetch sections with the vault skill; never read whole notes):")
    for x in cache["notes"]:
        if x["project"] == project:
            tok = sum(s["tok"] for s in x["sections"])
            print(f"- {x['title']} (~{tok // 1000 or 1}k tok): {x['summary']}")


def cmd_hook(_):
    data = read_stdin_json()
    prompt = data.get("prompt", "")
    # Slash commands, one-word replies and subagent hand-backs/notifications carry no new question.
    if prompt.startswith("/") or len(prompt) < 12 or "<agent-message" in prompt or "<task-notification" in prompt \
            or prompt.startswith("Another Claude session"):
        return
    words = [t for t in terms(prompt[:2000]) if t not in GENERIC]
    if len(set(words)) < HOOK_MIN_TERMS:  # can't qualify: skip loading the cache (most chat turns exit here)
        return
    hits, _ = search(load(), " ".join(words), cwd_project(data.get("cwd")))
    strong = [h for h in hits if h[1] >= HOOK_MIN_TERMS and h[0] >= HOOK_MIN_SCORE]
    seen, out = set(), []
    for score, _, s in strong:
        if s["note"] in seen:  # one pointer per note keeps the list diverse
            continue
        seen.add(s["note"])
        out.append(pointer(s))
        if len(out) == HOOK_MAX:
            break
    if out:
        print("Possibly relevant vault sections (fetch only if needed: vault.py get \"<note>\" \"<heading>\"):")
        print("\n".join(out))


def cmd_log(args):
    import datetime
    cache = load()
    note = resolve(cache, args[0])
    path = next(p for p in files() if p.stem == note["title"])
    text = path.read_text(encoding="utf-8")
    today = datetime.date.today().isoformat()
    text = re.sub(r"^updated: .*$", f"updated: {today}", text, count=1, flags=re.M)
    entry = f"- {today}: {' '.join(args[1:])}"
    if re.search(r"^## Updates\s*$", text, re.M):
        text = re.sub(r"(^## Updates\s*\n)", rf"\1{entry}\n", text, count=1, flags=re.M)
    else:
        text = text.rstrip("\n") + f"\n\n## Updates\n{entry}\n"
    path.write_text(text, encoding="utf-8")
    print(f"logged to {note['title']}")


def cmd_selftest(_):
    assert terms("INC-12 rate_master.sql the WAF") == ["inc-12", "inc", "12", "rate_master.sql", "rate", "master",
                                                        "sql", "waf"]
    sec = parse_text("---\nupdated: x\n---\n# T\n> [!summary] Short. Rest\n## A\nalpha\n### B\nbeta\n```\n# no\n```\n")
    assert [s["path"] for s in sec["sections"]] == ["(top)", "A", "A › B"], sec["sections"]
    assert sec["summary"] == "Short. Rest"
    print("ok")


def parse_text(text):
    import tempfile
    with tempfile.TemporaryDirectory() as d:
        p = pathlib.Path(d) / "T.md"
        p.write_text(text, encoding="utf-8")
        return parse(p)


def read_stdin_json():
    raw = sys.stdin.buffer.read().decode("utf-8", errors="replace").lstrip("﻿")
    return json.loads(raw or "{}")


def cmd_subagent(_):
    # SubagentStart context only reaches the subagent in the hookSpecificOutput JSON form.
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "SubagentStart", "additionalContext":
        f"Vault script (Obsidian project notes): {RUN} <find|get|log> ... ; see the vault skill's method."}}))


def ready():
    return bool(os.environ.get("VAULT_DIR") or CONFIG.get("vault_dir")) and VAULT.is_dir()


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    cmd, rest = (sys.argv[1], sys.argv[2:]) if len(sys.argv) > 1 else ("help", [])
    run = {"find": cmd_find, "get": cmd_get, "session": cmd_session, "hook": cmd_hook, "log": cmd_log,
           "subagent": cmd_subagent, "selftest": cmd_selftest}.get(cmd, lambda _: print(__doc__))
    if cmd in ("hook", "session", "subagent"):
        if ready():  # no vault configured: hooks stay silent
            try:  # a hook must never block or break the prompt
                run(rest)
            except Exception:  # pylint: disable=broad-except
                pass
    elif cmd in ("find", "get", "log") and not ready():
        sys.exit(f"No vault configured: set VAULT_DIR or create {KIT / 'vault.json'} "
                 '({"vault_dir": "...", "projects": {"<repo folder>": "<vault project folder>"}})')
    else:
        run(rest)
