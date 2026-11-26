"""Rules for the security guard hooks; loaded by guard.py (the launcher holds the prefilter and docs).

Pattern-based by design: it reads the command text (plus any .sh/.ps1 file the command runs), not
what a program does inside. Your environment's prod/uat names come from guard.json (see guard.py).
"""
import json
import os
import re
import sys

from guard import config as load_config

HOME = os.path.expanduser("~")
AUDIT = os.path.join(HOME, ".claude", "audit")

# ponytail: name-based prod detection; built-ins catch prod/prd/uat name segments and -t/--target/TARGET=,
# guard.json adds resource names, subscription IDs and hosts that don't say "prod".
BASE_PROD = r"(?<![a-z0-9])(prod|production|prd)(?![a-z0-9])|(?:\s-t|--target)[\s=]+prod\b|\bTARGET=prod\b"
BASE_UAT = r"(?<![a-z0-9])(uat|staging|stg)(?![a-z0-9])|(?:\s-t|--target)[\s=]+uat\b|\bTARGET=uat\b"
BASE_PROTECTED = r"^(main|master|development|develop|dev|uat|prod|production|release(/.+)?)$"
PROD_TARGET = re.compile(r"(?:\s-t|--target)[\s=]+prod\b|\bTARGET=prod\b", re.I)
DRY = re.compile(r"--dry-run|\b(validate|plan|summary)\b", re.I)
GLOBAL_PROD_PROFILE = re.compile(r"DATABRICKS_CONFIG_PROFILE\s*=\s*['\"]?[\w-]*(?<![a-z0-9])(prod|prd)(?![a-z0-9])", re.I)
NONPROD_OVERRIDE = re.compile(r"(?:\s-p|--profile)[\s=]+['\"]?[\w-]*(?<![a-z0-9])(dev|uat|test|stg|staging)(?![a-z0-9])"
                              r"|(?:\s-t|--target)[\s=]+(?:dev|uat)\b", re.I)
PROD = UAT = PROTECTED = None


def configure(cfg):
    global PROD, UAT, PROTECTED
    PROD = re.compile("|".join([BASE_PROD] + list(cfg.get("prod", []))), re.I)
    UAT = re.compile("|".join([BASE_UAT] + list(cfg.get("uat", []))), re.I)
    PROTECTED = re.compile(cfg.get("protected_branches") or BASE_PROTECTED)


configure(load_config())

AZ = re.compile(r"(?<![\w./-])az(?:\.cmd)?\s+((?:[a-z][a-z0-9-]*\s+)*[a-z][a-z0-9-]*)", re.I)
AZ_READ = re.compile(r"^(show|list|get|query|check|exists|tail|download|wait|browse|version|find|validate|what-if)")
AZ_LOCAL = {"login", "logout", "account", "extension", "config", "upgrade", "bicep", "version", "interactive",
            "init", "cloud", "cache", "feedback", "find"}
DBX = re.compile(r"(?<![\w./-])databricks\s+([a-z][\w-]*)(?:\s+([a-z][\w-]*))?", re.I)
DBX_READ = re.compile(r"^(get|list|export|describe|status|validate|plan|summary|schema|me|profiles|ls|cat|show|"
                      r"open|help|version|generate|view)")
DBX_LOCAL = {"auth", "configure", "completion", "version", "help", "labs"}
GIT = re.compile(r"(?<![\w./-])git(?:\.exe)?\s+(?:-C\s+(\"[^\"]+\"|'[^']+'|\S+)\s+)?(?:-c\s+\S+\s+)*([a-z-]+)(.*)", re.I)

SECRET_FILE = re.compile(r"(?:^|[\s'\"/\\=])(\.env(?:\.[\w-]+)?|\.databrickscfg|\.pgpass|\.git-credentials|\.netrc|"
                         r"id_rsa|id_ed25519)(?=$|[\s'\";|)])", re.M)
SAFE_ENV = re.compile(r"\.env\.(example|sample|template|dist|defaults?)$", re.I)
# A pipeline stage that starts with one of these and names a secret file prints (part of) it.
PRINT_STAGE = re.compile(r"^\s*\(?\s*(?:&\s*)?(cat|type|more|less|head|tail|bat|nl|strings|xxd|od|grep|egrep|rg|"
                         r"findstr|awk|sed|Get-Content|gc|Select-String|sls|Format-Hex)(?![\w-])", re.I)
SAFE_FLAGS = re.compile(r"\s(-l|-L|-c|-q|--count|--files-with-matches|--quiet)(\s|$)")
NAMES_ONLY = re.compile(r"-replace\s+['\"]=\.\*['\"]|cut\s+-d\s*['\"]?=['\"]?\s+-f\s*1|Split\(\s*['\"]=['\"]\s*\)\[0\]"
                        r"|\s-[a-zA-Z]*o[a-zA-Z]*\s+['\"]?\^")  # grep -o '^NAME' prints names only
GREP_FAMILY = re.compile(r"^\s*\(?\s*(?:&\s*)?(grep|egrep|rg|findstr|Select-String|sls)(?![\w-])", re.I)
SED_SAFE = re.compile(r"^\s*sed\b[^|]*(\s-i\b|REDACT|MASK|\*\*\*|s/=\.\*/)", re.I)  # in-place edit or masking
SAVED = re.compile(r"\|\s*(Set-Content|Out-File|Add-Content)\b", re.I)


def anchored_name_grep(stage):
    """grep/Select-String for one named, non-secret variable (`^NEXT_PUBLIC_API_URL=`) without extra context lines."""
    m = re.search(r"(?:-Pattern\s+|\s)['\"]?\^([A-Za-z_][A-Za-z0-9_]*)", stage)
    if m and not re.search(SECRETISH, m.group(1), re.I) and not re.search(r"\s-[ABC]\s*[1-9]|--(after-|before-)?context", stage):
        return True
    # grep -o with a pattern that can't reach a value (no `=`, no open-ended .* / .+ / \S+) prints only the match
    pat = re.search(r"\s-[a-zA-Z]*o[a-zA-Z]*\s+(\"[^\"]*\"|'[^']*')", stage)
    return bool(pat) and not re.search(r"=|\.\*|\.\+|\\S[+*]", pat.group(1))
# Output captured into a variable, piped to a consumer or redirected to a file is not printed.
CAPTURED = re.compile(r"\$?\w+\s*=\s*(&\s*)?\(?\s*\$?az\b|\$\(\s*az\b|--password-stdin|\|\s*(Out-File|Set-Content|Add-Content)\b"
                      r"|(?<![\d&])>\s*[^&\s]", re.I)
SECRETISH = r"\w*(KEY|SECRET|TOKEN|PASSWORD|PWD|CONN)\w*"
ENV_LIST = re.compile(r"(?<![\w-])(Get-ChildItem|gci|ls|dir)\s+env:(?!\w)", re.I)
ENV_DUMP = [
    re.compile(r"^\s*(env|printenv|set|export\s+-p)\s*$", re.I),
    re.compile(r"(?<![\w-])printenv\s+" + SECRETISH, re.I),
    re.compile(r"(?<![\w-])(echo|Write-Output|Write-Host)\s+[^|;]*\$(env:)?\{?" + SECRETISH, re.I),
    re.compile(r"^\s*\$env:" + SECRETISH + r"\s*$", re.I),
]
SCRATCH_CD = re.compile(r"\bcd\s+[\"']?[^\"'\n;&]*(scratchpad|[\\/]Temp[\\/]|/tmp/)", re.I)
ALWAYS_SECRET = re.compile(r"(?<![\w-])az\s[^\n;]*?\b(show-connection-string|connection-string\s+show|credential\s+reset|"
                           r"list-publishing-(profiles|credentials)|create-for-rbac)\b"
                           r"|(?<![\w-])databricks\s+(auth\s+token|secrets\s+get-secret|tokens\s+create)\b", re.I)
SECRET_UNLESS_QUERY = re.compile(r"(?<![\w-])az\s[^\n;]*?\b(keys\s+list|list-keys|admin-key\s+show|query-key\s+list|"
                                 r"credential\s+(show|list)|keyvault\s+secret\s+(show|download)|get-access-token|"
                                 r"appsettings\s+list|connection-string\s+list|secret\s+(list|show)\s[^\n;]*--show-values)\b", re.I)

REDACT = [
    (re.compile(r"(?i)((?:AccountKey|SharedAccessKey|Password|Pwd|ApiKey|api[-_]key|secret|token)\s*[=:]\s*)[^\s;'\"]+"), r"\1<redacted>"),
    (re.compile(r"(?i)(--(?:password|secret|value|admin-password|client-secret|sas-token|account-key)[\s=]+)(\"[^\"]*\"|'[^']*'|\S+)"), r"\1<redacted>"),
    (re.compile(r"eyJ[\w-]{10,}\.[\w-]{10,}\.[\w-]*"), "<jwt>"),
    (re.compile(r"\bdapi[0-9a-f]{32}\b"), "<dbx-token>"),
    (re.compile(r"(postgres(?:ql)?://[^:\s/]+:)[^@\s]+@"), r"\1<redacted>@"),
]


def segments(text):
    return [s for s in re.split(r"\r?\n|;|&&|\|\|", text) if s.strip()]


def strip_data(cmd):
    """Drop heredoc / here-string bodies that are data (a python script, notes), keeping ones that are run
    (fed to bash, or written to a .sh/.ps1 file)."""
    def heredoc(m):
        line_start = cmd.rfind("\n", 0, m.start()) + 1
        consumer = cmd[line_start:m.start()]
        keep = re.search(r"\.(sh|ps1)\b|(^|\s)(bash|sh|wsl)(\s|$)", consumer)
        return m.group(0) if keep else consumer[:0] + "<<" + m.group(2) + "\n" + m.group(2)
    out = re.sub(r"<<-?\s*(['\"]?)(\w+)\1[^\n]*\n.*?\n\s*\2\s*$", heredoc, cmd, flags=re.S | re.M)
    if not re.search(r"\.(sh|ps1)\b|\bwsl\b", out, re.I):
        out = re.sub(r"@(['\"])\r?\n.*?\r?\n\1@", "@''@", out, flags=re.S)
    return out


def unquote(seg):
    return re.sub(r"\"[^\"]*\"|'[^']*'", "\"\"", seg)


def variables(text):
    pairs = re.findall(r"(?:^|[\s;(])(?:export\s+|set\s+|\$env:)?\$?(\w+)\s*=\s*(\"[^\"\n]*\"|'[^'\n]*'|[^\s;]+)", text, re.M)
    return {k.lower(): v.strip("\"'") for k, v in pairs}


def expand(seg, env):
    return re.sub(r"\$\{?(\w+)\}?", lambda m: env.get(m.group(1).lower(), m.group(0)), seg)


def with_scripts(cmd, cwd):
    """Append the text of .sh/.ps1 files the command runs (the Databricks CLI runs via `wsl -e bash x.sh`)."""
    parts = [cmd]
    for p in re.findall(r"""(?:^|[\s'"])((?:[A-Za-z]:|/mnt/[a-z]|~|\.{1,2})?[^\s'";|&]*\.(?:sh|ps1))(?=$|[\s'";|&)])""", cmd)[:5]:
        m = re.match(r"/mnt/([a-z])/(.*)", p)
        path = f"{m.group(1).upper()}:/{m.group(2)}" if m else os.path.expanduser(p)
        if not os.path.isabs(path) and cwd:
            path = os.path.join(cwd, path)
        try:
            if os.path.isfile(path) and os.path.getsize(path) < 200_000:
                with open(path, encoding="utf-8", errors="replace") as fh:
                    parts.append(fh.read())
        except OSError:
            pass
    return "\n".join(parts)


def query_ok(seg):
    """--query returns names/metadata only, or the value of named settings that aren't secrets."""
    m = re.search(r"--query[\s=]+(\"[^\"]*\"|'[^']*'|\S+)", seg)
    if not m:
        return False
    q = m.group(1)
    if not re.search(r"value|primary|secondary|connection|password|secret|token|key(?!name)", q, re.I):
        return True
    names = re.findall(r"\bname\s*==\s*\\?['\"`]([^'\"`\\]+)", q)
    return bool(names) and not any("$" in n or re.search(SECRETISH, n, re.I) for n in names)


def az_calls(seg):
    for m in AZ.finditer(seg):
        words = m.group(1).split()
        if not words or words[0].lower() in AZ_LOCAL:
            continue
        tail = seg[m.end():]
        if re.match(r"[^|;]*?\s(-h|--help)(\s|$)", tail):
            yield " ".join(words), False
        elif words[0].lower() == "rest":
            meth = re.search(r"(?:--method|-m)\s+['\"]?(\w+)", tail)
            yield "rest", bool(meth) and meth.group(1).lower() not in ("get", "head")
        else:  # any read verb among the words (positional names may follow it: `acr manifest show-metadata <name>`)
            yield " ".join(words), not any(AZ_READ.match(w.lower()) for w in words[1:])


def dbx_calls(seg):
    for m in DBX.finditer(seg):
        if seg[max(0, m.start() - 5):m.start()].lower() == "from ":  # python `from databricks import sql`
            continue
        group, verb = m.group(1).lower(), (m.group(2) or "").lower()
        if group in DBX_LOCAL:
            continue
        if group == "api" and verb == "post" and "/sql/statements" in seg:  # sqlrun.py-style query: read if SELECT-like
            stmt = re.search(r"statement\W{1,8}(\w+)", seg[m.end():], re.I)
            yield "api post sql", not (stmt and stmt.group(1).lower() in ("select", "with", "show", "describe", "explain"))
            continue
        yield f"{group} {verb}".strip(), not DBX_READ.match(verb or group)


def current_branch(where):
    try:
        import subprocess
        r = subprocess.run(["git", "-C", where or ".", "rev-parse", "--abbrev-ref", "HEAD"],
                           capture_output=True, text=True, timeout=3)
        return r.stdout.strip()
    except Exception:
        return ""


def git_findings(seg, cwd, scratch=False):
    deny, ask, change = [], [], None
    m = GIT.search(seg)
    if not m:
        return deny, ask, change
    if scratch and m.group(2).lower() in ("reset", "clean", "branch", "checkout", "restore"):
        return deny, ask, change  # throwaway clone in a scratch/temp folder
    where, sub, rest = (m.group(1) or "").strip("\"'") or cwd, m.group(2).lower(), " " + m.group(3)
    if sub == "push":
        if "--no-verify" in rest:
            deny.append("`git push --no-verify` skips the repo's checks")
        if "--force-with-lease" in rest:
            ask.append("force-push (with lease) rewrites remote history")
        elif re.search(r"\s(--force|-f)(\s|$)|\s\+\S", rest):
            deny.append("force-push rewrites shared history; push a new commit instead, or let the user force-push themselves")
        if re.search(r"\s(--delete|-d)(\s|$)|\s:\S", rest):
            ask.append("deletes a remote branch")
        args = [a for a in rest.split() if not a.startswith("-")]
        dsts = [r.lstrip("+").split(":")[-1].replace("refs/heads/", "") for r in args[1:]] or ["HEAD"]
        dsts = [current_branch(where) if d == "HEAD" else d for d in dsts]
        hit = [d for d in dsts if d and PROTECTED.match(d)]
        if hit:
            ask.append(f"pushes to protected branch {', '.join(hit)}")
        change = ("git-push", ",".join(d for d in dsts if d) or "?")
    elif sub == "commit" and re.search(r"--no-verify|\s-n(\s|$)", rest):
        deny.append("`git commit --no-verify` skips the repo's pre-commit checks; fix what they report instead")
    elif sub == "reset" and "--hard" in rest:
        ask.append("`git reset --hard` discards uncommitted work")
    elif sub == "clean" and re.search(r"\s-[a-zA-Z]*f", rest):
        ask.append("`git clean -f` deletes untracked files")
    elif sub == "branch" and re.search(r"\s-D(\s|$)", rest):
        ask.append("`git branch -D` force-deletes a branch")
    elif sub in ("checkout", "restore") and re.search(r"\s(--\s+)?\.(\s|$)", rest) and not (
            "--staged" in rest and "--worktree" not in rest):
        ask.append(f"`git {sub} .` discards uncommitted changes")
    return deny, ask, change


def secret_findings(seg):
    out = []
    for stage in seg.split("|"):
        grep = GREP_FAMILY.match(stage)
        if SED_SAFE.match(stage) or SAVED.search(seg) or (grep and anchored_name_grep(stage)):
            continue
        files_text = stage
        if grep:  # a quoted ".env" there is the search pattern, not a file
            files_text = unquote(stage) + " " + " ".join(re.findall(r"-(?:Literal)?Path\s+(\"[^\"]*\"|'[^']*')", stage, re.I))
        files_text = re.sub(r">>?\s*\S+", " ", files_text)  # a redirect target is written, not printed
        bad = [f for f in SECRET_FILE.findall(files_text) if not SAFE_ENV.search(f)]
        if bad and PRINT_STAGE.match(stage) and not NAMES_ONLY.search(seg) and not SAFE_FLAGS.search(stage):
            out.append(f"prints the secret file `{bad[0]}`; show variable names only, e.g. `cut -d= -f1 {bad[0]}` or "
                       f"`(Get-Content {bad[0]}) -replace '=.*'`")
    captured = bool(CAPTURED.search(seg))
    creates = re.search(r"credential\s+reset|create-for-rbac|tokens\s+create", seg, re.I)
    if ALWAYS_SECRET.search(seg) and (creates or not captured):
        out.append("prints or creates a credential; read the setting's name or Key Vault reference instead, capture the "
                   "value into a variable and pass it on without printing it, or ask the user to do it")
    elif SECRET_UNLESS_QUERY.search(seg) and not query_ok(seg) and not captured:
        out.append("prints secret values; add a `--query` that returns names or metadata only (e.g. `--query \"[].name\"`, "
                   "`--query id`, `--query expiresOn`), or capture the value and pass it straight to the command that "
                   "needs it")
    lst = ENV_LIST.search(seg)
    rest = seg[lst.end():] if lst else ""
    names_only = (re.search(r"\.Name\b|Select(-Object)?\s+(-Property\s+)?Name\b", rest, re.I)
                  and not re.search(r"\.Value\b(?!\.Length)|Select(-Object)?\s+[^|]*\bValue\b", rest, re.I))
    if (lst and not names_only) or any(p.search(seg) for p in ENV_DUMP):
        out.append("prints environment variables that may hold secrets; list names only (`Get-ChildItem env: | "
                   "Select-Object Name`, or `env | cut -d= -f1`)")
    return out


def env_of(text):
    return "prod" if PROD.search(text) else "uat" if UAT.search(text) else "dev/other"


def analyze(cmd, cwd):
    """Return (deny reasons, ask reasons, changes) for a shell command."""
    text = with_scripts(strip_data(re.sub(r"[\\`]\r?\n", " ", cmd)), cwd)
    env = variables(text)
    gprod = bool(GLOBAL_PROD_PROFILE.search(text))
    scratch = bool(SCRATCH_CD.search(expand(text, env)))
    deny, ask, changes = [], [], []
    for raw in segments(text):
        seg = expand(raw, env)
        deny += secret_findings(seg)
        prod = bool(PROD.search(seg))
        for name, write in az_calls(seg):
            if write:
                changes.append(("azure", env_of(seg), seg))
                if prod:
                    ask.append(f"Azure change in production (`az {name}`)")
        for name, write in dbx_calls(seg):
            dprod = prod or (gprod and not NONPROD_OVERRIDE.search(seg))
            if write:
                changes.append(("databricks", "prod" if dprod else env_of(seg), seg))
                if dprod:
                    ask.append(f"Databricks change in production (`databricks {name}`)")
        g_deny, g_ask, g_change = git_findings(seg, cwd, scratch)
        deny += g_deny
        ask += g_ask
        if g_change:
            changes.append((g_change[0], "branch " + g_change[1], seg))
    # Any other command aimed at the prod target (make deploy, apply_ddl.py, ...). Quotes are dropped from
    # the whole text first, so `TARGET=prod` inside a message or log line doesn't count.
    for raw in segments(unquote(text)):
        seg = expand(raw, env)
        if PROD_TARGET.search(seg) and not AZ.search(seg) and not DBX.search(seg) and not DRY.search(seg):
            changes.append(("prod-target", "prod", seg))
            ask.append("command runs against the prod target")
    return deny, ask, changes


def secret_path(p):
    name = re.split(r"[\\/]", str(p))[-1]
    if re.fullmatch(r"\.env(\.[\w-]+)?", name):
        return not SAFE_ENV.search(name)
    return name in (".databrickscfg", ".pgpass", ".git-credentials", ".netrc", "id_rsa", "id_ed25519")


def pre(data):
    tool, inp, cwd = data.get("tool_name", ""), data.get("tool_input") or {}, data.get("cwd") or ""
    deny, ask = [], []
    if tool in ("Bash", "PowerShell"):
        deny, ask, _ = analyze(inp.get("command", ""), cwd)
    elif tool == "Read" and secret_path(inp.get("file_path", "")):
        deny.append("reads a secret file; list the variable names instead, or ask the user for the one value needed")
    elif tool == "Grep" and (secret_path(inp.get("path", "")) or re.search(r"\.env(?!\.(example|sample|template))",
                                                                          str(inp.get("glob", "")))):
        deny.append("searches a secret file; search names only (e.g. `^\\w+=` with output limited to names)")
    elif tool == "mcp__azure-devops__pipelines_write" and not inp.get("previewRun"):
        ids = {k: v for k, v in inp.items() if k in ("action", "pipelineId", "definitionId", "project", "branch")}
        ask.append(f"Azure DevOps pipeline write {ids}: a pipeline run may deploy")
    elif tool == "mcp__azure-devops__repo_pull_request_write" and (inp.get("bypassReason") or inp.get("autoComplete")):
        ask.append("pull request will merge automatically or bypass branch policies")
    if deny:
        decision, reason = "deny", "Blocked by the security guard: " + "; ".join(dict.fromkeys(deny))
    elif ask:
        decision, reason = "ask", "Security guard: " + "; ".join(dict.fromkeys(ask)) + ". Approve only if you intended this."
    else:
        return None
    return {"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": decision,
                                   "permissionDecisionReason": reason}}


def redact(s):
    for rx, rep in REDACT:
        s = rx.sub(rep, s)
    return s[:400]


def append(rec, name=None):
    import datetime
    os.makedirs(AUDIT, exist_ok=True)
    rec = {"ts": datetime.datetime.now().isoformat(timespec="seconds"), **rec}
    with open(os.path.join(AUDIT, name or f"{datetime.date.today():%Y-%m}.jsonl"), "a", encoding="utf-8") as f:
        f.write(json.dumps(rec, ensure_ascii=False) + "\n")


def post(data):
    tool, inp = data.get("tool_name", ""), data.get("tool_input") or {}
    base = {"session": str(data.get("session_id", ""))[:8], "cwd": data.get("cwd", ""), "tool": tool}
    if tool in ("Bash", "PowerShell"):
        for kind, env, seg in analyze(inp.get("command", ""), data.get("cwd") or "")[2]:
            append({**base, "kind": kind, "env": env, "detail": redact(seg.strip())})
    elif tool.startswith("mcp__azure-devops__") and re.search(r"write|create_branch|upsert", tool):
        keep = ("action", "project", "repositoryId", "pullRequestId", "pipelineId", "definitionId", "id", "workItemId",
                "branchName", "sourceRefName", "targetRefName", "status", "vote", "threadId")
        detail = json.dumps({k: inp[k] for k in keep if k in inp})
        append({**base, "kind": "azure-devops", "env": env_of(detail), "detail": detail})


def config(data):
    where = next((str(data[k]) for k in ("file_path", "path", "source", "setting_source", "scope") if data.get(k)), "")
    append({"kind": "config-change", "detail": where, "keys": sorted(data)})
    return {"systemMessage": "Claude Code settings changed during this session" + (f" ({where})" if where else "")
            + ". If you didn't make this change, check it before continuing: settings can add hooks and permission "
              "rules that run with your access."}


TEST_CONFIG = {"prod": ["contosoprod", "11111111-2222-3333-4444-555555555555"], "uat": ["contosouat"],
               "triggers": ["11111111-2222"]}

CASES = [
    # (tool, input, expected decision) — shapes taken from real commands; names are made up, see TEST_CONFIG
    ("PowerShell", "az containerapp update -n contosoprodapi01 -g rg-contoso-prod-01 --image x:1", "ask"),
    ("PowerShell", "$rg = 'rg-contoso-prod-01'\naz containerapp revision restart -g $rg -n app --revision r", "ask"),
    ("PowerShell", "az containerapp show -n contosoprodapi01 -g rg-contoso-prod-01 --query properties.runningStatus -o tsv", None),
    ("PowerShell", "az containerapp update -n contosouatapi01 -g rg-contoso-uat-01 --image x:1", None),
    ("PowerShell", "az monitor log-analytics query -w 00000000-0000-0000-0000-00000000abcd --analytics-query \"ContainerAppConsoleLogs_CL | take 5\"", None),
    ("PowerShell", "az account set --subscription 11111111-2222-3333-4444-555555555555", None),
    ("PowerShell", "az rest --method post --url https://management.azure.com/subscriptions/11111111-2222-3333-4444-555555555555/x", "ask"),
    ("PowerShell", "az rest --url https://management.azure.com/subscriptions/11111111-2222-3333-4444-555555555555/x", None),
    ("Bash", "export DATABRICKS_CONFIG_PROFILE=acme-prod\ndatabricks jobs run-now 123456789 --no-wait", "ask"),
    ("Bash", "export DATABRICKS_CONFIG_PROFILE=acme-prod\ncd ~\ndatabricks jobs get-run 123456789 -o json", None),
    ("Bash", "export DATABRICKS_CONFIG_PROFILE=acme-dev\ndatabricks bundle deploy -t dev", None),
    ("Bash", "make deploy TARGET=prod", "ask"),
    ("Bash", "python3 src/common/utils/apply_ddl.py --target prod --dry-run", None),
    ("Bash", "databricks bundle validate -t prod", None),
    ("Bash", "databricks bundle deploy -t prod --force", "ask"),
    ("PowerShell", "az storage account keys list -n contosoprodadls01 -g rg-contoso-prod-01", "deny"),
    ("PowerShell", "az storage account keys list -n x -g y --query \"[].keyName\" -o tsv", None),
    ("PowerShell", "az storage account show-connection-string -n x -g y", "deny"),
    ("PowerShell", "az keyvault secret show --vault-name kv -n db-password", "deny"),
    ("PowerShell", "az keyvault secret show --vault-name kv -n db-password --query id -o tsv", None),
    ("PowerShell", "az account get-access-token --resource https://management.azure.com", "deny"),
    ("PowerShell", "az account get-access-token --query expiresOn -o tsv", None),
    ("PowerShell", "az webapp config appsettings list -n web -g rg", "deny"),
    ("PowerShell", "az webapp config appsettings list -n web -g rg --query \"[].name\" -o tsv", None),
    ("Bash", "cat backend/.env", "deny"),
    ("Bash", "cat backend/.env.example", None),
    ("PowerShell", "Get-Content C:\\Users\\me\\projects\\app\\.env.uat", "deny"),
    ("PowerShell", "(Get-Content .env) -replace '=.*'", None),
    ("Bash", "cat ~/.databrickscfg", "deny"),
    ("PowerShell", "Get-ChildItem env:", "deny"),
    ("PowerShell", "Get-ChildItem env: | Select-Object Name", None),
    ("Bash", "echo $OPENAI_API_KEY", "deny"),
    ("Bash", "databricks auth token -p acme-dev", "deny"),
    ("Bash", "git push --force origin feature/x", "deny"),
    ("Bash", "git push origin feature/x", None),
    ("Bash", "git push origin main", "ask"),
    ("Bash", "git push origin HEAD:development", "ask"),
    ("Bash", "git push --force-with-lease origin feature/x", "ask"),
    ("Bash", "git commit -m \"fix\" --no-verify", "deny"),
    ("Bash", "git reset --hard HEAD~1", "ask"),
    ("Bash", "git clean -fd", "ask"),
    ("Bash", "git restore --staged .", None),
    ("Bash", "git status && git log --oneline -5", None),
    ("Read", {"file_path": "C:\\Users\\me\\projects\\app\\backend\\.env"}, "deny"),
    ("Read", {"file_path": "C:\\Users\\me\\projects\\app\\backend\\.env.example"}, None),
    ("Read", {"file_path": "C:\\Users\\me\\projects\\app\\backend\\app.py"}, None),
    ("Grep", {"pattern": "KEY", "glob": "**/.env*"}, "deny"),
    ("mcp__azure-devops__pipelines_write", {"action": "run_pipeline", "pipelineId": 12}, "ask"),
    ("mcp__azure-devops__repo_pull_request_write", {"action": "update", "autoComplete": True}, "ask"),
    ("mcp__azure-devops__repo_pull_request_write", {"action": "create", "title": "x"}, None),
    # false-positive classes found by replaying ~30k past calls
    ("Bash", "M=\"C:/x/memory/infra\"; python - <<'PYEOF'\np = 'cmd: az containerapp update -n contosoprodapi01 -g rg-contoso-prod-01'\nPYEOF", None),
    ("Bash", "cat > \"$S/run.sh\" <<'EOF'\nexport DATABRICKS_CONFIG_PROFILE=acme-prod\ndatabricks bundle deploy -t prod\nEOF\nwsl -e bash \"$S/run.sh\"", "ask"),
    ("PowerShell", "$rg='rg-contoso-prod-01'; & $az webapp sitecontainers update -g $rg -h", None),
    ("PowerShell", "$c = az acr credential show -n reg -o json | ConvertFrom-Json; $c.passwords[0].value | Out-File -Encoding ascii pw.txt", None),
    ("PowerShell", "az acr credential show -n reg", "deny"),
    ("PowerShell", "$conn = az storage account show-connection-string -n x -g y --query connectionString -o tsv", None),
    ("Bash", "git check-ignore -v backend/.env | head -5", None),
    ("Bash", "head -5 .env", "deny"),
    ("Bash", "grep KEY backend/.env", "deny"),
    ("Bash", "grep -c KEY backend/.env", None),
    ("PowerShell", "Get-ChildItem Env: | Where-Object { $_.Name -match 'DATABRICKS' } | ForEach-Object { $_.Name }", None),
    ("PowerShell", "Get-ChildItem Env: | ForEach-Object { \"$($_.Name)=$($_.Value)\" }", "deny"),
    ("Bash", "$PY log \"Notes - Deploys\" \"deployed with make deploy TARGET=prod\"", None),
    ("mcp__azure-devops__pipelines_write", {"action": "run_pipeline", "pipelineId": 546, "previewRun": True}, None),
    ("Bash", "cd \"C:/Users/me/AppData/Local/Temp/claude/x/scratchpad/mergesim\" && git reset --hard origin/development", None),
    ("Bash", "W=\"$TEMP/claude/x/scratchpad/mergesim\"; cd \"$W\"; git reset -q --hard origin/development", None),
    ("PowerShell", "az acr manifest show-metadata contosoprodacr/api:prod-1", None),
    ("PowerShell", "az deployment group validate -g rg-contoso-prod-01 -f main.bicep", None),
    ("PowerShell", "az webapp restart -n contosoprodweb01 -g rg-contoso-prod-01 -o none", "ask"),
    ("PowerShell", "az network nsg rule delete -g rg-contoso-prod-01 --nsg-name n -n r", "ask"),
    ("Bash", "grep -oE '^[A-Z_]+' .env | sort", None),
    ("Bash", "grep -nE \".env\" backend/.gitignore", None),
    ("PowerShell", "az webapp config appsettings list -n web -g rg --query \"[?name=='BACKEND_URL'].value\" -o tsv", None),
    ("PowerShell", "az webapp config appsettings list -n web -g rg --query \"[?name=='NEXTAUTH_SECRET'].value\" -o tsv", "deny"),
    ("PowerShell", "Get-ChildItem Env: | ForEach-Object { \"$($_.Name): $($_.Value.Length) chars\" }", None),
    ("Bash", "PY=x\n$PY log \"Notes - Deploys\" \"prod deploy ran\nwith make deploy TARGET=prod from me's login\"", None),
    ("Bash", "sed -E 's/=.*/=<REDACTED>/' .env", None),
    ("Bash", "sed -i '/^LAKEBASE_SYNCED_SCHEMA=/d' .env", None),
    ("Bash", "cat >> .env <<EOF\nX=1\nEOF", None),
    ("Bash", "grep -n \"^LAKEBASE_DATABASE\" .env", None),
    ("Bash", "grep -n \"^PUBLIC_SITE_ID=\" -A0 backend/.env.prod", None),
    ("Bash", "grep -n \"LAKEBASE\" .env", "deny"),
    ("Bash", "grep -n \"^DB_PASSWORD\" .env", "deny"),
    ("Bash", "grep -A3 \"acme\" ~/.databrickscfg", "deny"),
    ("PowerShell", "(Get-Content C:\\x\\.env) -replace '^A=.*','A=b' | Set-Content C:\\x\\.env", None),
    ("PowerShell", "Select-String -Path C:\\x\\.env -Pattern '^EMAIL_FROM_ADDRESS'", None),
    ("Bash", "tail -16 .env", "deny"),
    ("Bash", "grep -rhoE \"warehouses/[0-9a-f]{16}\" backend/.env memory", None),
    ("Bash", "grep -oE \"API_KEY=.*\" backend/.env", "deny"),
    ("Bash", "sed -n '21p' .env", "deny"),
    ("Bash", "export DATABRICKS_CONFIG_PROFILE=acme-prod\ndatabricks api post /api/2.0/sql/statements --json \"{\\\"warehouse_id\\\": \\\"w\\\", \\\"statement\\\": \\\"SELECT count(*) FROM t\\\"}\"", None),
    ("Bash", "export DATABRICKS_CONFIG_PROFILE=acme-prod\ndatabricks api post /api/2.0/sql/statements --json \"{\\\"warehouse_id\\\": \\\"w\\\", \\\"statement\\\": \\\"DELETE FROM t\\\"}\"", "ask"),
]


def selftest():
    from guard import needs_check
    configure(TEST_CONFIG)
    extra = [t.lower() for t in TEST_CONFIG["triggers"]]
    fails = 0
    for tool, inp, want in CASES:
        inp = {"command": inp} if isinstance(inp, str) else inp
        payload = {"tool_name": tool, "tool_input": inp, "cwd": HOME}
        out = pre(payload)
        got = out and out["hookSpecificOutput"]["permissionDecision"]
        if got != want:
            fails += 1
            print(f"FAIL want={want} got={got}: {tool} {inp}")
        for sep in ((",", ":"), (", ", ": ")):  # the prefilter must never skip a case that should fire
            if want and not needs_check(json.dumps(payload, separators=sep).lower(), extra):
                fails += 1
                print(f"FAIL prefilter skips: {tool} {inp}")
    red = redact("psql postgres://app_ro:S3cr3tPass@host/db AccountKey=abc123== --password hunter2")
    if "S3cr3t" in red or "abc123" in red or "hunter2" in red:
        fails += 1
        print("FAIL redact:", red)
    print(f"{len(CASES) + 1 - fails}/{len(CASES) + 1} passed")
    return 1 if fails else 0


def main(mode, raw):
    if mode == "selftest":
        sys.exit(selftest())
    try:
        data = json.loads(raw or "{}")
        out = {"pre": pre, "post": post, "config": config}[mode](data)
        if out:
            sys.stdout.write(json.dumps(out))
    except Exception:
        try:
            import traceback
            append({"mode": mode, "error": traceback.format_exc()}, "guard-errors.log")
        except OSError:
            pass
