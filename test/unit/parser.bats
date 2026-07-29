#!/usr/bin/env bats

load '../../support/bats-support/load'
load '../../support/bats-assert/load'

set -euo pipefail

BETTEROPTS="$BATS_TEST_DIRNAME/../../betteropts.sh"

setup() {
  # shellcheck source=../../betteropts.sh
  source "$BETTEROPTS"
  flag verbose -v --verbose
  flag force -f --force
  option output -o --output PATH
  option jobs -j --jobs N
  argument source required
  argument destination optional
}

@test "long flag is marked provided" {
  _bo_parse --verbose
  assert_equal "${_bo_provided[verbose]:-}" "true"
}

@test "short flag is marked provided" {
  _bo_parse -v
  assert_equal "${_bo_provided[verbose]:-}" "true"
}

@test "flag not passed is not marked provided" {
  _bo_parse
  assert_equal "${_bo_provided[verbose]:-}" ""
}

@test "repeated flag stays provided" {
  _bo_parse -v -v
  assert_equal "${_bo_provided[verbose]:-}" "true"
}

@test "option accepts a separate value (short form)" {
  _bo_parse -o /tmp
  assert_equal "${_bo_raw[output]}" "/tmp"
}

@test "option accepts a separate value (long form)" {
  _bo_parse --output /tmp
  assert_equal "${_bo_raw[output]}" "/tmp"
}

@test "option accepts --name=value form" {
  _bo_parse --output=/tmp
  assert_equal "${_bo_raw[output]}" "/tmp"
}

@test "-o=value form is rejected as an unknown option" {
  run _bo_parse -o=/tmp
  assert_failure
  assert_output "Unknown option:

-o=/tmp

Use --help for usage."
}

@test "an unknown long option is rejected" {
  run _bo_parse --verboes
  assert_failure
  assert_output "Unknown option:

--verboes

Use --help for usage."
}

@test "an unknown short option is rejected" {
  run _bo_parse -x
  assert_failure
  assert_output "Unknown option:

-x

Use --help for usage."
}

@test "a missing option value is rejected" {
  run _bo_parse --output
  assert_failure
  assert_output "Missing value:

--output"
}

@test "-- stops option parsing; remaining tokens are positional" {
  _bo_parse -- --verbose foo
  assert_equal "${_bo_provided[verbose]:-}" ""
  assert_equal "${_bo_positional_tokens[0]}" "--verbose"
  assert_equal "${_bo_positional_tokens[1]}" "foo"
}

@test "positional tokens are collected in order" {
  _bo_parse --output /tmp src dst
  assert_equal "${_bo_positional_tokens[0]}" "src"
  assert_equal "${_bo_positional_tokens[1]}" "dst"
}

@test "positional tokens are assigned to declared argument slots" {
  _bo_parse --output /tmp src dst
  _bo_assign_positionals
  assert_equal "${_bo_raw[source]}" "src"
  assert_equal "${_bo_raw[destination]}" "dst"
}

@test "an optional argument slot is left unset when omitted" {
  _bo_parse --output /tmp src
  _bo_assign_positionals
  assert_equal "${_bo_raw[source]}" "src"
  assert_equal "${_bo_raw[destination]:-}" ""
}

@test "an extra positional beyond declared slots is rejected" {
  _bo_parse --output /tmp src dst extra
  run _bo_assign_positionals
  assert_failure
  assert_output "Unexpected argument:

extra"
}

@test "a variadic argument collects all remaining positional tokens" {
  # shellcheck source=../../betteropts.sh
  source "$BETTEROPTS"
  argument source required
  argument files variadic
  _bo_parse src a b c
  _bo_assign_positionals
  assert_equal "${_bo_raw[source]}" "src"
  assert_equal "${_bo_variadic_values[0]}" "a"
  assert_equal "${_bo_variadic_values[1]}" "b"
  assert_equal "${_bo_variadic_values[2]}" "c"
}

@test "a variadic argument accepts zero values" {
  # shellcheck source=../../betteropts.sh
  source "$BETTEROPTS"
  argument source required
  argument files variadic
  _bo_parse src
  run _bo_assign_positionals
  assert_success
  assert_equal "${#_bo_variadic_values[@]}" "0"
}

@test "a repeated multi option accumulates values (long form)" {
  # shellcheck source=../../betteropts.sh
  source "$BETTEROPTS"
  option topic -t --topic VALUE multi
  _bo_parse --topic conflicts --topic builds
  assert_equal "${_bo_multi_count[topic]}" "2"
  assert_equal "${_bo_multi_values[topic.0]}" "conflicts"
  assert_equal "${_bo_multi_values[topic.1]}" "builds"
}

@test "a repeated multi option accumulates values (short form)" {
  # shellcheck source=../../betteropts.sh
  source "$BETTEROPTS"
  option topic -t --topic VALUE multi
  _bo_parse -t conflicts -t builds
  assert_equal "${_bo_multi_count[topic]}" "2"
  assert_equal "${_bo_multi_values[topic.0]}" "conflicts"
  assert_equal "${_bo_multi_values[topic.1]}" "builds"
}

@test "a repeated multi option accumulates values (--name=value form)" {
  # shellcheck source=../../betteropts.sh
  source "$BETTEROPTS"
  option topic -t --topic VALUE multi
  _bo_parse --topic=conflicts --topic=builds
  assert_equal "${_bo_multi_count[topic]}" "2"
  assert_equal "${_bo_multi_values[topic.0]}" "conflicts"
  assert_equal "${_bo_multi_values[topic.1]}" "builds"
}

@test "a multi option accumulates values across mixed forms in order" {
  # shellcheck source=../../betteropts.sh
  source "$BETTEROPTS"
  option topic -t --topic VALUE multi
  _bo_parse -t conflicts --topic=builds --topic tests
  assert_equal "${_bo_multi_count[topic]}" "3"
  assert_equal "${_bo_multi_values[topic.0]}" "conflicts"
  assert_equal "${_bo_multi_values[topic.1]}" "builds"
  assert_equal "${_bo_multi_values[topic.2]}" "tests"
}

@test "a multi option marks provided true like any other option" {
  # shellcheck source=../../betteropts.sh
  source "$BETTEROPTS"
  option topic -t --topic VALUE multi
  _bo_parse -t conflicts
  assert_equal "${_bo_provided[topic]:-}" "true"
}

@test "a non-multi option still overwrites on repeat" {
  _bo_parse --output /tmp/a --output /tmp/b
  assert_equal "${_bo_raw[output]}" "/tmp/b"
}
