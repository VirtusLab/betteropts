#!/usr/bin/env bats

load '../../support/bats-support/load'
load '../../support/bats-assert/load'

set -euo pipefail

BETTEROPTS="$BATS_TEST_DIRNAME/../../betteropts.sh"

compat_cli() {
  bash -c '
    source "$1"
    shift
    summary "Compatibility sample"
    description "Detailed description"
    option item --item VALUE required
    argument extra passthrough
    betteropts_parse "$@"
    printf "item=%s\n" "$item"
    printf "extra=%s\n" "${extra[*]}"
  ' compat "$BETTEROPTS" "$@"
}

@test "C24 builtins bypass missing requirements errors and passthrough boundaries before literal double dash" {
  local builtin
  for builtin in -h --help --usage; do
    run compat_cli --unknown "$builtin"
    assert_success
    assert_output --partial 'Usage:'
    run compat_cli --item "$builtin"
    assert_success
    assert_output --partial 'Usage:'
  done
  run compat_cli --item value -- --help
  assert_success
  assert_output $'item=value\nextra=-- --help'
}

@test "C25 schema rejection takes precedence over every builtin" {
  local builtin
  for builtin in --help --usage --__complete; do
    run bash -c '
      source "$1"
      option item --item multi default=1
      betteropts_parse "$2"
    ' compat "$BETTEROPTS" "$builtin"
    assert_failure
    assert_output 'A multi option cannot declare a default.'
  done
}

@test "C26 first help or usage token wins and completion is special only in argv one" {
  run compat_cli --usage --help
  assert_success
  refute_output --partial 'Detailed description'
  run compat_cli --help --usage
  assert_success
  assert_output --partial 'Detailed description'
  run compat_cli --__complete -- --it
  assert_success
  assert_output --item
  run compat_cli --item value --__complete
  assert_success
  assert_output $'item=value\nextra=--__complete'
  run compat_cli --__complete --help
  assert_success
  assert_output --partial 'Detailed description'
}

@test "C27 reserved aliases are accepted declarations but their builtin takes precedence" {
  run bash -c '
    source "$1"
    flag custom --help
    betteropts_parse --help
    printf "custom=%s\n" "$custom"
  ' compat "$BETTEROPTS"
  assert_success
  assert_output --partial 'Show this help'
  refute_output --partial custom=true
}
