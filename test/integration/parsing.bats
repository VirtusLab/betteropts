#!/usr/bin/env bats

load '../../support/bats-support/load'
load '../../support/bats-assert/load'

set -euo pipefail

FIXTURE="$BATS_TEST_DIRNAME/../fixtures/build"
VARNAMES_FIXTURE="$BATS_TEST_DIRNAME/../fixtures/varnames"
ARG_DEFAULTS_FIXTURE="$BATS_TEST_DIRNAME/../fixtures/arg_defaults"
MULTI_OPTION_FIXTURE="$BATS_TEST_DIRNAME/../fixtures/multi_option"
PASSTHROUGH_FIXTURE="$BATS_TEST_DIRNAME/../fixtures/passthrough"

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

@test "optional argument default is applied when omitted" {
  run "$ARG_DEFAULTS_FIXTURE"
  assert_success
  assert_line "commit=HEAD"
}

@test "optional argument default is overridden when provided" {
  run "$ARG_DEFAULTS_FIXTURE" abc123
  assert_success
  assert_line "commit=abc123"
}

@test "variadic argument default is applied when omitted" {
  run "$ARG_DEFAULTS_FIXTURE"
  assert_success
  assert_line "reviewers=alice bob"
}

@test "variadic argument default is overridden when provided" {
  run "$ARG_DEFAULTS_FIXTURE" abc123 carol dave
  assert_success
  assert_line "reviewers=carol dave"
}

@test "a multi option accumulates repeated occurrences (long form)" {
  run "$MULTI_OPTION_FIXTURE" --topic conflicts --topic builds
  assert_success
  assert_line "topic_count=2"
  assert_line "topic=conflicts builds"
}

@test "a multi option accumulates repeated occurrences (mixed forms)" {
  run "$MULTI_OPTION_FIXTURE" -t conflicts --topic=builds --topic tests
  assert_success
  assert_line "topic_count=3"
  assert_line "topic=conflicts builds tests"
}

@test "a multi option populates an empty array with zero occurrences" {
  run "$MULTI_OPTION_FIXTURE"
  assert_success
  assert_line "topic_count=0"
}

@test "a declared option before the passthrough boundary still parses normally" {
  run "$PASSTHROUGH_FIXTURE" --author alice --stat -M
  assert_success
  assert_line "author=alice"
  assert_line "git_args_count=2"
  assert_line "git_args=--stat -M"
}

@test "passthrough captures flag-shaped tokens without an unknown option error" {
  run "$PASSTHROUGH_FIXTURE" --stat -M v1.0
  assert_success
  assert_line "author="
  assert_line "git_args_count=3"
  assert_line "git_args=--stat -M v1.0"
}

@test "passthrough argument is empty when nothing follows declared options" {
  run "$PASSTHROUGH_FIXTURE" --author bob
  assert_success
  assert_line "author=bob"
  assert_line "git_args_count=0"
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
