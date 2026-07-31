#!/usr/bin/env bats

load '../../support/bats-support/load'
load '../../support/bats-assert/load'

set -euo pipefail

BETTEROPTS="$BATS_TEST_DIRNAME/../../betteropts.sh"

setup() {
  # shellcheck source=../../betteropts.sh
  source "$BETTEROPTS"
}

@test "summary stores the summary text" {
  summary "Build a project"
  assert_equal "$_bo_summary" "Build a project"
}

@test "description stores the description text" {
  description "
Line one.

Line two.
"
  assert_regex "$_bo_description" "Line one\."
  assert_regex "$_bo_description" "Line two\."
}

@test "flag registers short, long, and help metadata" {
  flag verbose -v --verbose help="Enable verbose logging"
  assert_equal "$(_bo_meta_get verbose short)" "-v"
  assert_equal "$(_bo_meta_get verbose long)" "--verbose"
  assert_equal "$(_bo_meta_get verbose help)" "Enable verbose logging"
  assert_equal "$(_bo_meta_get verbose var)" "verbose"
}

@test "flag defaults var to the declared name" {
  flag force -f --force
  assert_equal "$(_bo_meta_get force var)" "force"
}

@test "flag var overrides the populated variable name" {
  flag verbose -v --verbose var=is_verbose
  assert_equal "$(_bo_meta_get verbose var)" "is_verbose"
}

@test "flag records declaration order" {
  flag verbose -v --verbose
  flag force -f --force
  assert_equal "${_bo_flags[0]}" "verbose"
  assert_equal "${_bo_flags[1]}" "force"
}

@test "flag supports long-only declarations" {
  flag quiet --quiet
  assert_equal "$(_bo_meta_get quiet short)" ""
  assert_equal "$(_bo_meta_get quiet long)" "--quiet"
}

@test "option registers short, long, metavar, and help metadata" {
  option output -o --output PATH help="Output directory"
  assert_equal "$(_bo_meta_get output short)" "-o"
  assert_equal "$(_bo_meta_get output long)" "--output"
  assert_equal "$(_bo_meta_get output metavar)" "PATH"
  assert_equal "$(_bo_meta_get output help)" "Output directory"
}

@test "option records required, type, default and choices" {
  option mode -m --mode MODE type=choice choices=fast,slow,auto default=fast
  assert_equal "$(_bo_meta_get mode type)" "choice"
  assert_equal "$(_bo_meta_get mode choices)" "fast,slow,auto"
  assert_equal "$(_bo_meta_get mode default)" "fast"
}

@test "option required keyword sets required metadata" {
  option output -o --output PATH required
  assert_equal "$(_bo_meta_get output required)" "true"
}

@test "option is not required by default" {
  option jobs -j --jobs N default=4
  assert_equal "$(_bo_meta_get jobs required)" "false"
}

@test "option declaring optional does not set required metadata" {
  option jobs -j --jobs N optional
  assert_equal "$(_bo_meta_get jobs required)" "false"
}

@test "option declaring variadic does not set required metadata" {
  option jobs -j --jobs N variadic
  assert_equal "$(_bo_meta_get jobs required)" "false"
}

@test "option declaring passthrough does not set required metadata" {
  option jobs -j --jobs N passthrough
  assert_equal "$(_bo_meta_get jobs required)" "false"
}

@test "flag declaring optional does not set required metadata" {
  flag verbose -v --verbose optional
  assert_equal "$(_bo_meta_get verbose required)" "false"
}

@test "option var overrides the populated variable name" {
  option output -o --output PATH var=build_dir
  assert_equal "$(_bo_meta_get output var)" "build_dir"
}

@test "option multi keyword sets multi metadata" {
  option topic -t --topic VALUE multi
  assert_equal "$(_bo_meta_get topic multi)" "true"
}

@test "option is not multi by default" {
  option topic -t --topic VALUE
  assert_equal "$(_bo_meta_get topic multi)" ""
}

@test "argument records cardinality, type and help" {
  argument source required type=directory help="Source directory"
  assert_equal "$(_bo_meta_get source cardinality)" "required"
  assert_equal "$(_bo_meta_get source type)" "directory"
  assert_equal "$(_bo_meta_get source help)" "Source directory"
}

@test "argument supports optional and variadic cardinality" {
  argument destination optional
  argument files variadic
  assert_equal "$(_bo_meta_get destination cardinality)" "optional"
  assert_equal "$(_bo_meta_get files cardinality)" "variadic"
}

@test "argument records declaration order" {
  argument source required
  argument destination optional
  assert_equal "${_bo_arguments[0]}" "source"
  assert_equal "${_bo_arguments[1]}" "destination"
}

@test "argument var overrides the populated variable name" {
  argument source required var=input_dir
  assert_equal "$(_bo_meta_get source var)" "input_dir"
}

@test "argument records default on optional cardinality" {
  argument commit optional default=HEAD
  assert_equal "$(_bo_meta_get commit default)" "HEAD"
}

@test "argument records default on variadic cardinality" {
  argument folders variadic default=.
  assert_equal "$(_bo_meta_get folders default)" "."
}

@test "schema finalization rejects more than one variadic argument" {
  argument files1 variadic
  argument files2 variadic
  run _bo_finalize_schema
  assert_failure
}

@test "schema finalization rejects a variadic argument that is not last" {
  argument files variadic
  argument destination optional
  run _bo_finalize_schema
  assert_failure
}

@test "argument supports passthrough cardinality" {
  argument extra passthrough
  assert_equal "$(_bo_meta_get extra cardinality)" "passthrough"
}

@test "schema finalization rejects a passthrough argument that is not last" {
  argument extra passthrough
  argument destination optional
  run _bo_finalize_schema
  assert_failure
}

@test "schema finalization rejects both a variadic and a passthrough argument" {
  argument files variadic
  argument extra passthrough
  run _bo_finalize_schema
  assert_failure
}

@test "schema finalization accepts a passthrough argument as the sole collect-rest argument" {
  argument source required
  argument extra passthrough
  run _bo_finalize_schema
  assert_success
}

@test "schema finalization rejects a default on a required argument" {
  argument commit required default=HEAD
  run _bo_finalize_schema
  assert_failure
}

@test "schema finalization rejects a default combined with multi" {
  option topic -t --topic VALUE multi default=fast
  run _bo_finalize_schema
  assert_failure
}

@test "schema finalization rejects 'optional' on an option" {
  option jobs -j --jobs N optional
  run _bo_finalize_schema
  assert_failure
}

@test "schema finalization rejects 'variadic' on an option" {
  option jobs -j --jobs N variadic
  run _bo_finalize_schema
  assert_failure
}

@test "schema finalization rejects 'passthrough' on an option" {
  option jobs -j --jobs N passthrough
  run _bo_finalize_schema
  assert_failure
}

@test "schema finalization rejects 'optional' on a flag" {
  flag verbose -v --verbose optional
  run _bo_finalize_schema
  assert_failure
}

@test "schema finalization rejects 'variadic' on a flag" {
  flag verbose -v --verbose variadic
  run _bo_finalize_schema
  assert_failure
}

@test "schema finalization rejects 'passthrough' on a flag" {
  flag verbose -v --verbose passthrough
  run _bo_finalize_schema
  assert_failure
}

@test "schema finalization accepts a valid schema" {
  argument source required
  argument destination optional
  argument files variadic
  run _bo_finalize_schema
  assert_success
}

@test "schema finalization rejects an unrecognized key on a flag" {
  flag verbose -v --verbose bogus=1
  run _bo_finalize_schema
  assert_failure
  assert_output --partial "bogus"
}

@test "schema finalization rejects an unrecognized key on an option" {
  option mode -m --mode MODE chocies=fast,slow
  run _bo_finalize_schema
  assert_failure
  assert_output --partial "chocies"
}

@test "schema finalization rejects an unrecognized key on an argument" {
  argument source required deafult=foo
  run _bo_finalize_schema
  assert_failure
  assert_output --partial "deafult"
}

@test "_bo_key_allowed denies every key for an unrecognized kind" {
  run _bo_key_allowed bogus help
  assert_failure
}

@test "schema finalization rejects 'multi' on a flag" {
  flag verbose -v --verbose multi
  run _bo_finalize_schema
  assert_failure
}

@test "schema finalization rejects 'multi' on an argument" {
  argument files required multi
  run _bo_finalize_schema
  assert_failure
}

@test "schema finalization rejects 'required' on a flag" {
  flag verbose -v --verbose required
  run _bo_finalize_schema
  assert_failure
}

@test "schema finalization rejects a second bareword on an option" {
  option output -o --output PATH BOGUS
  run _bo_finalize_schema
  assert_failure
}

@test "schema finalization rejects an unrecognized bareword on a flag" {
  flag verbose -v --verbose bogus
  run _bo_finalize_schema
  assert_failure
}

@test "schema finalization rejects a misspelled cardinality keyword on an argument" {
  argument source requried
  run _bo_finalize_schema
  assert_failure
}

@test "schema finalization rejects an argument with no cardinality keyword" {
  argument source
  run _bo_finalize_schema
  assert_failure
}

@test "schema finalization rejects an argument declaring two cardinality keywords" {
  argument source required optional
  run _bo_finalize_schema
  assert_failure
}

@test "schema finalization rejects a required argument declared after an optional one" {
  argument mode optional
  argument source required
  run _bo_finalize_schema
  assert_failure
}

@test "schema finalization accepts a required argument declared before an optional one" {
  argument source required
  argument destination optional
  run _bo_finalize_schema
  assert_success
}

@test "schema finalization accepts an optional argument declared before a variadic one" {
  argument destination optional
  argument files variadic
  run _bo_finalize_schema
  assert_success
}

@test "schema finalization accepts an optional argument declared before a passthrough one" {
  argument mode optional
  argument extra passthrough
  run _bo_finalize_schema
  assert_success
}

@test "schema finalization accepts required, then optional, then variadic" {
  argument source required
  argument destination optional
  argument files variadic
  run _bo_finalize_schema
  assert_success
}

@test "schema finalization accepts two optional arguments in a row" {
  argument first optional
  argument second optional
  run _bo_finalize_schema
  assert_success
}

@test "schema finalization accepts every documented modifier for each kind" {
  flag verbose -v --verbose help="Enable verbose logging"
  option output -o --output PATH required type=directory help="Output directory"
  option jobs -j --jobs N default=4 type=integer help="Worker count"
  option topic -t --topic VALUE multi type=choice choices=fast,slow,auto var=topics help="Topics"
  argument source required type=directory var=input_dir help="Source directory"
  argument destination optional type=directory default=. help="Destination directory"
  argument files variadic help="Extra files"
  run _bo_finalize_schema
  assert_success
}
