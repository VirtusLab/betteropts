#!/usr/bin/env bats

load '../../support/bats-support/load'
load '../../support/bats-assert/load'
load '../helpers/git_repo'

set -euo pipefail

BUILD_FIXTURE="$BATS_TEST_DIRNAME/../fixtures/build"
TYPES_FIXTURE="$BATS_TEST_DIRNAME/../fixtures/types"
GIT_COMMITISH_FIXTURE="$BATS_TEST_DIRNAME/../fixtures/git_commitish"

setup() {
  SRC_DIR="$BATS_TEST_TMPDIR/src"
  OUT_DIR="$BATS_TEST_TMPDIR/out"
  CONFIG_FILE="$BATS_TEST_TMPDIR/config.toml"
  mkdir -p "$SRC_DIR" "$OUT_DIR"
  : > "$CONFIG_FILE"
}

@test "type=choice accepts a listed choice" {
  run "$TYPES_FIXTURE" --mode slow
  assert_success
  assert_line "mode=slow"
}

@test "type=choice applies its default" {
  run "$TYPES_FIXTURE" --count 1
  assert_success
  assert_line "mode=fast"
}

@test "type=choice rejects a value outside the choice list" {
  run "$TYPES_FIXTURE" --mode bogus
  assert_failure
  assert_output "Invalid value:

--mode bogus (choices: fast, slow, auto)"
}

@test "type=integer accepts an integer value" {
  run "$TYPES_FIXTURE" --count 42
  assert_success
  assert_line "count=42"
}

@test "type=integer rejects a non-integer value" {
  run "$TYPES_FIXTURE" --count abc
  assert_failure
  assert_output "Invalid value:

--count abc (must be an integer)"
}

@test "type=float accepts a decimal value" {
  run "$TYPES_FIXTURE" --ratio 3.14
  assert_success
  assert_line "ratio=3.14"
}

@test "type=float rejects a non-numeric value" {
  run "$TYPES_FIXTURE" --ratio abc
  assert_failure
  assert_output "Invalid value:

--ratio abc (must be a number)"
}

@test "type=file accepts an existing file" {
  run "$TYPES_FIXTURE" --config "$CONFIG_FILE"
  assert_success
  assert_line "config=$CONFIG_FILE"
}

@test "type=file rejects a path that does not exist" {
  run "$TYPES_FIXTURE" --config "$BATS_TEST_TMPDIR/nope.toml"
  assert_failure
  assert_output "Invalid value:

--config $BATS_TEST_TMPDIR/nope.toml (no such file)"
}

@test "type=directory accepts an existing directory (argument)" {
  run "$BUILD_FIXTURE" --output "$OUT_DIR" "$SRC_DIR"
  assert_success
  assert_line "source=$SRC_DIR"
}

@test "type=directory rejects a path that does not exist (argument)" {
  run "$BUILD_FIXTURE" --output "$OUT_DIR" "$BATS_TEST_TMPDIR/nope"
  assert_failure
  assert_output "Invalid value:

SOURCE $BATS_TEST_TMPDIR/nope (no such directory)"
}

@test "type=directory rejects a path that does not exist (option)" {
  run "$BUILD_FIXTURE" --output "$BATS_TEST_TMPDIR/nope" "$SRC_DIR"
  assert_failure
  assert_output "Invalid value:

--output $BATS_TEST_TMPDIR/nope (no such directory)"
}

@test "variadic argument collects zero values" {
  run "$TYPES_FIXTURE" --count 1
  assert_success
  assert_line "files="
}

@test "variadic argument collects multiple trailing values" {
  run "$TYPES_FIXTURE" --count 1 alpha beta gamma
  assert_success
  assert_line "files=alpha beta gamma"
}

@test "type=git-commitish accepts a full SHA, a branch, and a relative expression" {
  setup_git_repo
  run "$GIT_COMMITISH_FIXTURE" --base "$GIT_REPO_HEAD" HEAD~1
  assert_success
  assert_line "base=$GIT_REPO_HEAD"
  assert_line "commit=HEAD~1"
}

@test "type=git-commitish rejects a nonexistent ref" {
  setup_git_repo
  run "$GIT_COMMITISH_FIXTURE" --base does-not-exist
  assert_failure
  assert_output "Invalid value:

--base does-not-exist (not a valid git revision)"
}

@test "an omitted git-commitish argument's default is applied without being validated" {
  setup_git_repo
  run "$GIT_COMMITISH_FIXTURE" --base "$GIT_REPO_HEAD"
  assert_success
  assert_line "commit=HEAD"
}

@test "type=git-commitish reports a distinct error outside a git repository" {
  cd "$BATS_TEST_TMPDIR"
  run "$GIT_COMMITISH_FIXTURE" --base HEAD
  assert_failure
  assert_output "Not inside a git repository:

--base HEAD"
}
