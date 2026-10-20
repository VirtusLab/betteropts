#!/usr/bin/env bats
load '../../support/bats-support/load'
load '../../support/bats-assert/load'
set -euo pipefail
FIXTURE="$BATS_TEST_DIRNAME/../fixtures/equals_fields"

@test "public equals parsing covers every spelling repeated keys and literal extra equals" {
  run "$FIXTURE" --set kind=topic -s kind=test --set=axis=with=equals --verbose input
  assert_success
  assert_line count=3
  assert_line key=kind
  assert_line value=with=equals
  assert_line verbose=true
  assert_line file=input
}

@test "public equals parsing rejects spaced fields and validates decoded fields" {
  run "$FIXTURE" --set kind topic
  assert_failure
  assert_output --partial 'expected KEY=VALUE'
  run "$FIXTURE" --set unknown=topic
  assert_failure
  assert_output --partial '--set KEY unknown'
  run "$FIXTURE" --set kind=unknown
  assert_failure
  assert_output --partial '--set VALUE unknown'
}

@test "public pair syntax in help and usage agrees with the parser" {
  run "$FIXTURE" --usage
  assert_success
  assert_line 'equals_fields [--set KEY=VALUE]... [--verbose] [FILE]'
  run "$FIXTURE" --help
  assert_success
  # shellcheck disable=SC2016
  assert_line '-s, --set KEY=VALUE (repeatable, KEY choices: kind, axis, VALUE choices: topic, test, value with spaces, with=equals, shell;$(false)*, scheme:value, =leading)'
}

@test "public pair completion uses whole tokens and adapter mode adds context" {
  run "$FIXTURE" --__complete -- --set k
  assert_success
  assert_output kind=
  run "$FIXTURE" --__complete -- --set=kind=to
  assert_output --set=kind=topic
  run "$FIXTURE" --__complete --bash -- --set kind=to
  assert_output $'pair\nkind=topic'
  run "$FIXTURE" --__complete --bash -- --set kind=nope
  assert_success
  assert_output pair
  run "$FIXTURE" --__complete --bash -- --ver
  assert_output $'plain\n--verbose'
  run "$FIXTURE" --__complete --bash -- --unknown x
  assert_output ''
}

@test "equals tokens keep builtin prescan semantics without splitting their fields" {
  run "$FIXTURE" --set kind=--help
  assert_failure
  assert_output --partial '--set VALUE --help'
  run "$FIXTURE" --set --help
  assert_failure 1
  assert_output --partial "'--help' must be used alone"
  run "$FIXTURE" --set kind=topic -- --help
  assert_success
  assert_line file=--help
}
