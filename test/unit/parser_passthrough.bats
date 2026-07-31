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

@test "an unrecognized flag-like token starts passthrough capture" {
  _bo_parse --author foo --stat -M
  _bo_assign_positionals
  assert_equal "${_bo_raw[author]}" "foo"
  assert_equal "${_bo_passthrough_values[0]}" "--stat"
  assert_equal "${_bo_passthrough_values[1]}" "-M"
}

@test "declared options before the passthrough boundary still parse normally" {
  _bo_parse -a foo bar --stat
  _bo_assign_positionals
  assert_equal "${_bo_raw[author]}" "foo"
  assert_equal "${_bo_passthrough_values[0]}" "bar"
  assert_equal "${_bo_passthrough_values[1]}" "--stat"
}

@test "no unknown option error is raised past the passthrough boundary" {
  run _bo_parse --whatever -x
  assert_success
}

@test "a passthrough argument collects zero tokens when nothing follows" {
  _bo_parse --author foo
  _bo_assign_positionals
  assert_equal "${#_bo_passthrough_values[@]}" "0"
}
