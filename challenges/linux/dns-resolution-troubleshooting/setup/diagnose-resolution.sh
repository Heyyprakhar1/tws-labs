#!/bin/bash
set -euo pipefail

BASE="${LAB_HOME:-$HOME}"
INCIDENT="$BASE/dns-incident"
rm -f "$INCIDENT/reports/resolution-triage.env"
