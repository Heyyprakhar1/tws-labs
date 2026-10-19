. "$LAB_LIB"
b=infra/backend.tf
[ -f "$b" ] || b="$LAB_HOME/infra/backend.tf"
[ -f "$b" ] || fail "infra/backend.tf does not exist."
grep -Eq 'use_lockfile[[:space:]]*=[[:space:]]*true' "$b" || fail 'Add use_lockfile = true to backend "s3" in infra/backend.tf.'

g=.gitignore
[ -f "$g" ] || g="$LAB_HOME/.gitignore"
[ -f "$g" ] || fail ".gitignore does not exist."
grep -Fq '*.tfstate' "$g" || fail '.gitignore should include *.tfstate.'
grep -Fq '*.tfstate.*' "$g" || fail '.gitignore should include *.tfstate.*.'
grep -Fq '*.tfvars' "$g" || fail '.gitignore should include *.tfvars.'
