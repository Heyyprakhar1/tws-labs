. "$LAB_LIB"
[ -f infra/main.tf ] || fail "infra/main.tf does not exist yet."
res=$(hcl_strip infra/main.tf | hcl_block 'resource[[:space:]]+"local_file"[[:space:]]+"welcome"') || fail 'infra/main.tf has no local_file resource named welcome.'
[ "$(printf '%s\n' "$res" | hcl_attr filename)" = '"welcome.txt"' ] || fail "The resource should write to welcome.txt."
[ "$(printf '%s\n' "$res" | hcl_attr content)" = '"InfrastructureasCodewithTerraform"' ] || fail "The resource content is not the sentence from the task."
