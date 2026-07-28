#!/usr/bin/env bats

load '../../support/bats-support/load'
load '../../support/bats-assert/load'

FIXTURE="$BATS_TEST_DIRNAME/../fixtures/build"

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

SOURCE
    Source directory

DESTINATION
    Destination directory

Options

-v, --verbose
    Enable verbose logging

-f, --force
    Overwrite existing output

-o, --output PATH
    Output directory

-j, --jobs N
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
