. "$LAB_LIB"
f=.gitignore
[ -f "$f" ] || f="$LAB_HOME/.gitignore"
[ -f "$f" ] || fail ".gitignore does not exist."
grep -Fq '*.tfstate' "$f" || fail '.gitignore should include *.tfstate.'
grep -Fq '*.tfstate.*' "$f" || fail '.gitignore should include *.tfstate.*.'
grep -Fq '*.tfvars' "$f" || fail '.gitignore should include *.tfvars.'
