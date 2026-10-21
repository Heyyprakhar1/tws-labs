. "$LAB_LIB"
[ -f infra/main.tf ] || fail "infra/main.tf does not exist yet."
res=$(hcl_strip infra/main.tf | hcl_block 'resource[[:space:]]+"local_file"[[:space:]]+"welcome"') || fail 'infra/main.tf has no local_file resource named welcome.'
[ "$(printf '%s\n' "$res" | hcl_attr file_permission)" = '"0644"' ] || fail "Set file_permission inside the welcome resource to the four-digit mode from the task, as a quoted string."
