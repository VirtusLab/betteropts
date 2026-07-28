#!/usr/bin/env bats

load '../../support/bats-support/load'
load '../../support/bats-assert/load'

FIXTURE="$BATS_TEST_DIRNAME/../fixtures/build"

setup() {
  SRC_DIR="$BATS_TEST_TMPDIR/src"
  DST_DIR="$BATS_TEST_TMPDIR/dst"
  OUT_DIR="$BATS_TEST_TMPDIR/out"
  mkdir -p "$SRC_DIR" "$DST_DIR" "$OUT_DIR"
}

@test "unknown option reports the offending flag and suggests --help" {
  run "$FIXTURE" --verboes --output "$OUT_DIR" "$SRC_DIR"
  assert_failure
  assert_output "Unknown option:

--verboes

Use --help for usage."
}

@test "unknown option error goes to stderr" {
  "$FIXTURE" --verboes --output "$OUT_DIR" "$SRC_DIR" 1>/dev/null 2>"$BATS_TEST_TMPDIR/stderr"
  assert [ -s "$BATS_TEST_TMPDIR/stderr" ]
}

@test "missing option value is reported" {
  run "$FIXTURE" "$SRC_DIR" --output
  assert_failure
  assert_output "Missing value:

--output"
}

@test "unexpected positional argument is reported" {
  run "$FIXTURE" --output "$OUT_DIR" "$SRC_DIR" "$DST_DIR" foo
  assert_failure
  assert_output "Unexpected argument:

foo"
}

@test "missing required positional argument is reported" {
  run "$FIXTURE" --output "$OUT_DIR"
  assert_failure
  assert_output "Missing required argument:

SOURCE"
}

@test "missing required option is reported" {
  run "$FIXTURE" "$SRC_DIR"
  assert_failure
  assert_output "Missing required option:

--output"
}

@test "parse errors exit with non-zero status" {
  run "$FIXTURE" --verboes
  assert_equal "$status" 1
}
