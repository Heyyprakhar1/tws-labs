. "$LAB_LIB"
# One line holding both settings, in any order and with any spacing.
conf_ok() { [ "$(printf '%s\n' "$1" | grep -c .)" = 1 ] && [ "$(printf '%s\n' "$1" | tr -s ' \t' '\n\n' | grep . | sort | paste -sd' ' -)" = "LOG_LEVEL=debug PORT=8080" ]; }
[ "$(in_repo proj branch --show-current)" = "main" ] || fail "Switch to main before continuing."
in_repo proj rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1 || fail "Start the merge of feature into main; it must still be in progress."
[ "$(in_repo proj rev-parse MERGE_HEAD)" = "$(in_repo proj rev-parse feature-start)" ] || fail "Merge the original feature branch into main."
conf_ok "$(cat "$LAB_HOME/proj/app.conf" 2>/dev/null)" || fail "Resolve app.conf with one line that preserves both branch changes and removes all conflict markers."
[ -z "$(in_repo proj ls-files -u)" ] || fail "Git still has unmerged entries: stage your resolved app.conf."
conf_ok "$(in_repo proj show :app.conf 2>/dev/null)" || fail "Stage the resolved app.conf with both branch changes."
