#!/usr/bin/env bats

load '../../support/bats-support/load'
load '../../support/bats-assert/load'
set -euo pipefail

setup() {
  # shellcheck source=../../betteropts.sh
  source "$BATS_TEST_DIRNAME/../../betteropts.sh"
}

pair() { option set -s --set fields=key,value syntax=equals "$@"; }
populate() {
  _bo_finalize_schema
  _bo_parse "$@"
  _bo_assign_positionals
  _bo_validate
  _bo_apply_defaults
  _bo_populate
}

@test "equals syntax is restricted to exactly two fields on options" {
  local declaration
  for declaration in 'option set --set VALUE syntax=equals' 'option set --set fields=key syntax=equals' \
    'option set --set fields=a,b,c syntax=equals' 'flag set --set syntax=equals' \
    'argument set optional syntax=equals' 'option set --set fields=key,value syntax=' \
    'option set --set fields=key,value syntax=other'; do
    ( eval "$declaration"; run _bo_finalize_schema; assert_failure )
  done
}

@test "equals syntax uses final repeated metadata and works before fields" {
  option set --set syntax=other syntax=equals fields=one fields=key,value
  _bo_finalize_schema
  assert_equal "$(_bo_option_arity set)" 2
  assert_equal "$(_bo_option_input_arity set)" 1
}

@test "long short and attached equals occurrences retain duplicate keys in order" {
  pair multi var=result
  flag verbose -v --verbose
  argument file optional
  populate --set k=one -v -s k=two --set=k=three input
  # shellcheck disable=SC2154
  assert_equal "${result_key[*]}" 'k k k'
  # shellcheck disable=SC2154
  assert_equal "${result_value[*]}" 'one two three'
  # shellcheck disable=SC2154
  assert_equal "$verbose" true
  # shellcheck disable=SC2154
  assert_equal "$file" input
  [[ ! -v set && ! -v result ]]
}

@test "equals decoding splits once and preserves empty fields and literal shell data" {
  pair multi
  local literal=$'spaces \'quotes\' "double" \\ backslash\n$(touch should-not-exist) `touch should-not-exist`;*'
  cd "$BATS_TEST_TMPDIR"
  populate --set '=' --set '=a=b=' --set "key=$literal" --set $'key\n=tail\n\n'
  # shellcheck disable=SC2154
  assert_equal "${set_key[0]}" ''
  # shellcheck disable=SC2154
  assert_equal "${set_value[0]}" ''
  assert_equal "${set_value[1]}" 'a=b='
  assert_equal "${set_value[2]}" "$literal"
  assert_equal "${set_key[3]}" $'key\n'
  assert_equal "${set_value[3]}" $'tail\n\n'
  [[ ! -e should-not-exist ]]
}

@test "missing pair tokens and missing separators fail without accepting spaced fields" {
  pair
  local spelling
  for spelling in --set -s; do
    run _bo_parse "$spelling"
    assert_failure
    assert_output $'Missing value:\n\n--set'
    run _bo_parse "$spelling" key value
    assert_failure
    assert_output $'Invalid value:\n\n--set key (expected KEY=VALUE)'
  done
  run _bo_parse --set=key value
  assert_failure
  assert_output --partial 'expected KEY=VALUE'
  run _bo_parse --set=
  assert_failure
}

@test "scalar fields validate only the retained occurrence and omitted fields stay empty" {
  pair value.type=integer
  populate --set k=invalid --set k=3
  assert_equal "$set_key" k
  assert_equal "$set_value" 3
  populate
  assert_equal "$set_key" ''
  assert_equal "$set_value" ''
}

@test "multi validates every occurrence and empty typed fields use existing validators" {
  pair multi value.type=integer
  _bo_finalize_schema
  _bo_parse --set k=invalid --set k=3
  run _bo_validate
  assert_failure
  assert_output --partial '--set VALUE invalid (must be an integer)'
  _bo_parse --set k=
  run _bo_validate
  assert_failure
  assert_output --partial '--set VALUE  (must be an integer)'
  _bo_parse
  _bo_validate
  _bo_populate
  assert_equal "${#set_key[@]}" 0
  assert_equal "${#set_value[@]}" 0
}

@test "requiredness and first-field types apply to decoded fields" {
  pair required key.type=integer
  _bo_finalize_schema
  _bo_parse
  run _bo_validate
  assert_failure
  assert_output --partial 'Missing required option:'
  _bo_parse --set '=value'
  run _bo_validate
  assert_failure
  assert_output --partial '--set KEY  (must be an integer)'
  populate --set -3=value
  assert_equal "$set_key" -3
}

@test "ordinary arity stays verbatim and equals pair parsing resumes at boundaries" {
  pair multi
  option plain --plain fields=first,second
  flag verbose --verbose
  argument tail passthrough
  populate --plain a=b c --set --verbose=-- --verbose --unknown raw
  # shellcheck disable=SC2154
  assert_equal "$plain_first" a=b
  # shellcheck disable=SC2154
  assert_equal "$plain_second" c
  assert_equal "${set_key[0]}" --verbose
  assert_equal "${set_value[0]}" --
  assert_equal "$verbose" true
  # shellcheck disable=SC2154
  assert_equal "${tail[*]}" '--unknown raw'
  populate -- --set k=v
  assert_equal "${#set_key[@]}" 0
  assert_equal "${tail[*]}" '-- --set k=v'
}

@test "equals pairs render joined metavars in help and whole repeated occurrences in usage" {
  pair required multi value.type=choice value.choices=one,two
  _bo_finalize_schema
  _bo_command_name=sample
  run _bo_usage_line
  assert_output 'sample --set KEY=VALUE [--set KEY=VALUE]...'
  run _bo_option_label set
  assert_output '-s, --set KEY=VALUE (required, repeatable, VALUE choices: one, two)'
}

@test "pair completion selects fields and returns whole pair tokens" {
  pair multi key.type=choice key.choices=kind,axis value.type=choice 'value.choices=one,two,with=equals,value with spaces'
  _bo_finalize_schema
  run _bo_complete -- --set k
  assert_output kind=
  run _bo_complete -- -s axis=t
  assert_output axis=two
  run _bo_complete -- --set=kind=with=
  assert_output --set=kind=with=equals
  run _bo_complete -- --set kind=value
  assert_output 'kind=value with spaces'
  run _bo_complete -- --set axis=one --set axis=
  assert_output $'axis=one\naxis=two\naxis=with=equals\naxis=value with spaces'
}

@test "pair completion consumes one token and honors boundaries without populating variables" {
  pair key.type=choice key.choices=kind,axis value.type=choice value.choices=one,two
  option mode --mode MODE type=choice choices=fast,slow
  argument file optional type=choice choices=alpha,beta
  _bo_finalize_schema
  run _bo_complete -- --set=kind=one --mode s
  assert_output slow
  run _bo_complete -- -s kind=one b
  assert_output beta
  run _bo_complete -- --set --=one --mo
  assert_output --mode
  run _bo_complete -- --set kind=one -- --mo
  assert_output ''
  run _bo_complete -- -- --set=kind=o
  assert_output ''
  _bo_complete -- --set kind=o >/dev/null
  [[ ! -v set_key && ! -v set_value && ! -v mode ]]
}

@test "pair file and directory completion retain the first-field prefix" {
  cd "$BATS_TEST_TMPDIR"
  mkdir dir-one
  : > file-one
  pair key.type=directory value.type=file
  _bo_finalize_schema
  run _bo_complete -- --set d
  assert_output dir-one=
  run _bo_complete -- --set dir-one=f
  assert_output dir-one=file-one
}

@test "adapter reassembles only adjacent equals word breaks and strips the replacement prefix" {
  pair key.type=choice key.choices=kind value.type=choice value.choices=one,two
  # shellcheck disable=SC2329
  mock_command() { _bo_complete "${@:2}"; }
  COMP_WORDS=(mock_command --set kind "=" t)
  COMP_CWORD=4
  COMP_LINE='mock_command --set kind=t'
  COMP_POINT=${#COMP_LINE}
  COMP_WORDBREAKS=' ='
  _bo_bash_completion mock_command t
  assert_equal "${COMPREPLY[0]}" two
  COMP_WORDS=(mock_command --set "=" kind "=" '')
  COMP_CWORD=5
  COMP_LINE='mock_command --set=kind='
  COMP_POINT=${#COMP_LINE}
  _bo_bash_completion mock_command ''
  assert_equal "${COMPREPLY[*]}" 'one two'
  COMP_WORDS=(mock_command --set kind "=" t)
  COMP_CWORD=4
  COMP_LINE='mock_command --set kind =t'
  COMP_POINT=${#COMP_LINE}
  _bo_bash_completion mock_command t
  assert_equal "${#COMPREPLY[@]}" 0
}

@test "ordinary current attachments remain unsupported after adapter normalization" {
  option mode --mode MODE type=choice choices=one,two
  # shellcheck disable=SC2329
  mock_command() { _bo_complete "${@:2}"; }
  COMP_WORDS=(mock_command --mode "=" o)
  COMP_CWORD=3
  COMP_LINE='mock_command --mode=o'
  COMP_POINT=${#COMP_LINE}
  COMP_WORDBREAKS=' ='
  _bo_bash_completion mock_command o
  assert_equal "${#COMPREPLY[@]}" 0
}

@test "adapter escapes only pair candidates and handles plain header-like values literally" {
  # shellcheck disable=SC2016
  pair key.type=choice key.choices=kind value.type=choice 'value.choices=value with spaces,shell;$(false)*'
  option mode --mode MODE type=choice 'choices=pair,plain,ordinary=,ordinary value'
  # shellcheck disable=SC2329
  mock_command() { _bo_complete "${@:2}"; }
  COMP_WORDS=(mock_command --set kind "=" value)
  COMP_CWORD=4
  COMP_LINE='mock_command --set kind=value'
  COMP_POINT=${#COMP_LINE}
  COMP_WORDBREAKS=' ='
  _bo_bash_completion mock_command value
  assert_equal "${COMPREPLY[0]}" 'value\ with\ spaces'
  COMP_WORDS=(mock_command --mode '')
  COMP_CWORD=2
  COMP_LINE='mock_command --mode '
  COMP_POINT=${#COMP_LINE}
  _bo_bash_completion mock_command ''
  assert_equal "${COMPREPLY[0]}" pair
  assert_equal "${COMPREPLY[1]}" plain
  assert_equal "${COMPREPLY[2]}" ordinary=
  assert_equal "${COMPREPLY[3]}" 'ordinary value'
  COMP_WORDS=(mock_command --set kind "=" nope)
  COMP_CWORD=4
  COMP_LINE='mock_command --set kind=nope'
  COMP_POINT=${#COMP_LINE}
  _bo_bash_completion mock_command nope
  assert_equal "${#COMPREPLY[@]}" 0
}

@test "adapter reassembles adjacent runs of equals signs" {
  pair value.type=choice value.choices==leading
  # shellcheck disable=SC2329
  mock_command() { _bo_complete "${@:2}"; }
  COMP_WORDS=(mock_command --set kind '==' le)
  COMP_CWORD=4
  COMP_LINE='mock_command --set kind==le'
  COMP_POINT=${#COMP_LINE}
  COMP_WORDBREAKS=' ='
  _bo_bash_completion mock_command le
  assert_equal "${COMPREPLY[0]}" leading
}

@test "first-field completion omits keys containing the reserved separator" {
  pair key.type=choice key.choices=kind,invalid=key value.type=choice value.choices=with=equals
  run _bo_complete -- --set ''
  assert_output kind=
  run _bo_complete -- --set kind=with=
  assert_output kind=with=equals
}
