#!/usr/bin/env bats

load '../../support/bats-support/load'
load '../../support/bats-assert/load'

set -euo pipefail

BETTEROPTS="$BATS_TEST_DIRNAME/../../betteropts.sh"

setup() {
  # shellcheck source=../../betteropts.sh
  source "$BETTEROPTS"
  argument source required
  argument files variadic
}

@test "a variadic argument collects all remaining positional tokens" {
  _bo_parse src a b c
  _bo_assign_positionals
  assert_equal "${_bo_raw[source]}" "src"
  assert_equal "${_bo_variadic_values[0]}" "a"
  assert_equal "${_bo_variadic_values[1]}" "b"
  assert_equal "${_bo_variadic_values[2]}" "c"
}

@test "a variadic argument accepts zero values" {
  _bo_parse src
  run _bo_assign_positionals
  assert_success
  assert_equal "${#_bo_variadic_values[@]}" "0"
}
