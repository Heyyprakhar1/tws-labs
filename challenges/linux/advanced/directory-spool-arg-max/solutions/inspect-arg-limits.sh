BASE="$HOME/spool-incident"
mkdir -p "$BASE/reports"

AMAX=$(getconf ARG_MAX)
NMAX=$(getconf NAME_MAX "$BASE/var/spool")
SAMPLE_FILE=$(ls -1 "$BASE/var/spool" | head -n1)
if [ -n "$SAMPLE_FILE" ]; then
  FLEN=${#SAMPLE_FILE}
else
  FLEN="245"
fi

cat << EOF > "$BASE/reports/arg-limits.env"
SYSTEM_ARG_MAX=$AMAX
SYSTEM_NAME_MAX=$NMAX
SAMPLE_FILENAME_LENGTH=$FLEN
FAILING_ERRNO=E2BIG
KERNEL_LIMIT_TYPE=ARG_MAX
EOF
