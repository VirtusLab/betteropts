#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2154

load '../../support/bats-support/load'
load '../../support/bats-assert/load'

set -euo pipefail

BETTEROPTS="$BATS_TEST_DIRNAME/../../betteropts.sh"

setup() {
  # shellcheck source=../../betteropts.sh
  source "$BETTEROPTS"
  _bo_command_name=metadata
}

finish() {
  _bo_assign_positionals
  _bo_validate
  _bo_apply_defaults
  _bo_populate
}

@test "metadata keys separate logical names from attributes in either write order" {
  local order attribute got
  for order in before after; do
    for attribute in type choices help; do
      (
        [[ "$order" == before ]] && _bo_meta_set item "value.$attribute" $'record\n\n'
        _bo_meta_set item.value "$attribute" $'ordinary\n'
        [[ "$order" == after ]] && _bo_meta_set item "value.$attribute" $'record\n\n'
        _bo_meta_get item "value.$attribute" got
        assert_equal "$got" $'record\n\n'
        _bo_meta_get item.value "$attribute" got
        assert_equal "$got" $'ordinary\n'
      )
    done
  done
  _bo_meta_set item value.choices ''
  _bo_meta_has item value.choices
  run _bo_meta_has item.value choices
  assert_failure
  _bo_meta_get item value.choices got
  assert_equal "$got" ''
  _bo_meta_get item.value choices got
  assert_equal "$got" ''
  _bo_meta_set item%2Evalue choices $'escaped\n'
  _bo_meta_set item.value choices $'dotted\n'
  _bo_meta_get item%2Evalue choices got
  assert_equal "$got" $'escaped\n'
  _bo_meta_get item.value choices got
  assert_equal "$got" $'dotted\n'
}

@test "metadata retrieval retains literal bytes and can write caller-local names" {
  local sample expected destination name field value got
  for sample in '' plain $'\n' $'value\n' $'value\n\n' $'one\ntwo\n'; do
    expected="$sample"
    _bo_meta_set item help "$sample"
    for destination in name field value got; do
      _bo_meta_get item help "$destination"
      assert_equal "${!destination}" "$expected"
    done
  done
}

@test "record integer types stay independent from dotted ordinary IDs in both declaration orders" {
  local order
  for order in before after; do
    (
      [[ "$order" == before ]] && option item --item fields=value value.type=integer
      option item.value --other var=result type=string
      [[ "$order" == after ]] && option item --item fields=value value.type=integer
      _bo_finalize_schema
      _bo_parse --item not-integer --other text
      run _bo_validate
      assert_failure
      assert_output --partial '--item VALUE not-integer (must be an integer)'
      _bo_parse --item 12 --other text
      finish
      assert_equal "$item_value" 12
      assert_equal "$result" text
    )
  done
}

@test "record and dotted ordinary choice metadata drive their own validation help and completion" {
  local order
  for order in before after; do
    (
      [[ "$order" == before ]] && option item --item fields=value value.type=choice value.choices=red,blue help=record
      option item.value --other var=result type=choice choices=one,two help=ordinary
      [[ "$order" == after ]] && option item --item fields=value value.type=choice value.choices=red,blue help=record
      _bo_finalize_schema
      _bo_parse --item red --other one
      finish
      assert_equal "$item_value" red
      assert_equal "$result" one
      run _bo_option_label item
      assert_output '--item VALUE (VALUE choices: red, blue)'
      run _bo_option_label item.value
      assert_output '--other (choices: one, two)'
      run _bo_complete -- --item ''
      assert_output $'red\nblue'
      run _bo_complete -- --other ''
      assert_output $'one\ntwo'
      _bo_parse --item one --other one
      run _bo_validate
      assert_failure
      _bo_parse --item red --other red
      run _bo_validate
      assert_failure
    )
  done
}

@test "ordinary defaults and implicit values preserve exact empty internal and trailing newlines" {
  local value
  for value in '' plain $'\n' $'value\n' $'value\n\n' $'one\ntwo\n'; do
    (
      option defaulted --defaulted type=integer "default=$value"
      option implied -i --implied "implicit=$value"
      option explicit --explicit
      argument positional optional "default=$value"
      argument list variadic "default=first,$value"
      _bo_finalize_schema
      _bo_parse --implied "--explicit=$value"
      finish
      assert_equal "$defaulted" "$value"
      assert_equal "$implied" "$value"
      assert_equal "$explicit" "$value"
      assert_equal "$positional" "$value"
      assert_equal "${list[0]}" first
      if [[ -n "$value" ]]; then
        assert_equal "${list[1]}" "$value"
      else
        assert_equal "${#list[@]}" 1
      fi
      _bo_parse -i
      finish
      assert_equal "$implied" "$value"
    )
  done
}

@test "newline-bearing integer implicit values fail just like explicit values with scalar replacement retained" {
  option item --item type=integer $'implicit=1\n'
  _bo_finalize_schema
  local mode
  for mode in unused bare attached replaced; do
    case "$mode" in
      unused) _bo_parse ;;
      bare) _bo_parse --item ;;
      attached) _bo_parse $'--item=1\n' ;;
      replaced) _bo_parse --item --item=2 ;;
      *) return 1 ;;
    esac
    run _bo_validate
    case "$mode" in
      bare|attached) assert_failure; assert_output --partial 'must be an integer' ;;
      unused|replaced) assert_success ;;
      *) return 1 ;;
    esac
  done
  _bo_meta_set item multi true
  _bo_parse --item --item=2
  run _bo_validate
  assert_failure
}

@test "help labels and annotations preserve trailing newlines through generated wrappers" {
  local value text
  for value in '' plain $'\n' $'value\n' $'value\n\n' $'one\ntwo\n'; do
    (
      option item --item "metavar=$value" "default=$value" "implicit=$value" "help=$value"
      argument positional optional "default=$value" "help=$value"
      _bo_finalize_schema
      _bo_capture_text text _bo_option_label item
      local label=--item
      [[ -n "$value" ]] && label+=" $value"
      assert_equal "$text" "$label (default: $value, implicit: $value)"
      _bo_capture_text text _bo_help_text
      [[ "$text" == *"$label (default: $value, implicit: $value)"$'\n'"    $value"$'\n\n'"-h, --help"* ]]
      [[ "$text" == *"POSITIONAL (default: $value)"$'\n'"    $value"$'\n\n'"Options"* ]]
      if [[ -n "$value" ]]; then
        _bo_capture_text text _bo_usage_line
        assert_equal "$text" "metadata [--item[=$value]] [POSITIONAL]"
      fi
    )
  done
  option choice --choice type=choice $'choices=first,second\n\n'
  _bo_finalize_schema
  _bo_capture_text text _bo_option_label choice
  assert_equal "$text" $'--choice (choices: first, second\n\n)'

}

@test "effective structural metadata validates full bytes and honors final recognized replacements" {
  local attribute order position suffix
  for attribute in type fields var field_type; do
    for suffix in $'\n' $'\n\n' $'x\ny'; do
      for order in invalid_final valid_final; do
        for position in before after; do
          (
            local -a tokens=()
            case "$attribute" in
              type) tokens=(type=integer "type=integer$suffix") ;;
              fields) tokens=('fields=left,right' "fields=left,right$suffix") ;;
              var) tokens=(var=result "var=result$suffix") ;;
              field_type) tokens=(left.type=integer "left.type=integer$suffix") ;;
              *) return 1 ;;
            esac
            [[ "$order" == valid_final ]] && tokens=("${tokens[1]}" "${tokens[0]}")
            if [[ "$attribute" == type ]]; then
              option item --item "${tokens[@]}"
            elif [[ "$position" == before || "$attribute" == fields ]]; then
              option item --item fields=left,right "${tokens[@]}" help=record
            else
              option item --item help=record "${tokens[@]}" fields=left,right
            fi
            run _bo_finalize_schema
            if [[ "$order" == valid_final ]]; then
              assert_success
            else
              assert_failure
            fi
          )
        done
      done
    done
  done
}

@test "newline-bearing logical IDs and effective aliases remain literal in parsing and completion" {
  option $'item\n' -i --item var=result type=choice choices=one,two
  flag $'flag\n' $'--flag\n' var=enabled
  _bo_finalize_schema
  _bo_parse -i one $'--flag\n'
  finish
  assert_equal "$result" one
  assert_equal "$enabled" true
  _bo_parse --item=two
  finish
  assert_equal "$result" two
  run _bo_complete -- --item ''
  assert_output $'one\ntwo'
  local text
  _bo_capture_text text _bo_option_label $'flag\n'
  assert_equal "$text" $'--flag\n'
}

@test "exact structural errors precede public parsing help usage and completion in plain and strict callers" {
  local attribute mode caller
  local -a argv=()
  for attribute in type fields prefix field_type; do
    for mode in normal help usage completion; do
      case "$mode" in
        normal) argv=() ;;
        help) argv=(--help) ;;
        usage) argv=(--usage) ;;
        completion) argv=(--__complete -- '') ;;
        *) return 1 ;;
      esac
      for caller in plain strict; do
        run bash -c '
        metadata_schema_main() {
          [[ "$2" == strict ]] && set -euo pipefail
          source "$1"
          attribute=$3
          shift 3
          case "$attribute" in
            type) option item --item $'"'"'type=integer\n'"'"' ;;
            fields) option item --item $'"'"'fields=left,right\n'"'"' ;;
            prefix) option item --item fields=left,right $'"'"'var=result\n'"'"' ;;
            field_type) option item --item $'"'"'left.type=integer\n'"'"' fields=left,right ;;
          esac
          betteropts_parse "$@"
          printf reached-business-logic
        }
        metadata_schema_main "$@"
        ' bash "$BETTEROPTS" "$caller" "$attribute" "${argv[@]}"
        assert_failure
        refute_output --partial reached-business-logic
        refute_output --partial 'Usage:'
        case "$attribute" in
          type) assert_output --partial "is not a recognized type for option 'item'" ;;
          fields) assert_output --partial 'Invalid fields= list' ;;
          prefix) assert_output --partial 'Invalid field variable prefix' ;;
          field_type) assert_output --partial "is not a recognized type for field 'left'" ;;
          *) return 1 ;;
        esac
      done
    done
  done
}

@test "logical IDs retain metadata when the caller changes character-counting locale" {
  LC_ALL=en_US.UTF-8
  option café --item var=result
  LC_ALL=C
  _bo_finalize_schema
  _bo_parse --item value
  finish
  assert_equal "$result" value
}

@test "public entrypoints preserve literal default implicit help and metavar bytes in plain and strict callers" {
  local mode caller literal=$'value\n\n'
  local -a argv=()
  for mode in default implicit help usage completion; do
    case "$mode" in
      default) argv=() ;;
      implicit) argv=(--item) ;;
      help) argv=(--help) ;;
      usage) argv=(--usage) ;;
      completion) argv=(--__complete -- --choice '') ;;
      *) return 1 ;;
    esac
    for caller in plain strict; do
      run bash -c '
      metadata_literal_main() {
        [[ "$2" == strict ]] && set -euo pipefail
        source "$1"
        literal=$3
        shift 3
        option item --item "default=$literal" "implicit=$literal" "help=$literal" "metavar=$literal"
        option choice --choice type=choice choices=one,two
        betteropts_parse "$@"
        printf "<%s>" "$item"
      }
      metadata_literal_main "$@"
      ' bash "$BETTEROPTS" "$caller" "$literal" "${argv[@]}"
      assert_success
      case "$mode" in
        default|implicit) assert_output "<$literal>" ;;
        help)
          assert_output --partial "--item $literal (default: $literal, implicit: $literal)"$'\n'"    $literal"$'\n\n'"--choice"
          ;;
        usage) assert_output $'\n\nUsage:\n\nbash [--item[=value\n\n]] [--choice VALUE]' ;;
        completion) assert_output $'one\ntwo' ;;
        *) return 1 ;;
      esac
    done
  done
}
