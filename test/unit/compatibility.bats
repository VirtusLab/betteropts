#!/usr/bin/env bats
# Bats isolates tests; mutations in one test's subshell cannot affect another.
# shellcheck disable=SC2030,SC2031

load '../../support/bats-support/load'
load '../../support/bats-assert/load'
load '../helpers/git_repo'

set -euo pipefail

BETTEROPTS="$BATS_TEST_DIRNAME/../../betteropts.sh"

setup() {
  # shellcheck source=../../betteropts.sh
  source "$BETTEROPTS"
  _bo_command_name=compat
  COMPAT_DIMENSIONS=(required optional variadic passthrough multi type choices default implicit var help metavar bare short long)
  COMPAT_TOKENS=(required optional variadic passthrough multi type=integer 'choices=1,2' default=1 implicit=1 var=compat_value help=example metavar=N N -n --number)
}

# Independent applicability inventory and named pair exclusions from README.
# If two tokens are independently invalid, either relevant rejection is valid;
# schema diagnostic priority is deliberately not part of the matrix contract.
compat_expected() {
  local kind="$1" dimension token allowed first="${2-}" second="${3-}"
  shift
  COMPAT_ERRORS=()
  case "$kind" in
    flag) allowed=' var help short long ' ;;
    option) allowed=' required multi type choices default implicit var help metavar bare short long ' ;;
    argument) allowed=' required optional variadic passthrough type choices default var help short long ' ;;
    *) return 1 ;;
  esac
  for dimension in "$@"; do
    [[ "$allowed" == *" $dimension "* ]] && continue
    token="$dimension"
    [[ "$dimension" == bare ]] && token=N
    case "$dimension" in
      type|choices|default|implicit|metavar) COMPAT_ERRORS+=("'$token' is not a recognized attribute for $kind 'item'.") ;;
      *) COMPAT_ERRORS+=("'$token' is not a valid $kind modifier for 'item'.") ;;
    esac
  done
  (( ${#COMPAT_ERRORS[@]} > 0 )) && return 0
  case "$kind:$first:$second" in
    option:multi:default|option:default:multi) COMPAT_ERRORS+=('A multi option cannot declare a default.') ;;
    argument:required:default|argument:default:required) COMPAT_ERRORS+=('A required argument cannot declare a default.') ;;
    argument:passthrough:default|argument:default:passthrough) COMPAT_ERRORS+=('A passthrough argument cannot declare a default.') ;;
    option:metavar:bare|option:bare:bare) COMPAT_ERRORS+=("'N' is not a valid option modifier for 'item'.") ;;
    *) ;;
  esac
  if [[ "$kind" == argument && " required optional variadic passthrough " == *" $first "* && " required optional variadic passthrough " == *" $second "* && -n "$second" ]]; then
    COMPAT_ERRORS+=("Argument 'item' declares more than one of required, optional, variadic, or passthrough (only one is allowed).")
  fi
  return 0
}

compat_schema() (
  local kind="$1" dimension cardinality=false
  local -a tokens=()
  shift
  # shellcheck source=../../betteropts.sh
  source "$BETTEROPTS"
  for dimension in "$@"; do
    tokens+=("${COMPAT_TOKENS[$dimension]}")
    case "${COMPAT_DIMENSIONS[$dimension]}" in
      required|optional|variadic|passthrough) cardinality=true ;;
      *) ;;
    esac
  done
  if [[ "$kind" == argument && "$cardinality" == false ]]; then
    tokens=(optional "${tokens[@]}")
  fi
  "$kind" item "${tokens[@]}"
  _bo_finalize_schema
)

compat_check() {
  local kind="$1" index actual expected actual_status=0
  local -a dimensions=()
  shift
  for index in "$@"; do dimensions+=("${COMPAT_DIMENSIONS[$index]}"); done
  compat_expected "$kind" "${dimensions[@]}"
  # Expected schema failures are captured and checked below.
  # shellcheck disable=SC2310
  actual="$(compat_schema "$kind" "$@" 2>&1)" || actual_status=$?
  if [[ "${#COMPAT_ERRORS[@]}" == 0 ]]; then
    if [[ "$actual_status" != 0 || -n "$actual" ]]; then
      printf 'Expected accepted schema: %s %s; status=%s output=%s\n' "$kind" "${dimensions[*]}" "$actual_status" "$actual" >&2
      return 1
    fi
  else
    if [[ "$actual_status" == 1 ]]; then
      for expected in "${COMPAT_ERRORS[@]}"; do [[ "$actual" == "$expected" ]] && return 0; done
    fi
    printf 'Wrong rejection: %s %s; status=%s output=%s; expected one of=%s\n' "$kind" "${dimensions[*]}" "$actual_status" "$actual" "${COMPAT_ERRORS[*]}" >&2
    return 1
  fi
}

@test "C01 every declaration dimension has checked applicability for every kind" {
  local kind i
  for kind in flag option argument; do
    for i in "${!COMPAT_DIMENSIONS[@]}"; do compat_check "$kind" "$i"; done
  done
}

compat_pairs() {
  local kind="$1" i j
  for i in "${!COMPAT_DIMENSIONS[@]}"; do
    for j in "${!COMPAT_DIMENSIONS[@]}"; do compat_check "$kind" "$i" "$j"; done
  done
}

@test "C02 every ordered pair and repeated dimension on a flag has checked schema behavior" {
  compat_pairs flag
}

@test "C03 every ordered pair and repeated dimension on an option has checked schema behavior" {
  compat_pairs option
}

@test "C04 every ordered pair and repeated dimension on an argument has checked schema behavior" {
  compat_pairs argument
}

@test "C05 all ordered positional cardinality pairs have checked schema behavior" {
  local first second actual expected status_code
  for first in required optional variadic passthrough; do
    for second in required optional variadic passthrough; do
      expected=
      case "$first:$second" in
        variadic:variadic|variadic:passthrough|passthrough:variadic|passthrough:passthrough)
          expected='Only one variadic or passthrough argument is allowed.' ;;
        variadic:*|passthrough:*) expected='The variadic or passthrough argument must be the last declared argument.' ;;
        optional:required) expected="Argument 'second' is required but declared after an optional argument (required arguments must come before optional ones)." ;;
        *) ;;
      esac
      status_code=0
      # Expected schema failures are captured and checked below.
      # shellcheck disable=SC2310
      actual="$( {
        # shellcheck source=../../betteropts.sh
        source "$BETTEROPTS"
        argument first "$first"
        argument second "$second"
        _bo_finalize_schema
      } 2>&1 )" || status_code=$?
      if [[ -n "$expected" ]]; then
        assert_equal "$status_code" 1
        assert_equal "$actual" "$expected"
      else
        assert_equal "$status_code" 0
        assert_equal "$actual" ''
      fi
    done
  done
}

@test "C06 required default and implicit distinguish presence from fallback and preserve the triple exclusion" {
  option item --item required default=2 implicit=1 type=integer var=compat_value
  _bo_finalize_schema
  _bo_parse
  run _bo_validate
  assert_failure
  assert_output $'Missing required option:\n\n--item'
  _bo_parse --item
  _bo_assign_positionals
  _bo_validate
  _bo_apply_defaults
  _bo_populate
  assert_equal "${compat_value-}" 1
  option many --many required multi default=2 implicit=1
  run _bo_finalize_schema
  assert_failure
  assert_output 'A multi option cannot declare a default.'
}

@test "C07 choices constrain validate complete and annotate only type choice" {
  option item --item N choices=1,2 var=compat_value
  _bo_finalize_schema
  _bo_parse --item 3
  _bo_validate
  _bo_populate
  assert_equal "${compat_value-}" 3
  assert_equal "$(_bo_annotations item)" ''
  run _bo_complete -- --item ''
  assert_success
  assert_output ''
  _bo_meta_set item type choice
  run _bo_validate
  assert_failure
  assert_output $'Invalid value:\n\n--item 3 (choices: 1, 2)'
  assert_equal "$(_bo_annotations item)" 'choices: 1, 2'
  run _bo_complete -- --item ''
  assert_output $'1\n2'
}

@test "C08 missing choice lists are accepted but reject provided values" {
  option item --item type=choice
  _bo_finalize_schema
  _bo_parse --item x
  run _bo_validate
  assert_failure
  assert_output $'Invalid value:\n\n--item x (choices: )'
  run _bo_complete -- --item ''
  assert_output ''
}

@test "C09 all types compose with required multi implicit defaults and positional cardinalities" {
  setup_git_repo
  local type value mode bad_default='unvalidated fallback'
  local -a types=(string integer float file directory choice git-commitish git-range)
  local -a values=('literal text' -2 -2.5 "$BATS_TEST_TMPDIR/file.txt" "$BATS_TEST_TMPDIR" 1 HEAD HEAD~1..HEAD)
  local type_index
  for type_index in "${!types[@]}"; do
    type="${types[$type_index]}" value="${values[$type_index]}"
    for mode in scalar multi implicit default default_optional default_variadic required optional variadic passthrough; do
      (
        # shellcheck source=../../betteropts.sh
        source "$BETTEROPTS"
        case "$mode" in
          scalar) option item --item required "type=$type" choices=1,2 var=compat_value ;;
          multi) option item --item required multi "type=$type" choices=1,2 var=compat_value ;;
          implicit) option item --item required "implicit=$value" "type=$type" choices=1,2 var=compat_value ;;
          default) option item --item "default=$bad_default" "type=$type" choices=1,2 var=compat_value ;;
          default_optional) argument item optional "default=$bad_default" "type=$type" choices=1,2 var=compat_value ;;
          default_variadic) argument item variadic "default=$bad_default,second fallback" "type=$type" choices=1,2 var=compat_value ;;
          *) argument item "$mode" "type=$type" choices=1,2 var=compat_value ;;
        esac
        _bo_finalize_schema
        case "$mode" in
          scalar) _bo_parse --item "$value" ;;
          multi) _bo_parse --item "$value" "--item=$value" ;;
          implicit) _bo_parse --item ;;
          default*) _bo_parse ;;
          *) _bo_parse -- "$value" ;;
        esac
        _bo_assign_positionals
        _bo_validate
        _bo_apply_defaults
        _bo_populate
        if [[ "$mode" == default || "$mode" == default_optional ]]; then
          assert_equal "${compat_value-}" "$bad_default"
        elif [[ "$mode" == default_variadic ]]; then
          assert_equal "${#compat_value[@]}" 2
          assert_equal "${compat_value[0]}" "$bad_default"
          assert_equal "${compat_value[1]}" 'second fallback'
        elif [[ "$mode" == multi ]]; then
          assert_equal "${#compat_value[@]}" 2
          assert_equal "${compat_value[0]}" "$value"
          assert_equal "${compat_value[1]}" "$value"
        elif [[ "$mode" == passthrough ]]; then
          assert_equal "${#compat_value[@]}" 2
          assert_equal "${compat_value[0]}" --
          assert_equal "${compat_value[1]}" "$value"
        elif [[ "$mode" == variadic ]]; then
          assert_regex "$(declare -p compat_value)" '^declare -a '
          assert_equal "${#compat_value[@]}" 1
          assert_equal "${compat_value[0]}" "$value"
        else
          assert_equal "${compat_value-}" "$value"
        fi
      )
    done
  done
}

@test "C10 passthrough typing is accepted and advertised but never enforced" {
  argument item passthrough type=choice choices=1,2 var=compat_value help=opaque
  _bo_finalize_schema
  _bo_parse --not-a-choice
  _bo_assign_positionals
  _bo_validate
  _bo_populate
  assert_equal "${compat_value[0]}" --not-a-choice
  assert_equal "$(_bo_annotations item)" 'choices: 1, 2'
  run _bo_complete -- ''
  assert_output ''
}

@test "C11 positional spellings are accepted metadata but are not aliases" {
  argument item optional -n --number var=compat_value
  _bo_finalize_schema
  run _bo_parse --number 1
  assert_failure
  assert_output $'Unknown option:\n\n--number\n\nUse --help for usage.'
  _bo_parse 1
  _bo_assign_positionals
  _bo_populate
  assert_equal "${compat_value-}" 1
  assert_equal "$(_bo_usage_line)" 'compat [ITEM]'
  run _bo_complete -- --num
  assert_output ''
}

@test "C12 plain tokens do not trigger passthrough but unknown options do" {
  option item --item N var=compat_value
  argument extra passthrough
  _bo_parse operand --item 1 --unknown --item 2
  _bo_assign_positionals
  _bo_validate
  _bo_populate
  assert_equal "${compat_value-}" 1
  # shellcheck disable=SC2154 # populated dynamically by betteropts
  assert_equal "${extra[*]}" 'operand --unknown --item 2'
}

@test "C13 completion disagrees with parsing after an attached unknown passthrough option" {
  option item --item N
  argument extra passthrough
  _bo_parse --unknown=value --item 1
  _bo_assign_positionals
  assert_equal "${_bo_passthrough_values[*]}" '--unknown=value --item 1'
  run _bo_complete -- --unknown=value --it
  assert_output --item
  run _bo_complete -- --unknown --it
  assert_output ''
}

@test "C14 completion replays literal double dash incorrectly without passthrough" {
  option item --item N
  argument extra variadic type=choice choices=one,two
  _bo_parse -- --item 1
  _bo_assign_positionals
  assert_equal "${_bo_variadic_values[*]}" '--item 1'
  run _bo_complete -- -- --it
  assert_output --item
}

@test "C15 current attached values do not complete while earlier attachments replay" {
  option item --item N multi type=choice choices=one,two
  run _bo_complete -- --item=o
  assert_output ''
  run _bo_complete -- --item=one --item o
  assert_output one
}

@test "C16 empty values differ for options and scalar arguments" {
  option item --item required implicit= type=string var=compat_value
  argument other optional default=fallback type=integer
  _bo_finalize_schema
  _bo_parse --item ''
  _bo_assign_positionals
  _bo_validate
  _bo_apply_defaults
  _bo_populate
  assert_equal "${compat_value-}" ''
  assert_equal "${other-}" fallback
  # shellcheck source=../../betteropts.sh
  source "$BETTEROPTS"
  argument other required
  _bo_finalize_schema
  _bo_parse ''
  _bo_assign_positionals
  run _bo_validate
  assert_failure
  assert_output $'Missing required argument:\n\nOTHER'
}

@test "C17 spelling forms consume dash values verbatim and reject bundled or attached short forms" {
  flag verbose -v --verbose
  option item -n --number N var=compat_value
  _bo_finalize_schema
  _bo_parse --number --verbose
  _bo_populate
  assert_equal "${compat_value-}" --verbose
  assert_equal "${verbose-}" false
  _bo_parse -n --
  _bo_populate
  assert_equal "${compat_value-}" --
  local token
  for token in -n=1 -n1 -vn --verbose=true; do
    run _bo_parse "$token"
    assert_failure
    assert_output "Unknown option:

$token

Use --help for usage."
  done
}

@test "C18 repeated keys and aliases overwrite while metavar spellings depend on order" {
  option item -n -x --number --other N metavar=M type=integer type=string help=first help=last
  _bo_finalize_schema
  assert_equal "$(_bo_meta_get item short)" -x
  assert_equal "$(_bo_meta_get item long)" --other
  assert_equal "$(_bo_meta_get item metavar)" M
  assert_equal "$(_bo_meta_get item type)" string
  assert_equal "$(_bo_meta_get item help)" last
  run _bo_parse --number 1
  assert_failure
  assert_output --partial 'Unknown option:'
  option bad --bad metavar=M N
  run _bo_finalize_schema
  assert_failure
  assert_output "'N' is not a valid option modifier for 'bad'."
}

@test "C19 every constraining type rejects invalid values in each validated value path" {
  setup_git_repo
  local type mode
  for type in integer float file directory choice git-commitish git-range; do
    for mode in scalar multi implicit required optional variadic passthrough; do
      (
        # shellcheck source=../../betteropts.sh
        source "$BETTEROPTS"
        case "$mode" in
          scalar) option item --item "type=$type" choices=1,2 ;;
          multi) option item --item multi "type=$type" choices=1,2 ;;
          implicit) option item --item implicit=compat-invalid "type=$type" choices=1,2 ;;
          *) argument item "$mode" "type=$type" choices=1,2 ;;
        esac
        _bo_finalize_schema
        case "$mode" in
          scalar|multi) _bo_parse --item compat-invalid ;;
          implicit) _bo_parse --item ;;
          *) _bo_parse compat-invalid ;;
        esac
        _bo_assign_positionals
        run _bo_validate
        if [[ "$mode" == passthrough ]]; then
          assert_success
        else
          assert_failure
          assert_output --partial 'Invalid value:'
          assert_output --partial compat-invalid
        fi
      )
    done
  done
}

@test "C20 scalar repetitions validate only the final value while multi validates every occurrence" {
  option item --item type=integer
  _bo_parse --item invalid --item 1
  _bo_validate
  _bo_meta_set item multi true
  _bo_parse --item invalid --item 1
  run _bo_validate
  assert_failure
  assert_output $'Invalid value:\n\n--item invalid (must be an integer)'
  _bo_meta_set item multi false
  _bo_meta_set item implicit invalid
  _bo_parse --item --item=1
  _bo_validate
  assert_equal "${_bo_raw[item]}" 1
  _bo_meta_set item multi true
  _bo_parse --item --item=1
  run _bo_validate
  assert_failure
  assert_output $'Invalid value:\n\n--item invalid (must be an integer)'
}

@test "C21 missing cardinality unknown keys unknown types and extra barewords are rejected" {
  argument item
  run _bo_finalize_schema
  assert_failure
  assert_output "Argument 'item' must declare exactly one of required, optional, variadic, or passthrough (none given)."
  local kind token
  for kind in flag option argument; do
    for token in unknown=1 nonsense; do
      (
        # shellcheck source=../../betteropts.sh
        source "$BETTEROPTS"
        if [[ "$kind" == argument ]]; then
          argument item optional "$token"
        elif [[ "$kind" == option ]]; then
          option item N "$token"
        else
          flag item "$token"
        fi
        run _bo_finalize_schema
        assert_failure
        assert_output --partial "'$([[ "$token" == *=* ]] && printf unknown || printf nonsense)'"
      )
    done
  done
  run bash -c 'source "$1"; option other --other type=unknown; _bo_finalize_schema' compat "$BETTEROPTS"
  assert_failure
  assert_output "'unknown' is not a recognized type for option 'other'."
}

@test "C22 duplicate aliases and populated variables are accepted with different precedence" {
  flag first --same var=compat_value
  flag second --same var=compat_value
  _bo_finalize_schema
  _bo_parse --same
  assert_equal "${_bo_provided[first]-}" true
  assert_equal "${_bo_provided[second]-}" ''
  _bo_populate
  assert_equal "${compat_value-}" false
}

@test "C23 empty scalar arguments skip typing but empty variadic and option values are validated" {
  argument item optional type=integer
  _bo_parse ''
  _bo_assign_positionals
  _bo_validate
  _bo_meta_set item cardinality variadic
  _bo_parse ''
  _bo_assign_positionals
  run _bo_validate
  assert_failure
  assert_output $'Invalid value:\n\nITEM  (must be an integer)'
  option other --other type=integer
  _bo_parse --other=
  _bo_assign_positionals
  run _bo_validate
  assert_failure
  assert_output $'Invalid value:\n\n--other  (must be an integer)'
}

@test "C28 a preserved delimiter can fill an earlier positional before the passthrough tail" {
  argument first required
  argument extra passthrough
  _bo_finalize_schema
  _bo_parse -- operand
  _bo_assign_positionals
  _bo_validate
  _bo_populate
  assert_equal "${first-}" --
  assert_equal "${extra[*]}" operand
}

@test "C29 file completion includes directories although file validation rejects them" {
  cd "$BATS_TEST_TMPDIR"
  mkdir compat-dir
  : > compat-file
  option item --item type=file
  run _bo_complete -- --item compat-
  assert_success
  assert_line compat-file
  assert_line compat-dir
  _bo_parse --item compat-dir
  run _bo_validate
  assert_failure
  assert_output $'Invalid value:\n\n--item compat-dir (no such file)'
}
