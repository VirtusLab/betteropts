#!/usr/bin/env bats

load '../../support/bats-support/load'
load '../../support/bats-assert/load'

set -euo pipefail

BETTEROPTS="$BATS_TEST_DIRNAME/../../betteropts.sh"

setup() {
  # shellcheck source=../../betteropts.sh
  source "$BETTEROPTS"
  option author -a --author VALUE
  argument extra passthrough
}

@test "offers nothing once past the passthrough boundary" {
  run _bo_complete -- --author alice --stat -
  assert_success
  assert_output ""
}

@test "offers nothing for a passthrough argument's own positional slot" {
  run _bo_complete -- ""
  assert_success
  assert_output ""
}

@test "declared options still complete before the passthrough boundary" {
  run _bo_complete -- --aut
  assert_success
  assert_output --partial "--author"
}
