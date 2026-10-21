# cwd: proj
set -eu
cd "$LAB_HOME/proj"
git merge feature >/dev/null 2>&1 || [ -f .git/MERGE_HEAD ]
if grep -qs '^<<<<<<< ' app.conf; then printf '%s\n' 'PORT=8080 LOG_LEVEL=debug' > app.conf; fi
git add app.conf
