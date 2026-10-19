#!/usr/bin/env bats

load '../../support/bats-support/load'
load '../../support/bats-assert/load'

set -euo pipefail

FIXTURE="$BATS_TEST_DIRNAME/../fixtures/option_fields"

@test "fixed-arity records parse separate argv values and leave the following file positional" {
  run "$FIXTURE" --question Q-order high '§4.2, Table 3' -q Q-other low "O'Brien \\ ref" input
  assert_success
  assert_line count=2
  assert_line label=Q-order
  assert_line value=high
  assert_line 'passage=§4.2, Table 3'
  assert_line "passage=O'Brien \\ ref"
  assert_line file=input
}

@test "missing record fields exit before business logic" {
  run "$FIXTURE" --question Q-order high
  assert_failure
  assert_output $'Missing value:\n\n--question'
}

@test "bad record choices exit with a field identifier" {
  run "$FIXTURE" --question Q-order invalid passage
  assert_failure
  assert_output --partial '--question VALUE invalid'
}

@test "record usage and help are generated from the field schema" {
  run "$FIXTURE" --usage
  assert_success
  assert_line 'option_fields [--question LABEL VALUE PASSAGE]... [--verbose] [FILE]'
  run "$FIXTURE" --help
  assert_success
  assert_line '-q, --question LABEL VALUE PASSAGE (repeatable, VALUE choices: high, medium, low)'
}

@test "public completion selects field choices and resumes option names" {
  run "$FIXTURE" --__complete -- --question=Q-order m
  assert_success
  assert_output medium
  run "$FIXTURE" --__complete -- -q Q-order high passage --ver
  assert_success
  assert_output --verbose
}

@test "raw builtin scanning keeps help precedence even in a field slot" {
  run "$FIXTURE" --question Q-order high --help
  assert_success
  assert_line 'Options'
  refute_output --partial count=
}

@test "a -- field stops builtin scanning while record parsing resumes afterward" {
  run "$FIXTURE" --question -- high --help --verbose
  assert_success
  assert_line label=--
  assert_line passage=--help
  assert_line verbose=true
}

@test "an omitted repeated record populates empty arrays" {
  run "$FIXTURE"
  assert_success
  assert_line count=0
}
