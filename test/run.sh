#!/usr/bin/env bash
# Runs all BATS tests (unit + integration).
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
# shellcheck disable=SC2086
exec support/bats/bin/bats ${BATS_OPTS:-} --recursive test/unit test/integration
