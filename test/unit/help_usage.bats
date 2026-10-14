#!/usr/bin/env bats

load '../../support/bats-support/load'
load '../../support/bats-assert/load'

set -euo pipefail

BETTEROPTS="$BATS_TEST_DIRNAME/../../betteropts.sh"

setup() {
  # shellcheck source=../../betteropts.sh
  source "$BETTEROPTS"
  _bo_command_name="build"
}

@test "usage line expands declared flags and options in declaration order" {
  flag verbose -v --verbose
  option output -o --output PATH required
  flag force -f --force
  option jobs -j --jobs N default=4 type=integer help="Worker count"
  argument source required
  assert_equal "$(_bo_usage_line)" "build [--verbose] --output PATH [--force] [--jobs N] SOURCE"
}

@test "usage line falls back to short names and retains value metavars" {
  flag quiet -q
  option output -o PATH required
  option jobs -j N
  flag force --force
  assert_equal "$(_bo_usage_line)" "build [-q] -o PATH [-j N] [--force]"
}

@test "usage line repeats whole optional and required multi occurrences" {
  option topic -t --topic VALUE multi type=choice choices=fast,slow,auto
  option include -i --include PATH required multi
  assert_equal "$(_bo_usage_line)" "build [--topic VALUE]... --include PATH [--include PATH]..."
}

@test "usage line shows attached optional values for implicit long options" {
  option notes -n --notes REF multi implicit=refs/notes/commits
  option mode --mode VALUE required implicit=on default=off
  assert_equal "$(_bo_usage_line)" "build [--notes[=REF]]... --mode[=VALUE]"
}

@test "usage line repeats required implicit multi occurrences" {
  option notes --notes REF required multi implicit=refs/notes/commits
  assert_equal "$(_bo_usage_line)" "build --notes[=REF] [--notes[=REF]]..."
}

@test "usage line keeps short-only implicit options bare" {
  option notes -n REF implicit=refs/notes/commits
  assert_equal "$(_bo_usage_line)" "build [-n]"
}

@test "usage line uses VALUE for missing or empty option metavars" {
  option output --output
  option mode --mode implicit=on
  option input -i metavar=
  assert_equal "$(_bo_usage_line)" "build [--output VALUE] [--mode[=VALUE]] [-i VALUE]"
}

@test "usage line marks a required argument bare" {
  argument source required
  assert_equal "$(_bo_usage_line)" "build SOURCE"
}

@test "usage line brackets an optional argument" {
  argument source required
  argument destination optional
  assert_equal "$(_bo_usage_line)" "build SOURCE [DESTINATION]"
}

@test "usage line brackets a variadic argument with an ellipsis" {
  argument files variadic
  assert_equal "$(_bo_usage_line)" "build [FILES...]"
}

@test "usage line brackets a passthrough argument with an ellipsis" {
  argument git_args passthrough
  assert_equal "$(_bo_usage_line)" "build [GIT_ARGS...]"
}

@test "usage line shows only the command when no entries are declared" {
  assert_equal "$(_bo_usage_line)" "build"
}

@test "usage text includes only summary and synopsis" {
  summary "Build a project"
  argument source required
  argument destination optional
  expected="Build a project

Usage:

build SOURCE [DESTINATION]"
  assert_equal "$(_bo_usage_text)" "$expected"
}

@test "help text expands the synopsis and retains detailed entries" {
  summary "Build a project"
  description "
Compile a project and write the resulting artifacts.

Supports incremental and parallel builds.
"
  flag verbose -v --verbose help="Enable verbose logging"
  flag force -f --force help="Overwrite existing output"
  option output -o --output PATH required help="Output directory"
  option jobs -j --jobs N default=4 help="Worker count"
  argument source required help="Source directory"
  argument destination optional help="Destination directory"

  expected="Build a project

Compile a project and write the resulting artifacts.

Supports incremental and parallel builds.

Usage:

build [--verbose] [--force] --output PATH [--jobs N] SOURCE [DESTINATION]

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

  assert_equal "$(_bo_help_text)" "$expected"
}

@test "_bo_annotations marks a required option" {
  option output -o --output PATH required help="Output directory"
  assert_equal "$(_bo_annotations output)" "required"
}

@test "_bo_annotations marks a multi option repeatable" {
  option topic -t --topic VALUE multi help="Topic"
  assert_equal "$(_bo_annotations topic)" "repeatable"
}

@test "_bo_annotations shows an option's default value" {
  option jobs -j --jobs N default=4 help="Worker count"
  assert_equal "$(_bo_annotations jobs)" "default: 4"
}

@test "_bo_annotations shows an option's choice list" {
  option mode -m --mode MODE type=choice choices=fast,slow,auto help="Mode"
  assert_equal "$(_bo_annotations mode)" "choices: fast, slow, auto"
}

@test "_bo_annotations combines required, repeatable, and choices for an option" {
  option topic -t --topic VALUE required multi type=choice choices=fast,slow,auto help="Topic"
  assert_equal "$(_bo_annotations topic)" "required, repeatable, choices: fast, slow, auto"
}

@test "_bo_annotations shows an option's implicit value" {
  option notes --notes REF implicit=refs/notes/commits help="Notes ref"
  assert_equal "$(_bo_annotations notes)" "implicit: refs/notes/commits"
}

@test "_bo_annotations combines default and implicit for an option" {
  option mode -m --mode VALUE default=off implicit=on help="Mode"
  assert_equal "$(_bo_annotations mode)" "default: off, implicit: on"
}

@test "_bo_annotations combines repeatable and implicit for an option" {
  option notes --notes REF multi implicit=refs/notes/commits help="Notes ref"
  assert_equal "$(_bo_annotations notes)" "repeatable, implicit: refs/notes/commits"
}

@test "_bo_annotations is empty for a plain option" {
  option output -o --output PATH help="Output directory"
  assert_equal "$(_bo_annotations output)" ""
}

@test "_bo_annotations marks a required argument" {
  argument source required help="Source directory"
  assert_equal "$(_bo_annotations source)" "required"
}

@test "_bo_annotations marks a variadic argument repeatable" {
  argument files variadic help="Files"
  assert_equal "$(_bo_annotations files)" "repeatable"
}

@test "_bo_annotations shows an argument's default value" {
  argument commit optional default=HEAD help="Commit ref"
  assert_equal "$(_bo_annotations commit)" "default: HEAD"
}

@test "_bo_annotations shows a variadic argument's default value list verbatim" {
  argument reviewers variadic default=alice,bob help="Reviewers"
  assert_equal "$(_bo_annotations reviewers)" "repeatable, default: alice,bob"
}

@test "_bo_annotations shows an argument's choice list" {
  argument mode optional type=choice choices=fast,slow,auto help="Mode"
  assert_equal "$(_bo_annotations mode)" "choices: fast, slow, auto"
}

@test "_bo_annotations is empty for a plain optional argument" {
  argument destination optional help="Destination directory"
  assert_equal "$(_bo_annotations destination)" ""
}

@test "_bo_option_label appends annotations after the metavar" {
  option output -o --output PATH required help="Output directory"
  assert_equal "$(_bo_option_label output)" "-o, --output PATH (required)"
}

@test "help text renders no parenthesized suffix when no annotations apply" {
  summary "Plain"
  option output -o --output PATH help="Output directory"
  argument source optional help="Source directory"
  run _bo_help_text
  refute_output --partial "("
}

@test "help text omits the Arguments section when no arguments are declared" {
  summary "No args"
  flag verbose -v --verbose help="Enable verbose logging"
  run _bo_help_text
  refute_output --partial "Arguments"
}

@test "help text omits the description block when none was declared" {
  summary "No description"
  argument source required help="Source directory"
  run _bo_help_text
  refute_output --partial $'\n\n\n'
}

@test "help text never mentions --usage or --__complete" {
  summary "Hidden built-ins"
  argument source required help="Source directory"
  run _bo_help_text
  refute_output --partial "--usage"
  refute_output --partial "--__complete"
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
