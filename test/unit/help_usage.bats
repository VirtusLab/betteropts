#!/usr/bin/env bats

load '../../support/bats-support/load'
load '../../support/bats-assert/load'

BETTEROPTS="$BATS_TEST_DIRNAME/../../betteropts.sh"

setup() {
  source "$BETTEROPTS"
  _bo_command_name="build"
}

@test "usage line always includes [OPTIONS]" {
  argument source required
  assert_equal "$(_bo_usage_line)" "build [OPTIONS] SOURCE"
}

@test "usage line marks a required argument bare" {
  argument source required
  assert_equal "$(_bo_usage_line)" "build [OPTIONS] SOURCE"
}

@test "usage line brackets an optional argument" {
  argument source required
  argument destination optional
  assert_equal "$(_bo_usage_line)" "build [OPTIONS] SOURCE [DESTINATION]"
}

@test "usage line brackets a variadic argument with an ellipsis" {
  argument files variadic
  assert_equal "$(_bo_usage_line)" "build [OPTIONS] [FILES...]"
}

@test "usage line has no argument tokens when none are declared" {
  assert_equal "$(_bo_usage_line)" "build [OPTIONS]"
}

@test "usage text matches the DESIGN.MD worked example" {
  summary "Build a project"
  argument source required
  argument destination optional
  expected="Build a project

Usage:

build [OPTIONS] SOURCE [DESTINATION]"
  assert_equal "$(_bo_usage_text)" "$expected"
}

@test "help text matches the DESIGN.MD worked example" {
  summary "Build a project"
  description "
Compile a project and write the resulting artifacts.

Supports incremental and parallel builds.
"
  flag verbose -v --verbose help="Enable verbose logging"
  flag force -f --force help="Overwrite existing output"
  option output -o --output PATH help="Output directory"
  option jobs -j --jobs N help="Worker count"
  argument source required help="Source directory"
  argument destination optional help="Destination directory"

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

  assert_equal "$(_bo_help_text)" "$expected"
}

@test "help text omits the Arguments section when no arguments are declared" {
  summary "No args"
  flag verbose -v --verbose help="Enable verbose logging"
  refute [[ "$(_bo_help_text)" == *"Arguments"* ]]
}

@test "help text omits the description block when none was declared" {
  summary "No description"
  argument source required help="Source directory"
  refute [[ "$(_bo_help_text)" == *$'\n\n\n'* ]]
}

@test "help text never mentions --usage or --__complete" {
  summary "Hidden built-ins"
  argument source required help="Source directory"
  refute [[ "$(_bo_help_text)" == *"--usage"* ]]
  refute [[ "$(_bo_help_text)" == *"--__complete"* ]]
}

@test "a long-only flag is labeled without a leading comma" {
  summary "Long only"
  flag quiet --quiet help="Be quiet"
  assert_equal "$(_bo_option_label quiet)" "--quiet"
}

@test "a short-only flag is labeled with just the short form" {
  summary "Short only"
  flag q -q help="Be quiet"
  assert_equal "$(_bo_option_label q)" "-q"
}
