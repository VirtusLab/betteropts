#!/usr/bin/env bats

load '../../support/bats-support/load'
load '../../support/bats-assert/load'

FIXTURE="$BATS_TEST_DIRNAME/../fixtures/build"
VARNAMES_FIXTURE="$BATS_TEST_DIRNAME/../fixtures/varnames"

setup() {
  SRC_DIR="$BATS_TEST_TMPDIR/src"
  DST_DIR="$BATS_TEST_TMPDIR/dst"
  OUT_DIR="$BATS_TEST_TMPDIR/out"
  mkdir -p "$SRC_DIR" "$DST_DIR" "$OUT_DIR"
}

@test "flags default to false when not passed" {
  run "$FIXTURE" --output "$OUT_DIR" "$SRC_DIR"
  assert_success
  assert_line "verbose=false"
  assert_line "force=false"
}

@test "flags become true when passed (long form)" {
  run "$FIXTURE" --verbose --force --output "$OUT_DIR" "$SRC_DIR"
  assert_success
  assert_line "verbose=true"
  assert_line "force=true"
}

@test "flags become true when passed (short form)" {
  run "$FIXTURE" -v -f --output "$OUT_DIR" "$SRC_DIR"
  assert_success
  assert_line "verbose=true"
  assert_line "force=true"
}

@test "repeated flags remain true" {
  run "$FIXTURE" -v -v --output "$OUT_DIR" "$SRC_DIR"
  assert_success
  assert_line "verbose=true"
}

@test "option accepts separate value form (-o value)" {
  run "$FIXTURE" -o "$OUT_DIR" "$SRC_DIR"
  assert_success
  assert_line "output=$OUT_DIR"
}

@test "option accepts separate value form (--output value)" {
  run "$FIXTURE" --output "$OUT_DIR" "$SRC_DIR"
  assert_success
  assert_line "output=$OUT_DIR"
}

@test "option accepts --output=value form" {
  run "$FIXTURE" "--output=$OUT_DIR" "$SRC_DIR"
  assert_success
  assert_line "output=$OUT_DIR"
}

@test "-o=value form is not supported" {
  run "$FIXTURE" "-o=$OUT_DIR" "$SRC_DIR"
  assert_failure
}

@test "default is applied when option omitted" {
  run "$FIXTURE" --output "$OUT_DIR" "$SRC_DIR"
  assert_success
  assert_line "jobs=4"
}

@test "explicit option value overrides default" {
  run "$FIXTURE" --output "$OUT_DIR" --jobs 8 "$SRC_DIR"
  assert_success
  assert_line "jobs=8"
}

@test "required positional argument is populated" {
  run "$FIXTURE" --output "$OUT_DIR" "$SRC_DIR"
  assert_success
  assert_line "source=$SRC_DIR"
}

@test "optional positional argument is populated when given" {
  run "$FIXTURE" --output "$OUT_DIR" "$SRC_DIR" "$DST_DIR"
  assert_success
  assert_line "destination=$DST_DIR"
}

@test "optional positional argument is empty when omitted" {
  run "$FIXTURE" --output "$OUT_DIR" "$SRC_DIR"
  assert_success
  assert_line "destination="
}

@test "-- treats subsequent tokens as positionals even if flag-like" {
  mkdir -p "$BATS_TEST_TMPDIR/-weird"
  run "$FIXTURE" --output "$OUT_DIR" -- "$SRC_DIR" "$BATS_TEST_TMPDIR/-weird"
  assert_success
  assert_line "destination=$BATS_TEST_TMPDIR/-weird"
}

@test "variable names can be overridden with var=" {
  run "$VARNAMES_FIXTURE" --output "$OUT_DIR" "$SRC_DIR"
  assert_success
  assert_line "build_dir=$OUT_DIR"
  assert_line "input_dir=$SRC_DIR"
}

@test "long-only flag declaration works without a short form" {
  run "$VARNAMES_FIXTURE" --output "$OUT_DIR" --quiet "$SRC_DIR"
  assert_success
  assert_line "quiet=true"
}

@test "populated variables are not exported" {
  BETTEROPTS="$BATS_TEST_DIRNAME/../../betteropts.sh"
  run bash -c "
    source '$BETTEROPTS'
    flag verbose -v --verbose
    betteropts_parse -v
    bash -c 'echo \${verbose:-unset}'
  "
  assert_success
  assert_output "unset"
}
