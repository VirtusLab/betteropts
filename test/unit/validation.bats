#!/usr/bin/env bats

load '../../support/bats-support/load'
load '../../support/bats-assert/load'
load '../helpers/git_repo'

set -euo pipefail

BETTEROPTS="$BATS_TEST_DIRNAME/../../betteropts.sh"

setup() {
  # shellcheck source=../../betteropts.sh
  source "$BETTEROPTS"
  TMP_FILE="$BATS_TEST_TMPDIR/file.txt"
  TMP_DIR="$BATS_TEST_TMPDIR/dir"
  : > "$TMP_FILE"
  mkdir -p "$TMP_DIR"
}

@test "missing required option is rejected" {
  option output -o --output PATH required
  argument source required
  _bo_parse src-token
  _bo_assign_positionals
  run _bo_validate
  assert_failure
  assert_output "Missing required option:

--output"
}

@test "provided required option passes validation" {
  option output -o --output PATH required
  _bo_parse --output "$TMP_DIR"
  _bo_assign_positionals
  run _bo_validate
  assert_success
}

@test "missing required argument is rejected" {
  argument source required
  _bo_parse
  _bo_assign_positionals
  run _bo_validate
  assert_failure
  assert_output "Missing required argument:

SOURCE"
}

@test "type=integer accepts an integer" {
  option count -c --count N type=integer
  _bo_parse --count 42
  _bo_assign_positionals
  run _bo_validate
  assert_success
}

@test "type=integer rejects a non-integer" {
  option count -c --count N type=integer
  _bo_parse --count abc
  _bo_assign_positionals
  run _bo_validate
  assert_failure
  assert_output "Invalid value:

--count abc (must be an integer)"
}

@test "type=float accepts a decimal" {
  option ratio --ratio F type=float
  _bo_parse --ratio 3.14
  _bo_assign_positionals
  run _bo_validate
  assert_success
}

@test "type=float rejects a non-numeric value" {
  option ratio --ratio F type=float
  _bo_parse --ratio abc
  _bo_assign_positionals
  run _bo_validate
  assert_failure
  assert_output "Invalid value:

--ratio abc (must be a number)"
}

@test "type=file accepts an existing file" {
  option config --config FILE type=file
  _bo_parse --config "$TMP_FILE"
  _bo_assign_positionals
  run _bo_validate
  assert_success
}

@test "type=file rejects a missing file" {
  option config --config FILE type=file
  _bo_parse --config "$BATS_TEST_TMPDIR/nope.txt"
  _bo_assign_positionals
  run _bo_validate
  assert_failure
  assert_output "Invalid value:

--config $BATS_TEST_TMPDIR/nope.txt (no such file)"
}

@test "type=directory accepts an existing directory" {
  option output -o --output PATH type=directory
  _bo_parse --output "$TMP_DIR"
  _bo_assign_positionals
  run _bo_validate
  assert_success
}

@test "type=directory rejects a missing directory" {
  argument source required type=directory
  _bo_parse "$BATS_TEST_TMPDIR/nope"
  _bo_assign_positionals
  run _bo_validate
  assert_failure
  assert_output "Invalid value:

SOURCE $BATS_TEST_TMPDIR/nope (no such directory)"
}

@test "type=choice accepts a listed value" {
  option mode -m --mode MODE type=choice choices=fast,slow,auto
  _bo_parse --mode slow
  _bo_assign_positionals
  run _bo_validate
  assert_success
}

@test "type=choice rejects an unlisted value" {
  option mode -m --mode MODE type=choice choices=fast,slow,auto
  _bo_parse --mode bogus
  _bo_assign_positionals
  run _bo_validate
  assert_failure
  assert_output "Invalid value:

--mode bogus (choices: fast, slow, auto)"
}

@test "variadic values are each type-checked" {
  argument files variadic type=integer
  _bo_parse 1 2 notanumber
  _bo_assign_positionals
  run _bo_validate
  assert_failure
  assert_output "Invalid value:

FILES notanumber (must be an integer)"
}

@test "defaults are applied to options that were not provided" {
  option jobs -j --jobs N default=4
  _bo_parse
  _bo_assign_positionals
  _bo_validate
  _bo_apply_defaults
  assert_equal "${_bo_raw[jobs]}" "4"
}

@test "defaults do not override an explicitly provided value" {
  option jobs -j --jobs N default=4
  _bo_parse --jobs 8
  _bo_assign_positionals
  _bo_validate
  _bo_apply_defaults
  assert_equal "${_bo_raw[jobs]}" "8"
}

@test "an option without a default stays unset when omitted" {
  option output -o --output PATH
  _bo_parse
  _bo_assign_positionals
  _bo_validate
  _bo_apply_defaults
  assert_equal "${_bo_raw[output]:-}" ""
}

@test "a multi option validates each repeated value independently" {
  option count -c --count N type=integer multi
  _bo_parse --count 1 --count 2 --count 3
  _bo_assign_positionals
  run _bo_validate
  assert_success
}

@test "one invalid value among several multi values fails validation, identifying it" {
  option count -c --count N type=integer multi
  _bo_parse --count 1 --count notanumber --count 3
  _bo_assign_positionals
  run _bo_validate
  assert_failure
  assert_output "Invalid value:

--count notanumber (must be an integer)"
}

@test "required + multi with zero occurrences is a Missing required option error" {
  option topic -t --topic VALUE required multi
  _bo_parse
  _bo_assign_positionals
  run _bo_validate
  assert_failure
  assert_output "Missing required option:

--topic"
}

@test "required + multi with at least one occurrence passes validation" {
  option topic -t --topic VALUE required multi
  _bo_parse --topic conflicts
  _bo_assign_positionals
  run _bo_validate
  assert_success
}

@test "an optional argument's default is not type-checked" {
  argument count optional type=integer default=notanumber
  _bo_parse
  _bo_assign_positionals
  run _bo_validate
  assert_success
}

@test "a variadic argument's default is not type-checked" {
  argument ids variadic type=integer default=notanumber,alsonotanumber
  _bo_parse
  _bo_assign_positionals
  run _bo_validate
  assert_success
}

@test "type=git-commitish accepts a full SHA" {
  setup_git_repo
  option base -b --base VALUE type=git-commitish
  _bo_parse --base "$GIT_REPO_HEAD"
  _bo_assign_positionals
  run _bo_validate
  assert_success
}

@test "type=git-commitish accepts an abbreviated SHA" {
  setup_git_repo
  local short_sha
  short_sha="$(git rev-parse --short HEAD)"
  option base -b --base VALUE type=git-commitish
  _bo_parse --base "$short_sha"
  _bo_assign_positionals
  run _bo_validate
  assert_success
}

@test "type=git-commitish accepts a branch name" {
  setup_git_repo
  option base -b --base VALUE type=git-commitish
  _bo_parse --base feature-branch
  _bo_assign_positionals
  run _bo_validate
  assert_success
}

@test "type=git-commitish accepts a tag name" {
  setup_git_repo
  option base -b --base VALUE type=git-commitish
  _bo_parse --base v1.0
  _bo_assign_positionals
  run _bo_validate
  assert_success
}

@test "type=git-commitish accepts a relative expression like HEAD~1" {
  setup_git_repo
  option base -b --base VALUE type=git-commitish
  _bo_parse --base HEAD~1
  _bo_assign_positionals
  run _bo_validate
  assert_success
}

@test "type=git-commitish rejects a nonexistent ref" {
  setup_git_repo
  option base -b --base VALUE type=git-commitish
  _bo_parse --base does-not-exist
  _bo_assign_positionals
  run _bo_validate
  assert_failure
  assert_output "Invalid value:

--base does-not-exist (not a valid git revision)"
}

@test "type=git-commitish rejects a tree sha (not a commit)" {
  setup_git_repo
  local tree_sha
  tree_sha="$(git rev-parse "HEAD^{tree}")"
  option base -b --base VALUE type=git-commitish
  _bo_parse --base "$tree_sha"
  _bo_assign_positionals
  run _bo_validate
  assert_failure
  assert_output "Invalid value:

--base $tree_sha (not a valid git revision)"
}

@test "type=git-commitish reports a distinct error outside a git repository" {
  cd "$BATS_TEST_TMPDIR"
  option base -b --base VALUE type=git-commitish
  _bo_parse --base HEAD
  _bo_assign_positionals
  run _bo_validate
  assert_failure
  assert_output "Not inside a git repository:

--base HEAD"
}

@test "type=git-commitish resolves an abbreviated SHA to the full SHA" {
  setup_git_repo
  option base -b --base VALUE type=git-commitish
  _bo_parse --base "$(git rev-parse --short HEAD)"
  _bo_assign_positionals
  _bo_validate
  assert_equal "${_bo_raw[base]}" "$GIT_REPO_HEAD"
}

@test "type=git-commitish resolves a branch name to the full SHA" {
  setup_git_repo
  option base -b --base VALUE type=git-commitish
  _bo_parse --base feature-branch
  _bo_assign_positionals
  _bo_validate
  assert_equal "${_bo_raw[base]}" "$GIT_REPO_HEAD"
}

@test "type=git-commitish resolves a tag name to the full SHA" {
  setup_git_repo
  option base -b --base VALUE type=git-commitish
  _bo_parse --base v1.0
  _bo_assign_positionals
  _bo_validate
  assert_equal "${_bo_raw[base]}" "$GIT_REPO_HEAD"
}

@test "type=git-commitish resolves a relative expression to the full SHA" {
  setup_git_repo
  local head_minus_1
  head_minus_1="$(git rev-parse HEAD~1)"
  option base -b --base VALUE type=git-commitish
  _bo_parse --base HEAD~1
  _bo_assign_positionals
  _bo_validate
  assert_equal "${_bo_raw[base]}" "$head_minus_1"
}

@test "type=git-commitish leaves a full SHA unchanged" {
  setup_git_repo
  option base -b --base VALUE type=git-commitish
  _bo_parse --base "$GIT_REPO_HEAD"
  _bo_assign_positionals
  _bo_validate
  assert_equal "${_bo_raw[base]}" "$GIT_REPO_HEAD"
}

@test "a multi git-commitish option resolves each occurrence independently" {
  setup_git_repo
  local head_minus_1
  head_minus_1="$(git rev-parse HEAD~1)"
  option base -b --base VALUE type=git-commitish multi
  _bo_parse --base HEAD~1 --base HEAD
  _bo_assign_positionals
  _bo_validate
  assert_equal "${_bo_multi_values[base.0]}" "$head_minus_1"
  assert_equal "${_bo_multi_values[base.1]}" "$GIT_REPO_HEAD"
}

@test "a variadic git-commitish argument resolves each element" {
  setup_git_repo
  local head_minus_1
  head_minus_1="$(git rev-parse HEAD~1)"
  argument commits variadic type=git-commitish
  _bo_parse HEAD~1 HEAD
  _bo_assign_positionals
  _bo_validate
  assert_equal "${_bo_variadic_values[0]}" "$head_minus_1"
  assert_equal "${_bo_variadic_values[1]}" "$GIT_REPO_HEAD"
}

@test "an omitted git-commitish option's default=HEAD resolves to the full SHA" {
  setup_git_repo
  option base -b --base VALUE type=git-commitish default=HEAD
  _bo_parse
  _bo_assign_positionals
  _bo_validate
  _bo_apply_defaults
  assert_equal "${_bo_raw[base]}" "$GIT_REPO_HEAD"
}

@test "an omitted git-commitish argument's default=HEAD resolves to the full SHA" {
  setup_git_repo
  argument commit optional type=git-commitish default=HEAD
  _bo_parse
  _bo_assign_positionals
  _bo_validate
  _bo_apply_defaults
  assert_equal "${_bo_raw[commit]}" "$GIT_REPO_HEAD"
}

@test "a bogus git-commitish default reports Invalid value when omitted" {
  setup_git_repo
  argument commit optional type=git-commitish default=does-not-exist
  _bo_parse
  _bo_assign_positionals
  _bo_validate
  run _bo_apply_defaults
  assert_failure
  assert_output "Invalid value:

COMMIT does-not-exist (not a valid git revision)"
}

@test "a git-commitish default outside a git repository reports Not inside a git repository" {
  cd "$BATS_TEST_TMPDIR"
  argument commit optional type=git-commitish default=HEAD
  _bo_parse
  _bo_assign_positionals
  _bo_validate
  run _bo_apply_defaults
  assert_failure
  assert_output "Not inside a git repository:

COMMIT HEAD"
}

@test "type=git-range accepts a bare revision" {
  setup_git_repo
  option range -r --range VALUE type=git-range
  _bo_parse --range HEAD
  _bo_assign_positionals
  run _bo_validate
  assert_success
}

@test "type=git-range accepts an A..B range" {
  setup_git_repo
  option range -r --range VALUE type=git-range
  _bo_parse --range "HEAD~1..HEAD"
  _bo_assign_positionals
  run _bo_validate
  assert_success
}

@test "type=git-range accepts an A...B range" {
  setup_git_repo
  option range -r --range VALUE type=git-range
  _bo_parse --range "HEAD~1...HEAD"
  _bo_assign_positionals
  run _bo_validate
  assert_success
}

@test "type=git-range rejects a range with a bogus endpoint" {
  setup_git_repo
  option range -r --range VALUE type=git-range
  _bo_parse --range "HEAD..does-not-exist"
  _bo_assign_positionals
  run _bo_validate
  assert_failure
  assert_output "Invalid value:

--range HEAD..does-not-exist (not a valid git revision range)"
}

@test "type=git-range reports a distinct error outside a git repository" {
  cd "$BATS_TEST_TMPDIR"
  option range -r --range VALUE type=git-range
  _bo_parse --range HEAD
  _bo_assign_positionals
  run _bo_validate
  assert_failure
  assert_output "Not inside a git repository:

--range HEAD"
}
