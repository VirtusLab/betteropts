#!/usr/bin/env bats

load '../../support/bats-support/load'
load '../../support/bats-assert/load'

set -euo pipefail

BETTEROPTS="$BATS_TEST_DIRNAME/../../betteropts.sh"

setup() {
  # shellcheck source=../../betteropts.sh
  source "$BETTEROPTS"
  option mode -m --mode MODE type=choice choices=fast,slow,auto
  option count -c --count N type=integer
  option config --config FILE type=file
  option output -o --output PATH type=directory
  option topic -t --topic VALUE multi type=choice choices=conflicts,builds,tests
  option base -b --base VALUE type=git-commitish
  option range -r --range VALUE type=git-range
  argument source required type=directory
}

@test "completes a choice option's value, filtered by prefix" {
  run _bo_complete -- --mode s
  assert_success
  assert_output "slow"
}

@test "lists every choice when the prefix is empty" {
  run _bo_complete -- --mode ""
  assert_success
  assert_line "fast"
  assert_line "slow"
  assert_line "auto"
}

@test "offers nothing for an integer option's value" {
  run _bo_complete -- --count ""
  assert_success
  assert_output ""
}

@test "completes option names by prefix, long and short" {
  run _bo_complete -- --mo
  assert_success
  assert_output --partial "--mode"
}

@test "never suggests --usage or --__complete as an option name" {
  run _bo_complete -- --
  refute_output --partial "--usage"
  refute_output --partial "--__complete"
}

@test "does suggest --help as an option name" {
  run _bo_complete -- --h
  assert_output --partial "--help"
}

@test "completes a file option's value from the filesystem" {
  cd "$BATS_TEST_TMPDIR"
  : > alpha.conf
  : > beta.conf
  mkdir -p somedir
  run _bo_complete -- --config ""
  assert_success
  assert_line "alpha.conf"
  assert_line "beta.conf"
}

@test "completes a directory option's value from the filesystem" {
  cd "$BATS_TEST_TMPDIR"
  mkdir -p dir-one dir-two
  : > not-a-dir.txt
  run _bo_complete -- --output ""
  assert_success
  assert_line "dir-one"
  assert_line "dir-two"
  refute_output --partial "not-a-dir.txt"
}

@test "completes a positional argument's value by its declared type" {
  cd "$BATS_TEST_TMPDIR"
  mkdir -p src-one src-two
  run _bo_complete -- ""
  assert_success
  assert_line "src-one"
  assert_line "src-two"
}

@test "offers nothing for a type=git-commitish option's value" {
  run _bo_complete -- --base ""
  assert_success
  assert_output ""
}

@test "offers nothing for a type=git-range option's value" {
  run _bo_complete -- --range ""
  assert_success
  assert_output ""
}

@test "a multi option offers the full choice list regardless of values already chosen" {
  run _bo_complete -- --topic conflicts --topic ""
  assert_success
  assert_line "conflicts"
  assert_line "builds"
  assert_line "tests"
}

@test "an earlier --opt=value token in the replay is skipped correctly" {
  run _bo_complete -- --mode=fast --mode ""
  assert_success
  assert_line "fast"
  assert_line "slow"
  assert_line "auto"
}

@test "an earlier short option token in the replay is resolved via _bo_find_by_short" {
  run _bo_complete -- -m fast --mode ""
  assert_success
  assert_line "fast"
  assert_line "slow"
  assert_line "auto"
}

@test "an earlier already-typed flag in the replay doesn't consume the next word as its value" {
  flag verbose -v --verbose
  run _bo_complete -- --verbose --mode ""
  assert_success
  assert_line "fast"
  assert_line "slow"
  assert_line "auto"
}

@test "an earlier already-typed short flag in the replay doesn't consume the next word as its value" {
  flag verbose -v --verbose
  run _bo_complete -- -v --mode ""
  assert_success
  assert_line "fast"
  assert_line "slow"
  assert_line "auto"
}

@test "an earlier plain positional token in the replay advances past a satisfied argument" {
  argument dest required type=choice choices=alpha,beta
  run _bo_complete -- foo ""
  assert_success
  assert_line "alpha"
  assert_line "beta"
  # If "foo" hadn't incremented positional_count, this would still be
  # offering "source"'s type=directory completion (a filesystem listing)
  # instead of "dest"'s type=choice completion.
  assert_equal "${#lines[@]}" 2
}

@test "completing a later (third) of several declared positional arguments" {
  cd "$BATS_TEST_TMPDIR"
  mkdir -p dir-a dir-b
  argument middle required type=choice choices=x,y
  argument dest required type=directory
  run _bo_complete -- foo bar ""
  assert_success
  assert_line "dir-a"
  assert_line "dir-b"
  refute_line "x"
  refute_line "y"
}

@test "completing past all declared positional arguments yields no completions" {
  argument middle required type=choice choices=x,y
  argument dest required type=directory
  run _bo_complete -- foo bar baz ""
  assert_success
  assert_output ""
}

@test "_bo_bash_completion delegates to the target command's --__complete" {
  mock_command() {
    _bo_complete "${@:2}"
  }
  COMP_WORDS=(mock_command --mode s)
  COMP_CWORD=2
  _bo_bash_completion mock_command
  assert_equal "${COMPREPLY[0]}" "slow"
}
