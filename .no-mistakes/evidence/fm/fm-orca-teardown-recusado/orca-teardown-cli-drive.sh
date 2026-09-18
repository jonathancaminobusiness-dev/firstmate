#!/usr/bin/env bash
# Manual end-to-end driver: tears down a real Orca-backed Firstmate task through
# bin/fm-teardown.sh, with a fake `orca` CLI on PATH that logs every invocation.
# The task metadata carries the id shape Orca really produces:
#   orca_worktree_id=<uuid>::<absolute worktree path>
set -u
ROOT=${ROOT:?ROOT=<firstmate worktree>}
. "$ROOT/tests/lib.sh"
LABEL=${LABEL:-run}
TMP_ROOT=$(fm_test_tmproot "orca-teardown-drive-$LABEL")
UUID=e5d1f72a-8900-4f46-aed7-b9f49673674b

id="orcateardowndemo"
proj="$TMP_ROOT/project"; wt="$TMP_ROOT/orca/workspaces/ig-reels-gen/fm-$id"
data="$TMP_ROOT/data"; state="$TMP_ROOT/state"; config="$TMP_ROOT/config"
fb="$TMP_ROOT/fakebin"; RESP="$TMP_ROOT/responses"; LOG="$TMP_ROOT/orca.log"
mkdir -p "$fb" "$RESP" "$data/$id" "$state" "$config" "$(dirname "$wt")"
: > "$LOG"
fm_git_worktree "$proj" "$wt" "fm/$id"
printf 'report\n' > "$data/$id/report.md"
touch "$state/.last-watcher-beat"

EMBEDDED=${EMBEDDED:-$wt}
fm_write_meta "$state/$id.meta" \
  "window=fm-$id" "endpoint_task_id=$id" "terminal=term-reels-7" "worktree=$wt" "project=$proj" \
  "harness=claude" "kind=scout" "mode=no-mistakes" "yolo=off" \
  "backend=orca" "orca_worktree_id=$UUID::$EMBEDDED" \
  "decisions_reviewed=1" "decision_keys="

cat > "$fb/orca" <<'SH'
#!/usr/bin/env bash
set -u
{ printf '$ orca'; for a in "$@"; do printf ' %q' "$a"; done; printf '\n'; } >> "${FM_ORCA_LOG:?}"
RESP="${FM_ORCA_RESPONSES:?}"; COUNT_FILE="$RESP/.count"
next=$(( $(cat "$COUNT_FILE" 2>/dev/null || echo 0) + 1 ))
if [ "${1:-}" = status ]; then
  printf '{"ok":true,"result":{"runtime":{"reachable":true,"state":"ready"}}}\n'; exit 0
fi
echo "$next" > "$COUNT_FILE"
[ -f "$RESP/$next.out" ] && cat "$RESP/$next.out"
exit 0
SH
chmod +x "$fb/orca"
printf '{"ok":true,"result":{"worktree":{"id":"%s::%s","path":"%s"}}}\n' "$UUID" "$wt" "$wt" > "$RESP/1.out"

neutral="$TMP_ROOT/neutral-root"; mkdir -p "$neutral/bin"
printf '#!/usr/bin/env bash\nexit 0\n' > "$neutral/bin/fm-guard.sh"; chmod +x "$neutral/bin/fm-guard.sh"

echo "### task metadata as recorded by fm-spawn (backend=orca)"
grep -E '^(backend|window|terminal|worktree|orca_worktree_id)=' "$state/$id.meta"
echo
echo "### \$ bin/fm-teardown.sh $id ${TEARDOWN_ARGS:-}"
set +e
PATH="$fb:$PATH" FM_ORCA_LOG="$LOG" FM_ORCA_RESPONSES="$RESP" \
  FM_ROOT_OVERRIDE="$neutral" FM_STATE_OVERRIDE="$state" FM_DATA_OVERRIDE="$data" FM_CONFIG_OVERRIDE="$config" \
  "$ROOT/bin/fm-teardown.sh" "$id" ${TEARDOWN_ARGS:-} 2>&1
rc=$?
set -e
echo "exit status: $rc"
echo
echo "### real orca CLI calls fm-teardown.sh made"
cat "$LOG"
echo
echo "### task metadata after teardown"
if [ -e "$state/$id.meta" ]; then echo "STILL PRESENT: $id.meta (task state preserved)"; else echo "REMOVED: $id.meta (task closed out)"; fi
echo "### worktree directory after teardown"
if [ -d "$wt" ]; then echo "STILL PRESENT: $wt"; else echo "REMOVED: $wt"; fi
