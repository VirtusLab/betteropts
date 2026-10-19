#!/usr/bin/env bats

load '../../support/bats-support/load'
load '../../support/bats-assert/load'

set -euo pipefail

BETTEROPTS="$BATS_TEST_DIRNAME/../../betteropts.sh"

compat_cli() {
  bash -c '
    source "$1"
    shift
    summary "Compatibility sample"
    description "Detailed description"
    option item --item VALUE required
    argument extra passthrough
    betteropts_parse "$@"
    printf "item=%s\n" "$item"
    printf "extra=%s\n" "${extra[*]}"
  ' compat "$BETTEROPTS" "$@"
}

@test "C24 builtins bypass missing requirements errors and passthrough boundaries before literal double dash" {
  local builtin
  for builtin in -h --help --usage; do
    run compat_cli --unknown "$builtin"
    assert_success
    assert_output --partial 'Usage:'
    run compat_cli --item "$builtin"
    assert_success
    assert_output --partial 'Usage:'
  done
  run compat_cli --item value -- --help
  assert_success
  assert_output $'item=value\nextra=-- --help'
}

@test "C25 schema rejection takes precedence over every builtin" {
  local builtin
  for builtin in --help --usage --__complete; do
    run bash -c '
      source "$1"
      option item --item multi default=1
      betteropts_parse "$2"
    ' compat "$BETTEROPTS" "$builtin"
    assert_failure
    assert_output 'A multi option cannot declare a default.'
  done
}

@test "C26 first help or usage token wins and completion is special only in argv one" {
  run compat_cli --usage --help
  assert_success
  refute_output --partial 'Detailed description'
  run compat_cli --help --usage
  assert_success
  assert_output --partial 'Detailed description'
  run compat_cli --__complete -- --it
  assert_success
  assert_output --item
  run compat_cli --item value --__complete
  assert_success
  assert_output $'item=value\nextra=--__complete'
  run compat_cli --__complete --help
  assert_success
  assert_output --partial 'Detailed description'
}

@test "C27 reserved aliases are accepted declarations but their builtin takes precedence" {
  run bash -c '
    source "$1"
    flag custom --help
    betteropts_parse --help
    printf "custom=%s\n" "$custom"
  ' compat "$BETTEROPTS"
  assert_success
  assert_output --partial 'Show this help'
  refute_output --partial custom=true
}

compat_records_cli() {
  bash -c '
    set -euo pipefail
    IFS=$(printf "\n\t")
    source "$1"
    context="$2"
    shift 2
    summary "Compatibility records"
    flag verbose -v --verbose
    option record -r --record multi fields=key,value,passage value.type=choice value.choices=high,low var=verdict
    option ordinary --ordinary type=integer default=trusted-default
    option mode -m --mode implicit=on default=off type=choice choices=on,off
    case "$context" in
      required) argument first required; argument extra passthrough ;;
      optional) argument first optional default=fallback; argument extra variadic ;;
      raw) argument first optional; argument extra passthrough ;;
      *) exit 2 ;;
    esac
    betteropts_parse "$@"
    printf "count=%s\n" "${#verdict_key[@]}"
    for i in "${!verdict_key[@]}"; do
      printf "key=%s\nvalue=%s\npassage=%s\n" "${verdict_key[$i]}" "${verdict_value[$i]}" "${verdict_passage[$i]}"
    done
    printf "ordinary=%s\nmode=%s\nverbose=%s\nfirst=%s\n" "$ordinary" "$mode" "$verbose" "$first"
    for value in "${extra[@]}"; do printf "extra=%s\n" "$value"; done
  ' compat "$BETTEROPTS" "$@"
}

@test "C43 public records coexist with required slots and preserve passthrough capture and builtin-looking data" {
  run compat_records_cli required --record -- high --help --ordinary 2 --mode --verbose -- operand --record ignored low ignored
  assert_success
  assert_line count=1
  assert_line key=--
  assert_line passage=--help
  assert_line ordinary=2
  assert_line mode=on
  assert_line verbose=true
  # The actual marker fills the earlier required slot, as in C28.
  assert_line first=--
  assert_line extra=operand
  assert_line extra=--record
}

@test "C44 raw builtin precedence and consumed marker protection are unchanged around records" {
  local builtin
  for builtin in --help -h --usage; do
    run compat_records_cli required --record key high "$builtin"
    assert_success
    assert_output --partial 'Usage:'
    refute_output --partial count=
    run compat_records_cli required --record=-- high "$builtin" input
    assert_success
    assert_output --partial 'Usage:'
    run compat_records_cli required --record -- high "$builtin" input
    assert_success
    assert_line "passage=$builtin"
    assert_line first=input
  done
  run compat_records_cli raw --unknown=value --help
  assert_success
  assert_output --partial 'Usage:'
}

@test "C45 malformed record schema precedes every builtin before parsing any values" {
  local builtin bad
  for builtin in --help --usage --__complete; do
    for bad in default=1 implicit=1 type=integer metavar=SPEC; do
      run bash -c '
        source "$1"
        option record --record fields=key,value "$2"
        betteropts_parse "$3"
      ' compat "$BETTEROPTS" "$bad" "$builtin"
      assert_failure
      assert_output "Option 'record' cannot combine fields= with ${bad%%=*}=."
    done
  done
}

@test "C46 public completion replays ordinary implicit and record occurrences then honors real boundaries" {
  run compat_records_cli optional --__complete -- --mode --record=key l
  assert_success
  assert_output low
  run compat_records_cli optional --__complete -- --ordinary -- --record key h
  assert_success
  assert_output high
  run compat_records_cli optional --__complete -- --record key high passage -- --ver
  assert_success
  assert_output ''
  local token
  for token in --unknown=value --verbose=true; do
    run compat_records_cli raw --__complete -- --record key high passage "$token" --rec
    assert_success
    assert_output ''
  done
  # First-word dispatch only: later --__complete is an ordinary raw token.
  run compat_records_cli raw --record key high passage --__complete
  assert_success
  assert_line first=--__complete
}

@test "C47 public record values remain literal alongside ordinary defaults and empty optional positionals" {
  local text=$'O\'Brien \\ $(touch should-not-exist) `touch should-not-exist` ; *\nnext line'
  cd "$BATS_TEST_TMPDIR"
  run compat_records_cli optional --record= high "$text" --record next low '' ''
  assert_success
  assert_line count=2
  assert_line key=
  assert_line "passage=${text%%$'\n'*}"
  assert_line 'next line'
  assert_line passage=
  assert_line ordinary=trusted-default
  assert_line mode=off
  assert_line first=fallback
  [[ ! -e should-not-exist ]]
}
