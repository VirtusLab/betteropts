#!/usr/bin/env bash
# Runs all BATS tests (unit + integration).
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
exec support/bats/bin/bats --recursive test/unit test/integration
