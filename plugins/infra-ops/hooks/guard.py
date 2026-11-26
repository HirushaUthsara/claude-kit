"""Security guard for Claude Code hooks. Stdlib only; run as: python -I -S guard.py <mode>

  pre       PreToolUse: production-change gate (ask), secret guard (deny), git safety (deny/ask)
  post      PostToolUse (async): append Azure / Databricks / git / Azure DevOps changes to
            ~/.claude/audit/<YYYY-MM>.jsonl
  config    ConfigChange: tell the user a settings file changed during the session
  selftest  run the built-in cases in guard_rules.py (exit 1 on any failure)

Your environment's names go in ~/.claude/claude-kit/guard.json (or $CLAUDE_KIT_DIR/guard.json), e.g.
  {"prod": ["contoso-?prod", "<prod subscription id>"], "uat": ["contoso-?uat"],
   "triggers": ["<prod subscription id>"], "protected_branches": "^(main|release/.+)$"}
`prod` / `uat` are regexes (case-insensitive) added to the built-in ones; `triggers` are plain substrings
that must reach the rules even without the word "prod" (IDs, hostnames).

This launcher stays tiny on purpose: `pre` runs before every shell command, and Python re-compiles the
script it starts on every run but caches imported modules. So the prefilter lives here and exits before
loading the rules when the input holds no trigger word; the rules live in guard_rules.py (compiled once).
Fail-open: an internal error lets the action through and is logged to ~/.claude/audit/guard-errors.log.
"""
import sys

# A rule in guard_rules.py can only fire if one of these appears in the (lowercased) hook input.
TRIGGERS = (".env", "databrickscfg", "pgpass", "git-credentials", ".netrc", "id_rsa", "id_ed25519",
            "prod", "prd", "uat", ".sh", ".ps1", "printenv", "env:", "export -p",
            "pipelines_write", "pull_request_write")


def config():
    import json
    import os
    folder = os.environ.get("CLAUDE_KIT_DIR") or os.path.join(os.path.expanduser("~"), ".claude", "claude-kit")
    try:
        with open(os.path.join(folder, "guard.json"), encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def needs_check(raw, extra=()):
    if any(t in raw for t in TRIGGERS) or any(t in raw for t in extra):
        return True
    if ("az" in raw or "databricks" in raw) and any(t in raw for t in (
            "key", "secret", "token", "credential", "connection", "appsettings", "publishing", "rbac")):
        return True
    if "git" in raw and any(t in raw for t in ("push", "commit", "reset", "clean", "branch", "checkout", "restore")):
        return True
    if ("echo" in raw or "write-" in raw) and any(t in raw for t in ("key", "secret", "token", "password", "pwd", "conn")):
        return True
    return any(f'"command":{sp}"{c}' in raw for sp in ("", " ") for c in ("env", "set"))


if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) > 1 else "selftest"
    raw = "" if mode == "selftest" else sys.stdin.buffer.read().decode("utf-8", "replace")
    if mode == "pre" and not needs_check(raw.lower(), [t.lower() for t in config().get("triggers", [])]):
        sys.exit(0)
    import os
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))  # -I drops the script dir from sys.path
    import guard_rules
    guard_rules.main(mode, raw)
