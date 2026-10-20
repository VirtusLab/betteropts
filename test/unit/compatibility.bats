#!/usr/bin/env bats
# Bats isolates tests; mutations in one test's subshell cannot affect another.
# shellcheck disable=SC2030,SC2031,SC2154

load '../../support/bats-support/load'
load '../../support/bats-assert/load'
load '../helpers/git_repo'

set -euo pipefail

BETTEROPTS="$BATS_TEST_DIRNAME/../../betteropts.sh"

setup() {
  # shellcheck source=../../betteropts.sh
  source "$BETTEROPTS"
  _bo_command_name=compat
  COMPAT_DIMENSIONS=(required optional variadic passthrough multi type choices default implicit var help metavar bare short long fields field_type field_choices)
  COMPAT_FIELD_START=15
  COMPAT_TOKENS=(required optional variadic passthrough multi type=integer 'choices=1,2' default=1 implicit=1 var=compat_value help=example metavar=N N -n --number 'fields=left,right' left.type=choice 'left.choices=1,2')
}

# Independent applicability inventory and named pair exclusions from README.
# If two tokens are independently invalid, either relevant rejection is valid;
# schema diagnostic priority is deliberately not part of the matrix contract.
compat_expected() {
  local kind="$1" context="$2" dimension token allowed first="${3-}" second="${4-}"
  local has_fields=false has_field_type=false has_field_choices=false
  shift 2
  COMPAT_ERRORS=()
  case "$kind" in
    flag) allowed=' var help short long ' ;;
    option) allowed=' required multi type choices default implicit var help metavar bare short long fields field_type field_choices ' ;;
    argument) allowed=' required optional variadic passthrough type choices default var help short long ' ;;
    *) return 1 ;;
  esac
  if [[ "$context" == record ]]; then
    has_fields=true has_field_type=true has_field_choices=true
    if [[ "$kind" != option ]]; then
      for token in fields left.type left.choices; do
        COMPAT_ERRORS+=("'$token' is not a recognized attribute for $kind 'item'.")
      done
    fi
  fi
  for dimension in "$@"; do
    case "$dimension" in
      fields) has_fields=true ;;
      field_type) has_field_type=true ;;
      field_choices) has_field_choices=true ;;
      *) ;;
    esac
    [[ "$allowed" == *" $dimension "* ]] && continue
    token="$dimension"
    case "$dimension" in
      bare) token=N ;;
      field_type) token=left.type ;;
      field_choices) token=left.choices ;;
      *) ;;
    esac
    case "$dimension" in
      type|choices|default|implicit|metavar|fields|field_type|field_choices)
        COMPAT_ERRORS+=("'$token' is not a recognized attribute for $kind 'item'.") ;;
      *) COMPAT_ERRORS+=("'$token' is not a valid $kind modifier for 'item'.") ;;
    esac
  done
  (( ${#COMPAT_ERRORS[@]} > 0 )) && return 0
  if [[ "$kind" == option ]]; then
    if [[ "$has_fields" == true ]]; then
      for dimension in "$@"; do
        token="$dimension"
        [[ "$dimension" == bare ]] && token=metavar
        case "$dimension" in
          type|choices|default|implicit|metavar|bare)
            COMPAT_ERRORS+=("Option 'item' cannot combine fields= with $token=.") ;;
          *) ;;
        esac
      done
      (( ${#COMPAT_ERRORS[@]} > 0 )) && return 0
      if [[ "$has_field_choices" == true && "$has_field_type" == false ]]; then
        COMPAT_ERRORS+=("Field 'left' of option 'item' requires type=choice for choices=.")
      elif [[ "$has_field_type" == true && "$has_field_choices" == false ]]; then
        COMPAT_ERRORS+=("Field 'left' of option 'item' requires nonempty choices=.")
      fi
    elif [[ "$has_field_type" == true || "$has_field_choices" == true ]]; then
      COMPAT_ERRORS+=("Option 'item' requires fields= for field attributes.")
    fi
  fi
  (( ${#COMPAT_ERRORS[@]} > 0 )) && return 0
  if [[ "$kind" == argument && ( "$first" == passthrough || "$second" == passthrough ) ]]; then
    for dimension in "$@"; do
      case "$dimension" in
        type|choices) COMPAT_ERRORS+=("Passthrough argument 'item' cannot declare $dimension=.") ;;
        *) ;;
      esac
    done
  fi
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
  local kind="$1" context="$2" dimension cardinality=false
  local -a tokens=()
  shift 2
  # shellcheck source=../../betteropts.sh
  source "$BETTEROPTS"
  if [[ "$context" == record ]]; then
    tokens=('fields=left,right' left.type=choice 'left.choices=1,2')
  fi
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
  local kind="$1" context="$2" index actual expected actual_status=0
  local -a dimensions=()
  shift 2
  for index in "$@"; do dimensions+=("${COMPAT_DIMENSIONS[$index]}"); done
  compat_expected "$kind" "$context" "${dimensions[@]}"
  # Expected schema failures are captured and checked below.
  # shellcheck disable=SC2310
  actual="$(compat_schema "$kind" "$context" "$@" 2>&1)" || actual_status=$?
  if [[ "${#COMPAT_ERRORS[@]}" == 0 ]]; then
    if [[ "$actual_status" != 0 || -n "$actual" ]]; then
      printf 'Expected accepted schema: %s context=%s %s; status=%s output=%s\n' "$kind" "$context" "${dimensions[*]}" "$actual_status" "$actual" >&2
      return 1
    fi
  else
    if [[ "$actual_status" == 1 ]]; then
      for expected in "${COMPAT_ERRORS[@]}"; do [[ "$actual" == "$expected" ]] && return 0; done
    fi
    printf 'Wrong rejection: %s context=%s %s; status=%s output=%s; expected one of=%s\n' "$kind" "$context" "${dimensions[*]}" "$actual_status" "$actual" "${COMPAT_ERRORS[*]}" >&2
    return 1
  fi
}

@test "C01 every declaration dimension has checked applicability for every kind" {
  local kind i
  for kind in flag option argument; do
    for i in "${!COMPAT_DIMENSIONS[@]}"; do compat_check "$kind" plain "$i"; done
  done
}

compat_pairs() {
  local kind="$1" i j
  for i in "${!COMPAT_DIMENSIONS[@]}"; do
    for j in "${!COMPAT_DIMENSIONS[@]}"; do compat_check "$kind" plain "$i" "$j"; done
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
        if [[ "$mode" == passthrough ]]; then
          run _bo_finalize_schema
          assert_failure
          assert_output "Passthrough argument 'item' cannot declare type=."
          exit 0
        fi
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

@test "C10 passthrough rejects type and choices attributes but accepts a raw untyped tail" {
  local attribute
  for attribute in type=string type= choices= choices=one,two; do
    (
      # shellcheck source=../../betteropts.sh
      source "$BETTEROPTS"
      argument item passthrough "$attribute" var=compat_value
      run _bo_finalize_schema
      assert_failure
      assert_output "Passthrough argument 'item' cannot declare ${attribute%%=*}=."
    )
  done
  argument item passthrough var=compat_value help=opaque
  _bo_finalize_schema
  _bo_parse --not-a-choice
  _bo_assign_positionals
  _bo_validate
  _bo_populate
  assert_equal "${compat_value[0]}" --not-a-choice
  assert_equal "$(_bo_annotations item)" ''
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

@test "C13 completion agrees with parsing after an attached unknown passthrough option" {
  option item --item N
  argument extra passthrough
  _bo_parse --unknown=value --item 1
  _bo_assign_positionals
  assert_equal "${_bo_passthrough_values[*]}" '--unknown=value --item 1'
  run _bo_complete -- --unknown=value --it
  assert_output ''
  run _bo_complete -- --unknown --it
  assert_output ''
}

@test "C14 completion honors literal double dash and keeps the correct positional slot" {
  option item --item N
  argument extra variadic type=choice choices=one,two
  _bo_parse -- --item 1
  _bo_assign_positionals
  assert_equal "${_bo_variadic_values[*]}" '--item 1'
  run _bo_complete -- -- --it
  assert_output ''
  run _bo_complete -- -- o
  assert_output one
  # A marker is syntax, not the first positional value.
  # shellcheck source=../../betteropts.sh
  source "$BETTEROPTS"
  argument first required type=choice choices=first
  argument second optional type=choice choices=second
  run _bo_complete -- -- ''
  assert_output first
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
  _bo_meta_get item short metadata_value
  assert_equal "$metadata_value" -x
  _bo_meta_get item long metadata_value
  assert_equal "$metadata_value" --other
  _bo_meta_get item metavar metadata_value
  assert_equal "$metadata_value" M
  _bo_meta_get item type metadata_value
  assert_equal "$metadata_value" string
  _bo_meta_get item help metadata_value
  assert_equal "$metadata_value" last
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
        if [[ "$mode" == passthrough ]]; then
          run _bo_finalize_schema
          assert_failure
          assert_output "Passthrough argument 'item' cannot declare type=."
          exit 0
        fi
        _bo_finalize_schema
        case "$mode" in
          scalar|multi) _bo_parse --item compat-invalid ;;
          implicit) _bo_parse --item ;;
          *) _bo_parse compat-invalid ;;
        esac
        _bo_assign_positionals
        run _bo_validate
        assert_failure
        assert_output --partial 'Invalid value:'
        assert_output --partial compat-invalid
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

@test "C30 field axes have checked ordered pairs and repetitions in an explicit record context" {
  local kind i j checked=0
  # This is a conditional context, not evidence that two attributes alone
  # suffice: fields=left,right and a complete choice field precede the pair.
  for kind in flag option argument; do
    for i in "${!COMPAT_DIMENSIONS[@]}"; do
      for j in "${!COMPAT_DIMENSIONS[@]}"; do
        (( i < COMPAT_FIELD_START && j < COMPAT_FIELD_START )) && continue
        compat_check "$kind" record "$i" "$j"
        checked=$((checked + 1))
      done
    done
  done
  assert_equal "$checked" "$((3 * (${#COMPAT_DIMENSIONS[@]} ** 2 - COMPAT_FIELD_START ** 2)))"
}

compat_finish() {
  _bo_assign_positionals
  _bo_validate
  _bo_apply_defaults
  _bo_populate
}

@test "C31 repeated field keys use the final schema while unknown and orphaned attributes remain errors" {
  option item --item fields=discarded fields=left,right \
    left.type=integer left.type=choice left.choices=bad left.choices=1,2
  _bo_finalize_schema
  _bo_parse --item 1 'kept text'
  compat_finish
  assert_equal "${item_left-}" 1
  assert_equal "${item_right-}" 'kept text'
  [[ ! -v item_discarded ]]
  local tokens
  for tokens in orphan typo invalid_choice; do
    (
      # shellcheck source=../../betteropts.sh
      source "$BETTEROPTS"
      case "$tokens" in
        orphan) option item --item fields=old old.type=string fields=new ;;
        typo) option item --item fields=left left.typo=x left.type=string ;;
        invalid_choice) option item --item fields=left left.choices=1,2 left.type=choice left.type=integer ;;
        *) return 1 ;;
      esac
      run _bo_finalize_schema
      assert_failure
      case "$tokens" in
        orphan) assert_output "Unknown field 'old' for option 'item'." ;;
        typo) assert_output "'left.typo' is not a recognized attribute for option 'item'." ;;
        invalid_choice) assert_output "Field 'left' of option 'item' requires type=choice for choices=." ;;
        *) return 1 ;;
      esac
    )
  done
}

@test "C32 every field type preserves values in optional required scalar and repeated records" {
  setup_git_repo
  local type_index mode type value
  local -a types=(string integer float file directory choice git-commitish git-range)
  local -a values=('literal text' -2 -2.5 "$BATS_TEST_TMPDIR/file.txt" "$BATS_TEST_TMPDIR" 1 HEAD HEAD..HEAD)
  for type_index in "${!types[@]}"; do
    type="${types[$type_index]}" value="${values[$type_index]}"
    for mode in scalar required multi required_multi; do
      (
        # shellcheck source=../../betteropts.sh
        source "$BETTEROPTS"
        local -a modifiers=()
        [[ "$mode" == required* ]] && modifiers+=(required)
        [[ "$mode" == *multi ]] && modifiers+=(multi)
        [[ "$type" == choice ]] && modifiers+=('value.choices=1,2')
        option item -n --item fields=label,value,passage "value.type=$type" var=record "${modifiers[@]}"
        _bo_finalize_schema
        _bo_parse --item first "$value" 'quoted passage' "--item=second" "$value" 'final passage'
        compat_finish
        if [[ "$mode" == *multi ]]; then
          assert_equal "${#record_value[@]}" 2
          assert_equal "${record_label[0]}" first
          assert_equal "${record_label[1]}" second
          assert_equal "${record_value[0]}" "$value"
          assert_equal "${record_value[1]}" "$value"
          assert_equal "${record_passage[1]}" 'final passage'
        else
          assert_equal "${record_label-}" second
          assert_equal "${record_value-}" "$value"
          assert_equal "${record_passage-}" 'final passage'
        fi
      )
    done
  done
}

@test "C33 every field type checks nonempty invalid and empty retained values with scalar and multi parity" {
  setup_git_repo
  local type mode sample
  for type in string integer float file directory choice git-commitish git-range; do
    for mode in scalar multi; do
      for sample in compat-invalid ''; do
        (
          # shellcheck source=../../betteropts.sh
          source "$BETTEROPTS"
          local -a modifiers=()
          [[ "$mode" == multi ]] && modifiers+=(multi)
          [[ "$type" == choice ]] && modifiers+=('value.choices=1,2')
          option item --item fields=key,value required "value.type=$type" "${modifiers[@]}"
          _bo_finalize_schema
          _bo_parse --item key "$sample"
          run _bo_validate
          if [[ "$type" == string ]]; then
            assert_success
          else
            assert_failure
            assert_output --partial '--item VALUE '
            assert_output --partial 'Invalid value:'
          fi
        )
      done
    done
  done
}

@test "C34 record scalars validate retained occurrences while repeated records validate each one" {
  option item --item fields=key,value value.type=integer
  _bo_finalize_schema
  _bo_parse --item old invalid --item=new -2
  compat_finish
  assert_equal "${item_key-}" new
  assert_equal "${item_value-}" -2
  _bo_meta_set item multi true
  _bo_parse --item old invalid --item=new -2
  run _bo_validate
  assert_failure
  assert_output $'Invalid value:\n\n--item VALUE invalid (must be an integer)'
}

@test "C35 several record arities coexist with ordinary required default implicit repeated and flag options" {
  flag verbose -v --verbose
  option ordinary --ordinary required type=integer
  option jobs --jobs type=integer default=trusted-invalid-default
  option mode -m --mode MODE implicit=on default=off type=choice choices=on,off
  option tag -t --tag T multi type=choice choices=a,b
  argument source required type=integer
  option pair -p --pair required multi fields=key,value value.type=integer var=record
  option triple --triple fields=label,path,note path.type=directory var=entry
  option single --single fields=token
  argument destination optional default=unvalidated type=integer
  argument extra variadic type=integer default=unvalidated,also-unvalidated
  _bo_finalize_schema
  _bo_parse --single before --ordinary invalid -p first -1 10 --mode -v \
    --triple sample "$BATS_TEST_TMPDIR" 'literal note' --ordinary=2 -t a \
    --pair=second 3 -v --single=last -t b
  compat_finish
  assert_equal "${verbose-}" true
  assert_equal "${ordinary-}" 2
  assert_equal "${jobs-}" trusted-invalid-default
  assert_equal "${mode-}" on
  assert_equal "${tag[*]}" 'a b'
  assert_equal "${record_key[*]}" 'first second'
  assert_equal "${record_value[*]}" '-1 3'
  assert_equal "${entry_path-}" "$BATS_TEST_TMPDIR"
  assert_equal "${entry_note-}" 'literal note'
  assert_equal "${single_token-}" last
  assert_equal "${source-}" 10
  assert_equal "${destination-}" unvalidated
  assert_equal "${extra[*]}" 'unvalidated also-unvalidated'
  assert_equal "$(_bo_usage_line)" 'compat [--verbose] --ordinary VALUE [--jobs VALUE] [--mode[=MODE]] [--tag T]... --pair KEY VALUE [--pair KEY VALUE]... [--triple LABEL PATH NOTE] [--single TOKEN] SOURCE [DESTINATION] [EXTRA...]'
  _bo_parse --ordinary 2 10
  _bo_assign_positionals
  run _bo_validate
  assert_failure
  assert_output $'Missing required option:\n\n--pair'
  _bo_parse --pair only 1 10
  _bo_assign_positionals
  run _bo_validate
  assert_failure
  assert_output $'Missing required option:\n\n--ordinary'
}

@test "C36 record tokens do not occupy positional slots or change positional typing and default rules" {
  local mode
  for mode in required optional variadic passthrough; do
    (
      # shellcheck source=../../betteropts.sh
      source "$BETTEROPTS"
      option record --record fields=key,value multi value.type=integer
      local -a modifiers=()
      [[ "$mode" != passthrough ]] && modifiers+=(type=integer)
      [[ "$mode" == optional || "$mode" == variadic ]] && modifiers+=(default=trusted-invalid-default)
      argument item "$mode" "${modifiers[@]}"
      _bo_finalize_schema
      _bo_parse 1 --record first -2 --record=second 3
      compat_finish
      assert_equal "${record_key[*]}" 'first second'
      assert_equal "${record_value[*]}" '-2 3'
      assert_equal "${item[0]-}" 1
      _bo_parse --record first 2 ''
      _bo_assign_positionals
      run _bo_validate
      case "$mode" in
        required) assert_failure; assert_output $'Missing required argument:\n\nITEM' ;;
        variadic) assert_failure; assert_output --partial 'must be an integer' ;;
        optional|passthrough) assert_success ;;
        *) return 1 ;;
      esac
      if [[ "$mode" == optional || "$mode" == variadic ]]; then
        _bo_parse --record only 1
        compat_finish
        assert_equal "${item[0]-}" trusted-invalid-default
      elif [[ "$mode" == passthrough ]]; then
        _bo_parse --record only 1 --unknown=literal --record ignored 2
        compat_finish
        assert_equal "${record_key[*]}" only
        assert_equal "${item[*]}" '--unknown=literal --record ignored 2'
      fi
    )
  done
}

@test "C37 generated field output collisions reject every declaration kind in either declaration order" {
  local kind order
  for kind in flag option argument record; do
    for order in before after; do
      (
        # shellcheck source=../../betteropts.sh
        source "$BETTEROPTS"
        [[ "$order" == before ]] && option item --item fields=key,value var=record
        case "$kind" in
          flag) flag other --other var=record_value ;;
          option) option other --other var=record_value ;;
          argument) argument other optional var=record_value ;;
          record) option other --other fields=value var=record ;;
          *) return 1 ;;
        esac
        [[ "$order" == after ]] && option item --item fields=key,value var=record
        run _bo_finalize_schema
        assert_failure
        assert_output --partial "Field variable 'record_value'"
      )
    done
  done
  # The unused base prefix itself is not an output, so this is valid.
  option item --item fields=key,value var=record
  option base --base var=record
  _bo_finalize_schema
  _bo_parse --item k v --base scalar
  compat_finish
  assert_equal "${record-}" scalar
  assert_equal "${record_key-}" k
  assert_equal "${record_value-}" v
}

@test "C38 field shape type choice and prefix errors stay distinct from ordinary permissive metadata" {
  local bad
  for bad in list prefix attribute kind type empty_choices missing_choices inert_choices newline_list newline_prefix newline_type; do
    (
      # shellcheck source=../../betteropts.sh
      source "$BETTEROPTS"
      case "$bad" in
        list) option item --item fields=left,left ;;
        prefix) option item --item fields=left var=_bo_raw ;;
        attribute) option item --item fields=left left.default=1 ;;
        kind) argument item optional fields=left ;;
        type) option item --item fields=left left.type=int ;;
        empty_choices) option item --item fields=left left.type=choice left.choices= ;;
        missing_choices) option item --item fields=left left.type=choice ;;
        inert_choices) option item --item fields=left left.type=string left.choices=1,2 ;;
        newline_list) option item --item $'fields=left,right\n' ;;
        newline_prefix) option item --item fields=left $'var=result\n' ;;
        newline_type) option item --item fields=left $'left.type=integer\n' ;;
        *) return 1 ;;
      esac
      run _bo_finalize_schema
      assert_failure
      case "$bad" in
        list) assert_output "Duplicate field 'left' for option 'item'." ;;
        prefix|newline_prefix) assert_output --partial 'Invalid field variable prefix' ;;
        newline_list) assert_output --partial 'Invalid fields= list' ;;
        newline_type) assert_output --partial "is not a recognized type for field 'left'" ;;
        attribute) assert_output "'left.default' is not a recognized attribute for option 'item'." ;;
        kind) assert_output "'fields' is not a recognized attribute for argument 'item'." ;;
        type) assert_output "'int' is not a recognized type for field 'left' of option 'item'." ;;
        empty_choices|missing_choices) assert_output "Field 'left' of option 'item' requires nonempty choices=." ;;
        inert_choices) assert_output "Field 'left' of option 'item' requires type=choice for choices=." ;;
        *) return 1 ;;
      esac
    )
  done
}

@test "C39 completion distinguishes record fields mandatory scalar values and actual markers" {
  option record -r --record fields=key,value multi value.type=choice value.choices=alpha,beta
  option ordinary -n --ordinary N type=choice choices=one,two
  option implicit -i --implicit N implicit=one type=choice choices=one,two
  flag verbose -v --verbose
  argument first required type=choice choices=first
  argument second optional type=choice choices=second
  _bo_finalize_schema
  run _bo_complete -- --record -- a
  assert_output alpha
  run _bo_complete -- --record=-- b
  assert_output beta
  run _bo_complete -- -r --verbose alpha --ordinary -- --record next b
  assert_output beta
  run _bo_complete -- -i -r x alpha --ordinary=o --record another a
  assert_output alpha
  run _bo_complete -- --record x alpha -- ''
  assert_output first
  run _bo_complete -- --record x alpha -- first ''
  assert_output second
  run _bo_complete -- --record x alpha -- --ver
  assert_output ''
}

@test "C40 attached unknown options and attached flags stop completion before and after records" {
  option record --record fields=key,value value.type=choice value.choices=alpha,beta
  flag verbose --verbose
  argument first optional
  argument extra passthrough
  _bo_finalize_schema
  local token
  for token in --unknown=value --verbose=true; do
    _bo_parse "$token" --record k alpha
    _bo_assign_positionals
    assert_equal "${_bo_raw[first]}" "$token"
    assert_equal "${_bo_passthrough_values[*]}" '--record k alpha'
    run _bo_complete -- "$token" --rec
    assert_output ''
    run _bo_complete -- --record k alpha "$token" --rec
    assert_output ''
  done
  # The same tokens in a mandatory field slot remain literal field data.
  run _bo_complete -- --record --verbose=true a
  assert_output alpha
  run _bo_complete -- --record --unknown=value b
  assert_output beta
}

@test "C41 file field completion retains directory candidates and required default var metadata is not applied" {
  cd "$BATS_TEST_TMPDIR"
  mkdir compat-dir
  : > compat-file
  option record --record required fields=key,path var=verdict path.type=file
  option ordinary --ordinary required default=unvalidated type=choice choices=one,two var=other
  _bo_finalize_schema
  _bo_complete -- --record=key compat- > "$BATS_TEST_TMPDIR/completion-candidates"
  [[ ! -v verdict_path && ! -v other ]]
  [[ -z "${_bo_raw[ordinary]+set}" ]]
  run cat "$BATS_TEST_TMPDIR/completion-candidates"
  assert_success
  assert_line compat-dir
  assert_line compat-file
  _bo_parse --record key compat-dir
  run _bo_validate
  assert_failure
  assert_output $'Missing required option:\n\n--ordinary'
  _bo_parse --ordinary one --record key compat-dir
  run _bo_validate
  assert_failure
  assert_output $'Invalid value:\n\n--record PATH compat-dir (no such file)'
}

@test "C42 omitted Git fields need no repository while provided fields report the repository error" {
  mkdir "$BATS_TEST_TMPDIR/no-repository"
  cd "$BATS_TEST_TMPDIR/no-repository"
  local type
  for type in git-commitish git-range; do
    (
      # shellcheck source=../../betteropts.sh
      source "$BETTEROPTS"
      option item --item fields=key,value multi "value.type=$type"
      _bo_finalize_schema
      _bo_parse
      compat_finish
      assert_equal "${#item_value[@]}" 0
      _bo_parse --item key HEAD
      run _bo_validate
      assert_failure
      assert_output $'Not inside a git repository:\n\n--item VALUE HEAD'
    )
  done
}
