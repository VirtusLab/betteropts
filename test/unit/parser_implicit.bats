#!/usr/bin/env bats

load '../../support/bats-support/load'
load '../../support/bats-assert/load'

set -euo pipefail

BETTEROPTS="$BATS_TEST_DIRNAME/../../betteropts.sh"

setup() {
  # shellcheck source=../../betteropts.sh
  source "$BETTEROPTS"
  option notes --notes REF multi implicit=refs/notes/commits
  option mode -m --mode VALUE implicit=on
}

@test "a bare long-form implicit option substitutes its implicit value" {
  _bo_parse --notes
  assert_equal "${_bo_multi_count[notes]}" "1"
  assert_equal "${_bo_multi_values[notes.0]}" "refs/notes/commits"
}

@test "a bare short-form implicit option substitutes its implicit value" {
  _bo_parse -m
  assert_equal "${_bo_raw[mode]}" "on"
}

@test "an explicit --name=value still attaches, even with implicit= declared" {
  _bo_parse --notes=refs/notes/other
  assert_equal "${_bo_multi_count[notes]}" "1"
  assert_equal "${_bo_multi_values[notes.0]}" "refs/notes/other"
}

@test "mixed bare and explicit occurrences accumulate in order" {
  _bo_parse --notes --notes=refs/notes/other --notes
  assert_equal "${_bo_multi_count[notes]}" "3"
  assert_equal "${_bo_multi_values[notes.0]}" "refs/notes/commits"
  assert_equal "${_bo_multi_values[notes.1]}" "refs/notes/other"
  assert_equal "${_bo_multi_values[notes.2]}" "refs/notes/commits"
}

@test "a bare implicit option marks provided true like any other option" {
  _bo_parse --notes
  assert_equal "${_bo_provided[notes]:-}" "true"
}

@test "a bare implicit option does not consume the following token" {
  _bo_parse --notes foo
  assert_equal "${_bo_multi_count[notes]}" "1"
  assert_equal "${_bo_multi_values[notes.0]}" "refs/notes/commits"
  assert_equal "${_bo_positional_tokens[0]}" "foo"
}

@test "a bare implicit option at the very end of argv does not error" {
  run _bo_parse --notes
  assert_success
}
