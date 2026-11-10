#!/bin/bash
set -euo pipefail

BASE="${LAB_HOME:-$HOME}"
"$BASE/dns-incident/bin/validate-resolution"
