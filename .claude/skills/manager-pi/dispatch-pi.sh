#!/usr/bin/env bash
# dispatch-pi.sh — launch ONE pi/Kimi-K3 dev in its worktree, with a wedge watchdog.
#
# Usage (via the Bash tool with run_in_background: true, ONE call per dev):
#   .claude/skills/manager-pi/dispatch-pi.sh <dev> <base-sha> <session-id> <prompt-file> [stagger-secs]
#
# - <dev>         short id, e.g. "om"        -> worktree ../opensas-pi-om
# - <base-sha>    gated base (last green master tip)
# - <session-id>  unique per dispatch, e.g. "mgrpi-optmissing" (used to find the .jsonl)
# - <prompt-file> file holding the TASK detail (jira line + repro + owned file + gate instruction)
# - [stagger-secs] optional: sleep this many seconds BEFORE launching (to space concurrent
#                  session-inits — the black-hole wedge correlates with init bursts).
#
# Runs pi in the FOREGROUND-equivalent (waits on it) so the background Bash task stays alive
# until pi exits => the manager gets a normal completion notification. A detached watchdog
# kills the run at WEDGE_SECS if it never wrote its session .jsonl (the black-hole signature:
# TCP to Kimi opens, no response, no error, 0 CPU, no journal — pi-retry can't catch it).
set -u

dev=${1:?dev}; base=${2:?base-sha}; sid=${3:?session-id}; promptfile=${4:?prompt-file}
stagger=${5:-0}

PI=~/.nvm/versions/node/v26.5.0/bin/pi
# `pi` is a JS bundle behind `#!/usr/bin/env node`. If node is not on PATH the shebang fails
# with "env: 'node': No such file or directory" and pi EXITS 0 HAVING PRINTED NOTHING — which is
# indistinguishable from a dev that had nothing to do. That is what was misfiled as
# KIMI-PROVIDER-DOWN (tick452): three runs, zero commits, rc 0, blamed on the provider for
# hours. This shell's PATH is inherited from a different (macOS) box, so node is NOT on it.
export PATH="$HOME/.nvm/versions/node/v26.5.0/bin:$PATH"
command -v node >/dev/null || { echo "pi-$dev: FATAL node not on PATH — refusing to launch (a silent rc-0 run reads as success)"; exit 4; }
CHARTER=/tmp/pi-charter.txt
WEDGE_SECS=120          # a healthy run journals its `session` line in <1s; 120s = safe wedge cutoff
HARD_TIMEOUT=5400       # 90-min backstop for a run that wedges AFTER init (rare)
wt="../opensas-pi-$dev"

[ "$stagger" -gt 0 ] 2>/dev/null && { echo "[dispatch] pi-$dev staggering ${stagger}s"; sleep "$stagger"; }

# Charter default (role delta) if the manager didn't pre-write /tmp/pi-charter.txt.
if [ ! -s "$CHARTER" ]; then
  cat > "$CHARTER" <<'CH'
You are a pi/Kimi DEV in an ISOLATED git worktree — alone, no collision risk, but you own
ONLY the src file(s) named in the task. Do the task; ship a runnable check (in-file `test`
or a tests/corpus/*.sas + expected .txt, output verified against the built binary). zig is
at ~/.local/bin/zig. Before reporting, run `zig build test && zig build corpus && zig build
programs` and get all three green. Commit LOCALLY by explicit pathspec
(git commit <your files> -m "<dev>: DONE <ID> — one line") — NEVER git add -A, NEVER push.
Report the commit sha + the three suite counts, then stop.
CH
fi

# Worktree (idempotent — ok if it already exists).
git worktree add "$wt" "$base" >/dev/null 2>&1 || true
cd "$wt" || { echo "pi-$dev: cannot cd $wt"; exit 3; }

stamp="/tmp/pi-$dev.launch"; : > "$stamp"    # mtime marker so the watchdog only sees THIS run's log

# Launch pi (hard-timeout wrapped) in the background; capture its PID.
timeout "$HARD_TIMEOUT" "$PI" -p -a \
  --provider kimi-coding --model k3 \
  --session-id "$sid" \
  --append-system-prompt "$(cat "$CHARTER")" \
  "$(cat "$promptfile")" &
pid=$!

# Watchdog: at WEDGE_SECS, if no session .jsonl for this sid was written after launch, the
# run is wedged at session-init (black-hole) — kill it so the manager reclaims + relaunches now.
(
  sleep "$WEDGE_SECS"
  if ! find ~/.pi/agent/sessions -name "*${sid}*.jsonl" -newer "$stamp" 2>/dev/null | grep -q .; then
    echo "[watchdog] pi-$dev WEDGED — no session .jsonl ${WEDGE_SECS}s after launch (session-init black-hole); killing" >&2
    kill -TERM "$pid" 2>/dev/null; sleep 3; kill -KILL "$pid" 2>/dev/null
  fi
) &
wdog=$!

wait "$pid"; rc=$?
kill "$wdog" 2>/dev/null   # cancel watchdog if pi finished on its own
[ "$rc" = 124 ] && echo "pi-$dev: HARD TIMEOUT (${HARD_TIMEOUT}s)"
echo "pi-$dev exit=$rc"
exit "$rc"
