#!/usr/bin/env bats

load '../../support/bats-support/load'
load '../../support/bats-assert/load'

BETTEROPTS="$BATS_TEST_DIRNAME/../../betteropts.sh"

setup() {
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
  [[ "$_bo_description" == *"Line one."* ]]
  [[ "$_bo_description" == *"Line two."* ]]
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

@test "schema finalization accepts a valid schema" {
  argument source required
  argument destination optional
  argument files variadic
  run _bo_finalize_schema
  assert_success
}
