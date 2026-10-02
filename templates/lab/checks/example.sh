# Exit 0 = pass. First line printed = message shown on failure (a nudge, never the answer).
# Prefer checking real state; see checks/lib.sh for helpers (ran, file_has, shell_cwd, proc_running, in_repo).
. "$LAB_LIB"
[ -f hello.txt ] || fail "hello.txt does not exist yet."
