#!/usr/bin/env bats

load '../../support/bats-support/load'
load '../../support/bats-assert/load'

set -euo pipefail

BETTEROPTS="$BATS_TEST_DIRNAME/../../betteropts.sh"

setup() {
  # shellcheck source=../../betteropts.sh
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

@test "required arguments fill first, then optional, then variadic gets the remainder" {
  # features/09-argument-ordering.md: with the required*optional*(variadic|
  # passthrough)? ordering now enforced by _bo_finalize_schema, the existing
  # greedy assignment in _bo_assign_positionals is unambiguous.
  argument source required
  argument destination optional
  argument files variadic
  _bo_parse a b c d
  _bo_assign_positionals
  _bo_populate
  assert_equal "$source" "a"
  assert_equal "$destination" "b"
  assert_equal "${#files[@]}" "2"
  assert_equal "${files[0]}" "c"
  assert_equal "${files[1]}" "d"
}

@test "an optional argument before a variadic argument claims the first token, leaving variadic empty" {
  # Locks in features/09-argument-ordering.md's claim that a trailing
  # variadic argument can never receive a token while an earlier optional
  # argument goes unfulfilled: _bo_assign_positionals walks arguments with a
  # single strictly-increasing index, so the earlier-declared optional
  # argument always gets first claim on any available token.
  argument destination optional
  argument files variadic
  _bo_parse foo
  _bo_assign_positionals
  _bo_populate
  assert_equal "$destination" "foo"
  assert_equal "${#files[@]}" "0"
}

@test "an optional argument before a passthrough argument claims the first token, even a flag-shaped one" {
  # Same guarantee as above, extended to passthrough: the optional argument
  # wins the first token even when it looks like a flag meant for the
  # passthrough tail.
  argument mode optional
  argument extra passthrough
  _bo_parse --stat
  _bo_assign_positionals
  _bo_populate
  assert_equal "$mode" "--stat"
  assert_equal "${#extra[@]}" "0"
}

@test "optional argument populates its default when omitted" {
  argument commit optional default=HEAD
  _bo_parse
  _bo_assign_positionals
  _bo_apply_defaults
  _bo_populate
  assert_equal "$commit" "HEAD"
}

@test "optional argument populates the given value over its default" {
  argument commit optional default=HEAD
  _bo_parse abc123
  _bo_assign_positionals
  _bo_apply_defaults
  _bo_populate
  assert_equal "$commit" "abc123"
}

@test "variadic argument populates its default (single value) when omitted" {
  argument folders variadic default=.
  _bo_parse
  _bo_assign_positionals
  _bo_apply_defaults
  _bo_populate
  assert_equal "${#folders[@]}" "1"
  assert_equal "${folders[0]}" "."
}

@test "variadic argument populates its comma-split default when omitted" {
  argument reviewers variadic default=alice,bob
  _bo_parse
  _bo_assign_positionals
  _bo_apply_defaults
  _bo_populate
  assert_equal "${#reviewers[@]}" "2"
  assert_equal "${reviewers[0]}" "alice"
  assert_equal "${reviewers[1]}" "bob"
}

@test "variadic argument populates given values over its default" {
  argument reviewers variadic default=alice,bob
  _bo_parse carol dave
  _bo_assign_positionals
  _bo_apply_defaults
  _bo_populate
  assert_equal "${#reviewers[@]}" "2"
  assert_equal "${reviewers[0]}" "carol"
  assert_equal "${reviewers[1]}" "dave"
}

@test "multi option populates a bash array in the order given" {
  option topic -t --topic VALUE multi
  _bo_parse --topic conflicts --topic builds
  _bo_assign_positionals
  _bo_populate
  assert_equal "${#topic[@]}" "2"
  assert_equal "${topic[0]}" "conflicts"
  assert_equal "${topic[1]}" "builds"
}

@test "multi option populates an empty array with zero occurrences" {
  option topic -t --topic VALUE multi
  _bo_parse
  _bo_assign_positionals
  _bo_populate
  assert_equal "${#topic[@]}" "0"
}

@test "multi option var= overrides the populated variable name" {
  option topic -t --topic VALUE multi var=topics
  _bo_parse --topic conflicts
  _bo_assign_positionals
  _bo_populate
  assert_equal "${#topics[@]}" "1"
  assert_equal "${topics[0]}" "conflicts"
}

@test "populated scalar variables are not exported" {
  option output -o --output PATH
  _bo_parse --output /tmp/out
  _bo_assign_positionals
  _bo_populate
  run bash -c 'echo "${output:-unset}"'
  assert_output "unset"
}

@test "passthrough argument populates a bash array in order, including flag-shaped tokens" {
  option author -a --author VALUE
  argument extra passthrough
  _bo_parse --author foo bar --stat -M
  _bo_assign_positionals
  _bo_populate
  assert_equal "$author" "foo"
  assert_equal "${#extra[@]}" "3"
  assert_equal "${extra[0]}" "bar"
  assert_equal "${extra[1]}" "--stat"
  assert_equal "${extra[2]}" "-M"
}

@test "passthrough argument populates an empty array when nothing follows" {
  argument extra passthrough
  _bo_parse
  _bo_assign_positionals
  _bo_populate
  assert_equal "${#extra[@]}" "0"
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
