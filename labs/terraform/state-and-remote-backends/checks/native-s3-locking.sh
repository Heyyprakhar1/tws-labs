. "$LAB_LIB"
f=infra/backend.tf
[ -f "$f" ] || f="$LAB_HOME/infra/backend.tf"
[ -f "$f" ] || fail "infra/backend.tf does not exist."
grep -Eq 'use_lockfile[[:space:]]*=[[:space:]]*true' "$f" || fail 'Add use_lockfile = true inside the backend "s3" block.'
