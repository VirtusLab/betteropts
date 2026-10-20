#!/usr/bin/env bats

load '../../support/bats-support/load'
load '../../support/bats-assert/load'

set -euo pipefail

BETTEROPTS="$BATS_TEST_DIRNAME/../../betteropts.sh"

# Each case runs through the public lifecycle, including the caller's shell
# flags, and must exit before the sentinel business logic can run.
identity_cli() {
  bash -c '
  identity_main() {
    mode="$2" kind="$3" scenario="$4" value="$5" entry="$6"
    case "$mode" in
      plain) ;;
      errexit) set -e ;;
      nounset) set -u ;;
      strict) set -eu ;;
    esac
    source "$1"
    case "$scenario" in
      missing) "$kind" ;;
      empty) "$kind" "" var=result ;;
      output)
        if [[ "$kind" == argument ]]; then
          argument item optional "var=$value"
        else
          "$kind" item --item "var=$value"
        fi ;;
      derived)
        if [[ "$kind" == argument ]]; then
          argument "$value" optional
        else
          "$kind" "$value" --item
        fi ;;
      spelling) "$kind" item "$value" ;;
      passthrough)
        case "$value" in
          before) argument item type=string passthrough ;;
          after) argument item passthrough type=string ;;
          repeated) argument item choices=one passthrough choices= ;;
          typerepeated) argument item type=integer passthrough type=string ;;
          choicesbefore) argument item choices=one passthrough ;;
          choicesafter) argument item passthrough choices=one ;;
          both) argument item choices=one passthrough type=string ;;
          *) argument item passthrough "$value" ;;
        esac ;;
    esac
    case "$entry" in
      normal) betteropts_parse ;;
      completion) betteropts_parse --__complete -- "" ;;
      *) betteropts_parse "$entry" ;;
    esac
    printf "BUSINESS LOGIC REACHED\n"
  }
  identity_main "$@"
  ' schema-identity "$BETTEROPTS" "$@"
}

@test "missing and empty names have library diagnostics in every caller mode and public entrypoint" {
  local mode kind entry scenario label
  for mode in plain errexit nounset strict; do
    for kind in flag option argument; do
      for scenario in missing empty; do
        label=Missing
        [[ "$scenario" == empty ]] && label=Empty
        for entry in normal -h --help --usage completion; do
          run identity_cli "$mode" "$kind" "$scenario" '' "$entry"
          assert_failure 1
          assert_output "$label name for $kind declaration."
        done
      done
    done
  done
}

@test "invalid effective and derived ordinary outputs reject before builtins independently of caller flags" {
  local mode kind entry value scenario
  for mode in plain errexit nounset strict; do
    for kind in flag option argument; do
      for value in '' bad-name 9bad 'result[0]' $'result\n' $'result\n\n'; do
        for entry in normal -h --help --usage completion; do
          run identity_cli "$mode" "$kind" output "$value" "$entry"
          assert_failure 1
          assert_output "Invalid output variable '$value' for $kind 'item' (expected a shell identifier)."
        done
      done
      for value in bad-name 'has space' 9bad; do
        run identity_cli "$mode" "$kind" derived "$value" normal
        assert_failure 1
        assert_output "Invalid output variable '$value' for $kind '$value' (expected a shell identifier)."
      done
    done
  done
}

@test "effective reserved and unreachable spellings reject before every public entrypoint" {
  local mode kind spelling entry expected
  for mode in plain errexit nounset strict; do
    for kind in flag option; do
      for spelling in -h --help --usage --__complete --bad=name; do
        if [[ "$spelling" == --bad=name ]]; then
          expected="Invalid long spelling '$spelling' for $kind 'item' (must not contain '=')."
        else
          expected="Reserved spelling '$spelling' for $kind 'item'."
        fi
        for entry in normal -h --help --usage completion; do
          run identity_cli "$mode" "$kind" spelling "$spelling" "$entry"
          assert_failure 1
          assert_output "$expected"
        done
      done
    done
  done
}

@test "passthrough rejects unsupported attributes by presence and order before every public entrypoint" {
  local mode entry value attribute
  for mode in plain errexit nounset strict; do
    for value in type= type=string type=integer type=unknown choices= choices=one before after repeated typerepeated choicesbefore choicesafter both; do
      attribute="type"
      case "$value" in choices=*|repeated|choicesbefore|choicesafter) attribute=choices ;; *) ;; esac
      for entry in normal -h --help --usage completion; do
        run identity_cli "$mode" argument passthrough "$value" "$entry"
        assert_failure 1
        assert_output "Passthrough argument 'item' cannot declare $attribute=."
      done
    done
  done
}

@test "final aliases and outputs win while logical IDs and literal data remain independent" {
  run bash -c '
  identity_controls() {
    set -eu
    source "$1"
    flag "flag id" -h -f --help --flag var=bad-name var=flag_result
    option --help --__complete --bad=name --custom var=bad-name var=option_result
    option _bo_private --private var=private_result
    option fallback default=trusted
    argument "arg-id" required var=argument_result
    betteropts_parse --flag --custom=literal --private=private -- --help
    printf "%s|%s|%s|%s|%s\n" "$flag_result" "$option_result" "$private_result" "$fallback" "$argument_result"
  }
  identity_controls "$@"
  ' schema-identity "$BETTEROPTS"
  assert_success
  assert_output 'true|literal|private|trusted|--help'
}

@test "final invalid replacements stay invalid and multi targets require plain identifiers" {
  run bash -c '
    source "$1"
    option item --item multi var=result "var=result[0]"
    betteropts_parse --help
  ' schema-identity "$BETTEROPTS"
  assert_failure 1
  assert_output "Invalid output variable 'result[0]' for option 'item' (expected a shell identifier)."
  run bash -c '
    source "$1"
    flag item --item --help
    betteropts_parse --usage
  ' schema-identity "$BETTEROPTS"
  assert_failure 1
  assert_output "Reserved spelling '--help' for flag 'item'."
}

@test "valid overrides retain CLI labels and accept ordinary loop-local output names" {
  local kind target
  for kind in flag option argument; do
    for target in name kind cardinality count tok var value i idx; do
      run bash -c '
      identity_output_control() {
        set -eu
        source "$1"
        case "$2" in
          flag) flag "has space" --item var=bad-name "var=$3"; betteropts_parse --item ;;
          option) option "has space" --item var=bad-name "var=$3"; betteropts_parse --item value ;;
          argument) argument "has space" required var=bad-name "var=$3"; betteropts_parse value ;;
        esac
        printf "%s\n" "${!3}"
      }
      identity_output_control "$@"
      ' schema-identity "$BETTEROPTS" "$kind" "$target"
      assert_success
      if [[ "$kind" == flag ]]; then assert_output true; else assert_output value; fi
    done
  done
  run bash -c '
    source "$1"
    flag item -h -i --help --usage --__complete --item var=result
    betteropts_parse --help
  ' schema-identity "$BETTEROPTS"
  assert_success
  assert_output --partial '-i, --item'
  refute_output --partial --__complete
  refute_output --partial --usage
  refute_output --partial result
  run bash -c '
    source "$1"
    option item --bad=name --help --item var=result
    betteropts_parse --__complete -- --it
  ' schema-identity "$BETTEROPTS"
  assert_success
  assert_output --item
}
