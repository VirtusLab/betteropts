#!/usr/bin/env bats

load '../../support/bats-support/load'
load '../../support/bats-assert/load'

BUILD_FIXTURE="$BATS_TEST_DIRNAME/../fixtures/build"
TYPES_FIXTURE="$BATS_TEST_DIRNAME/../fixtures/types"

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
