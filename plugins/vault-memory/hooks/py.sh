#!/bin/sh
# Run a Python 3 script for a hook: python3 where it is real, else python
# (on Windows, python3 is often only the Microsoft Store shortcut).
py=$(command -v python3 2>/dev/null)
case "$py" in ""|*WindowsApps*) py=python ;; esac
exec "$py" -I -S "$@"
