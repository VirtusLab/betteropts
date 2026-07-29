#!/usr/bin/env bats

load '../../support/bats-support/load'
load '../../support/bats-assert/load'

set -euo pipefail

FIXTURE="$BATS_TEST_DIRNAME/../fixtures/build"
PASSTHROUGH_FIXTURE="$BATS_TEST_DIRNAME/../fixtures/passthrough"
ANNOTATIONS_FIXTURE="$BATS_TEST_DIRNAME/../fixtures/annotations"

@test "--usage prints summary and usage line only" {
  run "$FIXTURE" --usage
  assert_success
  expected="Build a project

Usage:

build [OPTIONS] SOURCE [DESTINATION]"
  assert_output "$expected"
}

@test "-h prints the same as --help" {
  run "$FIXTURE" -h
  local help_output="$output"
  run "$FIXTURE" --help
  assert_output "$help_output"
}

@test "--help prints full help text matching the CLI schema" {
  run "$FIXTURE" --help
  assert_success
  expected="Build a project

Compile a project and write the resulting artifacts.

Supports incremental and parallel builds.

Usage:

build [OPTIONS] SOURCE [DESTINATION]

Arguments

SOURCE (required)
    Source directory

DESTINATION
    Destination directory

Options

-v, --verbose
    Enable verbose logging

-f, --force
    Overwrite existing output

-o, --output PATH (required)
    Output directory

-j, --jobs N (default: 4)
    Worker count

-h, --help
    Show this help"
  assert_output "$expected"
}

@test "--help does not mention --usage or --__complete" {
  run "$FIXTURE" --help
  refute_output --partial "--usage"
  refute_output --partial "--__complete"
}

@test "--help and --usage exit 0" {
  run "$FIXTURE" --help
  assert_equal "$status" 0
  run "$FIXTURE" --usage
  assert_equal "$status" 0
}

@test "--help wins even alongside an otherwise-invalid command line" {
  run "$FIXTURE" --this-is-not-a-real-option --help
  assert_success
  assert_output --partial "Usage:"
}

@test "-- suppresses built-in command detection for tokens after it" {
  run "$FIXTURE" --output /tmp -- --help
  assert_failure
  refute_output --partial "Usage:"
}

@test "--usage renders a passthrough argument with an ellipsis" {
  run "$PASSTHROUGH_FIXTURE" --usage
  assert_success
  assert_output --partial "[GIT_ARGS...]"
}

@test "--help renders a passthrough argument like any other argument, without fake type info" {
  run "$PASSTHROUGH_FIXTURE" --help
  assert_success
  assert_line "GIT_ARGS"
  assert_line "    Extra options forwarded to git log"
}

@test "--help annotates required, repeatable, default, and choices" {
  run "$ANNOTATIONS_FIXTURE" --help
  assert_success
  expected="Annotation sample

Usage:

annotations [OPTIONS] SOURCE [REVIEWERS...]

Arguments

SOURCE (required)
    Source directory

REVIEWERS (repeatable, default: alice,bob)
    Reviewers

Options

-o, --output PATH (required)
    Output directory

-j, --jobs N (default: 4)
    Worker count

-t, --topic VALUE (repeatable, choices: fast, slow, auto)
    Note topic to show

-h, --help
    Show this help"
  assert_output "$expected"
}
