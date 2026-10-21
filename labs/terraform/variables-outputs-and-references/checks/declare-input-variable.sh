. "$LAB_LIB"
[ -f infra/variables.tf ] || fail "infra/variables.tf does not exist yet."
v=$(hcl_strip infra/variables.tf | hcl_block 'variable[[:space:]]+"environment"') || fail 'infra/variables.tf has no variable "environment".'
[ "$(printf '%s\n' "$v" | hcl_attr type)" = 'string' ] || fail "The variable should have type string."
[ "$(printf '%s\n' "$v" | hcl_attr description)" = '"Targetdeploymentenvironment"' ] || fail "Describe the variable with the description from the task."
[ "$(printf '%s\n' "$v" | hcl_attr default)" = '"dev"' ] || fail "Give the variable a default of dev."
