#!/usr/bin/env bats

load '../../support/bats-support/load'
load '../../support/bats-assert/load'

set -euo pipefail

setup() {
  # shellcheck source=../../betteropts.sh
  source "$BATS_TEST_DIRNAME/../../betteropts.sh"
}

questions() {
  option question -q --question fields=label,value,passage multi \
    value.type=choice value.choices=high,medium,low
}

populate() {
  _bo_finalize_schema
  _bo_parse "$@"
  _bo_assign_positionals
  _bo_validate
  _bo_apply_defaults
  _bo_populate
}

@test "repeated records stay aligned across short long and attached forms" {
  questions
  flag verbose -v --verbose
  argument file required
  populate --question Q-order high '§4.2, Table 3' -v -q Q-path low 'p. 4' --question=Q-more medium 'Table 2' input
  # shellcheck disable=SC2154
  assert_equal "${question_label[*]}" 'Q-order Q-path Q-more'
  # shellcheck disable=SC2154
  assert_equal "${question_value[*]}" 'high low medium'
  # shellcheck disable=SC2154
  assert_equal "${question_passage[0]}" '§4.2, Table 3'
  assert_equal "${question_passage[2]}" 'Table 2'
  # shellcheck disable=SC2154
  assert_equal "$verbose" true
  # shellcheck disable=SC2154
  assert_equal "$file" input
  [[ ! -v question ]]
}

@test "field population preserves quoting newlines empty strings and shell text literally" {
  questions
  local text=$'apostrophe\' backslash\\ spaces\n$(touch should-not-exist) `touch should-not-exist` ; * [x]'
  cd "$BATS_TEST_TMPDIR"
  populate -q '' high "$text" --question=Q-empty low ''
  assert_equal "${question_label[0]}" ''
  assert_equal "${question_passage[0]}" "$text"
  assert_equal "${question_passage[1]}" ''
  [[ ! -e should-not-exist ]]
}

@test "non-multi fields are scalars and the last occurrence wins" {
  option pair -p --pair fields=key,value var=result
  populate -p first old --pair=last new
  # shellcheck disable=SC2154
  assert_equal "$result_key" last
  # shellcheck disable=SC2154
  assert_equal "$result_value" new
  [[ ! -v pair && ! -v result ]]
  run declare -p result_key
  assert_output --partial 'declare -- result_key='
}

@test "omitted field options create empty arrays or empty scalars" {
  questions
  option pair --pair fields=key,value
  populate
  assert_equal "${#question_label[@]}" 0
  assert_equal "${#question_value[@]}" 0
  assert_equal "${#question_passage[@]}" 0
  # shellcheck disable=SC2154
  assert_equal "$pair_key" ''
  # shellcheck disable=SC2154
  assert_equal "$pair_value" ''
}

@test "required records need at least one occurrence" {
  option pair --pair required multi fields=key,value
  _bo_finalize_schema
  _bo_parse
  run _bo_validate
  assert_failure
  assert_output $'Missing required option:\n\n--pair'
}

@test "incomplete records fail in every invocation form" {
  questions
  local form
  for form in --question -q --question=Q-order; do
    run _bo_parse "$form" high
    assert_failure
    assert_output $'Missing value:\n\n--question'
  done
}

@test "hyphen-leading fields and -- consume their slots before option parsing resumes" {
  option record --record fields=first,second,third multi
  flag verbose -v --verbose
  populate --record --verbose -- -123 --record=-x --unknown 'tail' --verbose
  # shellcheck disable=SC2154
  assert_equal "${record_first[0]}" --verbose
  # shellcheck disable=SC2154
  assert_equal "${record_second[0]}" --
  # shellcheck disable=SC2154
  assert_equal "${record_third[0]}" -123
  assert_equal "${record_first[1]}" -x
  assert_equal "${record_second[1]}" --unknown
  assert_equal "$verbose" true
}

@test "field validators identify the field and reject a bad repeated record" {
  questions
  _bo_finalize_schema
  _bo_parse -q Q-first high p1 -q Q-second invalid p2
  run _bo_validate
  assert_failure
  assert_output --partial '--question VALUE invalid (choices: high, medium, low)'
}

@test "each field has its own type validator" {
  option record --record fields=count,ratio,path count.type=integer ratio.type=float path.type=file
  _bo_finalize_schema
  _bo_parse --record -3 1.25 "$BATS_TEST_FILENAME"
  run _bo_validate
  assert_success
  _bo_parse --record nope 1.25 "$BATS_TEST_FILENAME"
  run _bo_validate
  assert_failure
  assert_output --partial '--record COUNT nope (must be an integer)'
  _bo_parse --record 3 nope "$BATS_TEST_FILENAME"
  run _bo_validate
  assert_failure
  assert_output --partial '--record RATIO nope (must be a number)'
}

@test "fields reject scalar-only attributes including explicit empty values" {
  local attr
  for attr in 'type=string' 'choices=a,b' 'metavar=SPEC' 'default=' 'implicit='; do
    ( option pair --pair fields=key,value "$attr"
      run _bo_finalize_schema
      assert_failure
      assert_output --partial "cannot combine fields= with ${attr%%=*}=" )
  done
}

@test "bare metavar also conflicts with fields" {
  option pair --pair SPEC fields=key,value
  run _bo_finalize_schema
  assert_failure
  assert_output --partial 'cannot combine fields= with metavar='
}

@test "invalid empty duplicate and malformed field identifiers fail schema validation" {
  local fields
  for fields in '' ',a' 'a,' 'a,,b' 'a,a' 'a,b-c' 'a,2bad' 'a,has space' $'a,b\nc'; do
    ( option pair --pair "fields=$fields"
      run _bo_finalize_schema
      assert_failure )
  done
}

@test "a single named field is a supported fixed-arity record" {
  option item --item fields=value
  populate --item hello
  # shellcheck disable=SC2154
  assert_equal "$item_value" hello
}

@test "unknown field attributes names and types are rejected" {
  local attr
  for attr in 'key.chocies=a,b' 'other.type=string' 'key.type=int' 'key.default=x' 'key.choices=a,b' 'key.type=choice'; do
    ( option pair --pair fields=key,value "$attr"
      run _bo_finalize_schema
      assert_failure )
  done
}

@test "field attributes need fields and cannot be used on other declaration kinds" {
  option pair --pair key.type=integer
  run _bo_finalize_schema
  assert_failure
  assert_output --partial 'requires fields='
}

@test "fields are an option-only schema attribute" {
  flag verbose --verbose fields=value
  run _bo_finalize_schema
  assert_failure
  assert_output --partial "'fields' is not a recognized attribute for flag"
}

@test "generated output names cannot collide with ordinary or field variables" {
  questions
  argument source optional var=question_label
  run _bo_finalize_schema
  assert_failure
  assert_output --partial "Field variable 'question_label'"
}

@test "field output collisions are checked across different prefixes" {
  option first --first fields=b_c var=a
  option second --second fields=c var=a_b
  run _bo_finalize_schema
  assert_failure
  assert_output --partial "Field variable 'a_b_c'"
}

@test "field prefixes must be safe shell identifiers outside library namespace" {
  local prefix
  for prefix in '' 'bad-name' 'x[0]' _bo _bo_raw; do
    ( option pair --pair fields=key,value "var=$prefix"
      run _bo_finalize_schema
      assert_failure
      assert_output --partial 'Invalid field variable prefix' )
  done
}

@test "help and usage display the complete occurrence with field-specific choices" {
  questions
  _bo_finalize_schema
  _bo_command_name=tag
  run _bo_usage_line
  assert_output 'tag [--question LABEL VALUE PASSAGE]...'
  run _bo_option_label question
  assert_output '-q, --question LABEL VALUE PASSAGE (repeatable, VALUE choices: high, medium, low)'
}

@test "required record usage repeats whole occurrences" {
  option pair -p fields=key,value required multi
  _bo_finalize_schema
  _bo_command_name=tag
  run _bo_usage_line
  assert_output 'tag -p KEY VALUE [-p KEY VALUE]...'
}

@test "completion selects the right field for long short and attached occurrences" {
  questions
  _bo_finalize_schema
  run _bo_complete -- --question Q-order m
  assert_output medium
  run _bo_complete -- -q Q-order ''
  assert_output $'high\nmedium\nlow'
  run _bo_complete -- --question=Q-order h
  assert_output high
  run _bo_complete -- --question Q-order high text --question Q-other l
  assert_output low
}

@test "completion consumes flag-shaped and -- field values before resuming options" {
  option record --record fields=first,second,third third.type=choice third.choices=alpha,beta
  flag verbose -v --verbose
  _bo_finalize_schema
  run _bo_complete -- --record --verbose -- a
  assert_output alpha
  run _bo_complete -- --record --verbose -- alpha --ver
  assert_output --verbose
}

@test "completion resumes positionals and scalar options after full records" {
  questions
  option mode -m --mode MODE type=choice choices=fast,slow
  argument file required type=choice choices=one,two
  _bo_finalize_schema
  run _bo_complete -- --question=Q-order high passage --mode s
  assert_output slow
  run _bo_complete -- -q Q-order high passage t
  assert_output two
}

@test "completion uses field file and directory types" {
  cd "$BATS_TEST_TMPDIR"
  mkdir directory
  : > file.txt
  option pair --pair fields=folder,path folder.type=directory path.type=file
  _bo_finalize_schema
  run _bo_complete -- --pair d
  assert_output directory
  run _bo_complete -- --pair directory f
  assert_output file.txt
}

@test "field attributes may precede fields and var changes every repeated output prefix" {
  option question --question value.type=choice value.choices=high,low \
    fields=label,value var=verdict multi
  populate --question Q-order high --question Q-path low
  # shellcheck disable=SC2154
  assert_equal "${verdict_label[*]}" 'Q-order Q-path'
  # shellcheck disable=SC2154
  assert_equal "${verdict_value[*]}" 'high low'
  [[ ! -v question_label && ! -v question_value ]]
}

@test "completion respects a real -- outside record slots" {
  questions
  argument file required type=choice choices=--first,--second
  _bo_finalize_schema
  run _bo_complete -- --question Q-order high passage -- --s
  assert_output --second
}

@test "completion offers nothing for a passthrough boundary after a full record" {
  questions
  argument extra passthrough
  _bo_finalize_schema
  run _bo_complete -- --question Q-order high passage --unknown --q
  assert_output ''
}

@test "help identifies independent choices for several fields in declaration order" {
  option pair --pair fields=first,second first.type=choice first.choices=a,b \
    second.type=choice second.choices=x,y
  _bo_finalize_schema
  run _bo_option_label pair
  assert_output '--pair FIRST SECOND (FIRST choices: a, b, SECOND choices: x, y)'
}

@test "field declarations parsing and completion ignore the caller's IFS" {
  IFS=$'\n\t'
  questions
  populate --question Q-order high '§4.2, Table 3'
  assert_equal "${question_label[0]}" Q-order
  assert_equal "${question_value[0]}" high
  assert_equal "${question_passage[0]}" '§4.2, Table 3'
  run _bo_complete -- --question=Q-order m
  assert_output medium
}
