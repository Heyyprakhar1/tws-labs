. "$LAB_LIB"
[ -d "$LAB_HOME/infra" ] || fail "Directory infra does not exist yet."
[ "$(shell_cwd)" = "$LAB_HOME/infra" ] || fail "Move into the infra directory with cd infra."
