#!/usr/bin/env bats

load '../../support/bats-support/load'
load '../../support/bats-assert/load'

set -euo pipefail

BETTEROPTS="$BATS_TEST_DIRNAME/../../betteropts.sh"

setup() {
  # shellcheck source=../../betteropts.sh
  source "$BETTEROPTS"
  option topic -t --topic VALUE multi
}

@test "a repeated multi option accumulates values (long form)" {
  _bo_parse --topic conflicts --topic builds
  assert_equal "${_bo_multi_count[topic]}" "2"
  assert_equal "${_bo_multi_values[topic.0]}" "conflicts"
  assert_equal "${_bo_multi_values[topic.1]}" "builds"
}

@test "a repeated multi option accumulates values (short form)" {
  _bo_parse -t conflicts -t builds
  assert_equal "${_bo_multi_count[topic]}" "2"
  assert_equal "${_bo_multi_values[topic.0]}" "conflicts"
  assert_equal "${_bo_multi_values[topic.1]}" "builds"
}

@test "a repeated multi option accumulates values (--name=value form)" {
  _bo_parse --topic=conflicts --topic=builds
  assert_equal "${_bo_multi_count[topic]}" "2"
  assert_equal "${_bo_multi_values[topic.0]}" "conflicts"
  assert_equal "${_bo_multi_values[topic.1]}" "builds"
}

@test "a multi option accumulates values across mixed forms in order" {
  _bo_parse -t conflicts --topic=builds --topic tests
  assert_equal "${_bo_multi_count[topic]}" "3"
  assert_equal "${_bo_multi_values[topic.0]}" "conflicts"
  assert_equal "${_bo_multi_values[topic.1]}" "builds"
  assert_equal "${_bo_multi_values[topic.2]}" "tests"
}

@test "a multi option marks provided true like any other option" {
  _bo_parse -t conflicts
  assert_equal "${_bo_provided[topic]:-}" "true"
}
