# Helpers for lab check scripts. Source it first:   . "$LAB_LIB"
#
# Environment provided by the server (and by `npm run lab:validate`):
#   LAB_HOME        the learner's home directory (also $HOME, also the cwd)
#   LAB_SHELL_PID   pid of the learner's shell (also its Linux session id)
#   LAB_HISTORY     file with the learner's Enter-submitted command lines
#
# A check exits 0 to pass. Anything printed on its first line is shown to the
# learner when it fails - make it a useful nudge, never the answer.
# Prefer checking real state (files, git, processes). Use `ran` only when
# there is no state to inspect (e.g. "run ls -l").

fail() { echo "$*"; exit 1; }

# ran CMD : the learner ran CMD as a command (not merely typed the word in `echo CMD`)
ran() { grep -Eq "(^|[;&|(][[:space:]]*)$1([[:space:]]|\$|[;&|)])" "$LAB_HISTORY" 2>/dev/null; }

# ran_re REGEX : some submitted line matches the extended regex
ran_re() { grep -Eq -- "$1" "$LAB_HISTORY" 2>/dev/null; }

# file_has PATH REGEX : PATH exists and has a line matching REGEX
file_has() { [ -f "$1" ] && grep -Eq -- "$2" "$1"; }

# shell_cwd : the learner's shell's current directory right now
shell_cwd() { readlink "/proc/$LAB_SHELL_PID/cwd" 2>/dev/null; }

# proc_running NAME : a process called NAME is alive in the learner's shell session
# (zombies are already dead - waiting for their parent to reap them - so they do not count)
proc_running() { ps -s "$LAB_SHELL_PID" -o stat=,comm= 2>/dev/null | awk -v n="$1" '$1 !~ /^Z/ && $2 == n { f = 1 } END { exit !f }'; }

# in_repo DIR git-args... : run git inside $LAB_HOME/DIR
in_repo() { local d="$1"; shift; git -C "$LAB_HOME/$d" "$@"; }
