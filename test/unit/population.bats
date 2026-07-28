#!/usr/bin/env bats

load '../../support/bats-support/load'
load '../../support/bats-assert/load'

BETTEROPTS="$BATS_TEST_DIRNAME/../../betteropts.sh"

setup() {
  source "$BETTEROPTS"
}

@test "flag populates true when provided" {
  flag verbose -v --verbose
  _bo_parse -v
  _bo_assign_positionals
  _bo_populate
  assert_equal "$verbose" "true"
}

@test "flag populates false when not provided" {
  flag verbose -v --verbose
  _bo_parse
  _bo_assign_positionals
  _bo_populate
  assert_equal "$verbose" "false"
}

@test "option populates its value under the declared name" {
  option output -o --output PATH
  _bo_parse --output /tmp/out
  _bo_assign_positionals
  _bo_populate
  assert_equal "$output" "/tmp/out"
}

@test "option var= overrides the populated variable name" {
  option output -o --output PATH var=build_dir
  _bo_parse --output /tmp/out
  _bo_assign_positionals
  _bo_populate
  assert_equal "$build_dir" "/tmp/out"
}

@test "argument populates its value under the declared name" {
  argument source required
  _bo_parse /tmp/src
  _bo_assign_positionals
  _bo_populate
  assert_equal "$source" "/tmp/src"
}

@test "argument var= overrides the populated variable name" {
  argument source required var=input_dir
  _bo_parse /tmp/src
  _bo_assign_positionals
  _bo_populate
  assert_equal "$input_dir" "/tmp/src"
}

@test "optional argument populates empty when omitted" {
  argument destination optional
  _bo_parse
  _bo_assign_positionals
  _bo_populate
  assert_equal "${destination:-}" ""
}

@test "variadic argument populates a bash array" {
  argument files variadic
  _bo_parse a b c
  _bo_assign_positionals
  _bo_populate
  assert_equal "${#files[@]}" "3"
  assert_equal "${files[0]}" "a"
  assert_equal "${files[1]}" "b"
  assert_equal "${files[2]}" "c"
}

@test "variadic argument populates an empty array when no values given" {
  argument files variadic
  _bo_parse
  _bo_assign_positionals
  _bo_populate
  assert_equal "${#files[@]}" "0"
}

@test "populated scalar variables are not exported" {
  option output -o --output PATH
  _bo_parse --output /tmp/out
  _bo_assign_positionals
  _bo_populate
  run bash -c 'echo "${output:-unset}"'
  assert_output "unset"
}

@test "population is not shadowed by an internal local variable of the same name" {
  # _bo_populate's own implementation uses local loop variables (e.g. "name",
  # "var", "value"); a CLI author is free to name their own option/argument
  # the same thing. Regression test for that exact collision.
  option name -n --name VALUE
  _bo_parse --name custom
  _bo_assign_positionals
  _bo_populate
  assert_equal "$name" "custom"
}
