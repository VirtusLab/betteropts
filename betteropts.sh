#!/usr/bin/env bash
# BetterOpts - a pure Bash runtime library for declarative CLI argument parsing.
#
# See DESIGN.MD for the full specification. Where the spec leaves a detail
# unstated, the choice made here is noted inline.
#
# Public API: summary, description, flag, option, argument, betteropts_parse.
# Everything else (anything prefixed `_bo_`) is a private implementation detail.

# ---------------------------------------------------------------------------
# Schema
#
# The CLI schema is the single source of truth consumed by the parser,
# validator, help/usage generators, and completion engine. Storage is an
# implementation detail: ordered name lists plus a "name.field" associative
# array, reached only through the _bo_meta_* accessor functions below.
# ---------------------------------------------------------------------------

_bo_summary=""
_bo_description=""
_bo_flags=()
_bo_options=()
_bo_arguments=()
declare -gA _bo_meta=()

_bo_meta_set() {
  local name="$1" field="$2" value="$3"
  _bo_meta["${name}.${field}"]="$value"
}

_bo_meta_get() {
  local name="$1" field="$2"
  printf '%s' "${_bo_meta["${name}.${field}"]:-}"
}

_bo_meta_has() {
  local name="$1" field="$2"
  [[ -n "${_bo_meta["${name}.${field}"]+set}" ]]
}

summary() {
  _bo_summary="$1"
}

description() {
  _bo_description="$1"
}

# Shared declaration-token parser for flag/option/argument.
#
# Recognizes:
#   --xxx        -> long flag name
#   -x           -> short flag name
#   key=value    -> attribute
#   bareword     -> cardinality keyword (required/optional/variadic) or,
#                   for options, the metavar (first non-keyword bareword)
_bo_declare() {
  local kind="$1" name="$2"
  shift 2

  _bo_meta_set "$name" var "$name"
  _bo_meta_set "$name" short ""
  _bo_meta_set "$name" long ""
  _bo_meta_set "$name" required "false"

  while [[ $# -gt 0 ]]; do
    local tok="$1"
    case "$tok" in
      --*)
        _bo_meta_set "$name" long "$tok"
        ;;
      -?*)
        _bo_meta_set "$name" short "$tok"
        ;;
      *=*)
        _bo_meta_set "$name" "${tok%%=*}" "${tok#*=}"
        ;;
      required|optional|variadic)
        if [[ "$kind" == "argument" ]]; then
          _bo_meta_set "$name" cardinality "$tok"
        else
          _bo_meta_set "$name" required "true"
        fi
        ;;
      *)
        if [[ "$kind" == "option" ]] && ! _bo_meta_has "$name" metavar; then
          _bo_meta_set "$name" metavar "$tok"
        fi
        ;;
    esac
    shift
  done
}

flag() {
  local name="$1"
  shift
  _bo_declare flag "$name" "$@"
  _bo_meta_set "$name" kind "flag"
  _bo_flags+=("$name")
}

option() {
  local name="$1"
  shift
  _bo_declare option "$name" "$@"
  _bo_meta_set "$name" kind "option"
  _bo_options+=("$name")
}

argument() {
  local name="$1"
  shift
  _bo_declare argument "$name" "$@"
  _bo_meta_set "$name" kind "argument"
  _bo_arguments+=("$name")
}

# Validates the schema itself (not user input). Called once at the start of
# betteropts_parse. Returns non-zero and prints to stderr on a broken schema.
_bo_finalize_schema() {
  local name variadic_seen=false i last_index=$(( ${#_bo_arguments[@]} - 1 ))

  for i in "${!_bo_arguments[@]}"; do
    name="${_bo_arguments[$i]}"
    if [[ "$(_bo_meta_get "$name" cardinality)" == "variadic" ]]; then
      if [[ "$variadic_seen" == "true" ]]; then
        echo "Only one variadic argument is allowed." >&2
        return 1
      fi
      variadic_seen=true
      if [[ "$i" -ne "$last_index" ]]; then
        echo "The variadic argument must be the last declared argument." >&2
        return 1
      fi
    fi
  done

  return 0
}

# ---------------------------------------------------------------------------
# Error Handling
#
# Internal functions never call `exit`; they print to stderr and return
# non-zero. Only the public betteropts_parse translates a failure into a
# process exit. This keeps every internal function unit-testable in-process.
# ---------------------------------------------------------------------------

# Prints "<label>:\n\n<body>" optionally followed by a blank line and a
# trailer, matching every error format shown in DESIGN.MD.
_bo_print_error() {
  local label="$1" body="$2" trailer="${3:-}"
  printf '%s:\n\n%s\n' "$label" "$body" >&2
  if [[ -n "$trailer" ]]; then
    printf '\n%s\n' "$trailer" >&2
  fi
}

# The flag/option identifier shown in messages: its long form, or its short
# form when no long form was declared.
_bo_display_flag() {
  local name="$1" long short
  long="$(_bo_meta_get "$name" long)"
  short="$(_bo_meta_get "$name" short)"
  if [[ -n "$long" ]]; then
    printf '%s' "$long"
  else
    printf '%s' "$short"
  fi
}

# The argument identifier shown in messages: its declared name, uppercased.
_bo_display_argument() {
  local name="$1"
  printf '%s' "${name^^}"
}

_bo_die_unknown_option() {
  _bo_print_error "Unknown option" "$1" "Use --help for usage."
}

_bo_die_missing_value() {
  _bo_print_error "Missing value" "$(_bo_display_flag "$1")"
}

_bo_die_unexpected_argument() {
  _bo_print_error "Unexpected argument" "$1"
}

_bo_die_missing_required_argument() {
  _bo_print_error "Missing required argument" "$(_bo_display_argument "$1")"
}

_bo_die_missing_required_option() {
  _bo_print_error "Missing required option" "$(_bo_display_flag "$1")"
}

# $1 = display identifier (a flag form or an uppercased argument name)
# $2 = the offending raw value
# $3 = human-readable reason, e.g. "must be an integer"
_bo_die_invalid_value() {
  _bo_print_error "Invalid value" "$1 $2 ($3)"
}

# ---------------------------------------------------------------------------
# Parser
#
# Converts argv into raw (unvalidated) values: which flags/options were
# provided and their raw string values, plus the leftover positional
# tokens. Positional-to-argument assignment is a second pass
# (_bo_assign_positionals) since it depends on the full token list.
# ---------------------------------------------------------------------------

declare -gA _bo_provided=()
declare -gA _bo_raw=()
declare -ga _bo_positional_tokens=()
declare -ga _bo_variadic_values=()

_bo_is_flag() {
  [[ "$(_bo_meta_get "$1" kind)" == "flag" ]]
}

_bo_find_by_long() {
  local tok="$1" name
  for name in "${_bo_flags[@]}" "${_bo_options[@]}"; do
    if [[ "$(_bo_meta_get "$name" long)" == "$tok" ]]; then
      printf '%s' "$name"
      return 0
    fi
  done
  return 1
}

_bo_find_by_short() {
  local tok="$1" name
  for name in "${_bo_flags[@]}" "${_bo_options[@]}"; do
    if [[ "$(_bo_meta_get "$name" short)" == "$tok" ]]; then
      printf '%s' "$name"
      return 0
    fi
  done
  return 1
}

_bo_parse() {
  _bo_provided=()
  _bo_raw=()
  _bo_positional_tokens=()

  local args=("$@") after_dashdash=false
  local i=0 n=${#args[@]}

  while (( i < n )); do
    local tok="${args[$i]}"

    if [[ "$after_dashdash" == "true" ]]; then
      _bo_positional_tokens+=("$tok")
      i=$((i + 1))
      continue
    fi

    if [[ "$tok" == "--" ]]; then
      after_dashdash=true
      i=$((i + 1))
      continue
    fi

    if [[ "$tok" == --*=* ]]; then
      local long="${tok%%=*}" value="${tok#*=}" name
      if ! name="$(_bo_find_by_long "$long")" || _bo_is_flag "$name"; then
        _bo_die_unknown_option "$tok"
        return 1
      fi
      _bo_provided[$name]="true"
      _bo_raw[$name]="$value"
      i=$((i + 1))
      continue
    fi

    if [[ "$tok" == --* ]]; then
      local name
      if ! name="$(_bo_find_by_long "$tok")"; then
        _bo_die_unknown_option "$tok"
        return 1
      fi
      if _bo_is_flag "$name"; then
        _bo_provided[$name]="true"
        i=$((i + 1))
      else
        if (( i + 1 >= n )); then
          _bo_die_missing_value "$name"
          return 1
        fi
        _bo_provided[$name]="true"
        _bo_raw[$name]="${args[$((i + 1))]}"
        i=$((i + 2))
      fi
      continue
    fi

    if [[ "$tok" == -?* ]]; then
      local name
      if ! name="$(_bo_find_by_short "$tok")"; then
        _bo_die_unknown_option "$tok"
        return 1
      fi
      if _bo_is_flag "$name"; then
        _bo_provided[$name]="true"
        i=$((i + 1))
      else
        if (( i + 1 >= n )); then
          _bo_die_missing_value "$name"
          return 1
        fi
        _bo_provided[$name]="true"
        _bo_raw[$name]="${args[$((i + 1))]}"
        i=$((i + 2))
      fi
      continue
    fi

    _bo_positional_tokens+=("$tok")
    i=$((i + 1))
  done

  return 0
}

# Maps the leftover positional tokens onto declared argument slots, in
# declaration order. A trailing variadic argument consumes every remaining
# token; otherwise, more tokens than declared slots is an error.
_bo_assign_positionals() {
  _bo_variadic_values=()

  local idx=0 total=${#_bo_positional_tokens[@]}
  local name cardinality

  for name in "${_bo_arguments[@]}"; do
    cardinality="$(_bo_meta_get "$name" cardinality)"
    if [[ "$cardinality" == "variadic" ]]; then
      while (( idx < total )); do
        _bo_variadic_values+=("${_bo_positional_tokens[$idx]}")
        idx=$((idx + 1))
      done
    elif (( idx < total )); then
      _bo_raw[$name]="${_bo_positional_tokens[$idx]}"
      idx=$((idx + 1))
    fi
  done

  if (( idx < total )); then
    _bo_die_unexpected_argument "${_bo_positional_tokens[$idx]}"
    return 1
  fi

  return 0
}

# ---------------------------------------------------------------------------
# Validation
#
# Checks required options/arguments are present and that every provided raw
# value matches its declared type. Runs after parsing and before defaults are
# applied (a default is trusted as-is; it is never itself validated).
# ---------------------------------------------------------------------------

_bo_choice_matches() {
  local value="$1" choices="$2"
  local IFS=','
  local -a list=($choices)
  local c
  for c in "${list[@]}"; do
    [[ "$c" == "$value" ]] && return 0
  done
  return 1
}

# $1 = display identifier, $2 = raw value, $3 = declared type, $4 = choices csv
_bo_validate_type() {
  local ident="$1" value="$2" type="$3" choices="$4"
  case "$type" in
    integer)
      [[ "$value" =~ ^-?[0-9]+$ ]] || {
        _bo_die_invalid_value "$ident" "$value" "must be an integer"
        return 1
      }
      ;;
    float)
      [[ "$value" =~ ^-?[0-9]+(\.[0-9]+)?$ ]] || {
        _bo_die_invalid_value "$ident" "$value" "must be a number"
        return 1
      }
      ;;
    file)
      [[ -f "$value" ]] || {
        _bo_die_invalid_value "$ident" "$value" "no such file"
        return 1
      }
      ;;
    directory)
      [[ -d "$value" ]] || {
        _bo_die_invalid_value "$ident" "$value" "no such directory"
        return 1
      }
      ;;
    choice)
      _bo_choice_matches "$value" "$choices" || {
        _bo_die_invalid_value "$ident" "$value" "choices: ${choices//,/, }"
        return 1
      }
      ;;
    *)
      ;;
  esac
  return 0
}

_bo_validate() {
  local name cardinality

  for name in "${_bo_options[@]}"; do
    if [[ "$(_bo_meta_get "$name" required)" == "true" && -z "${_bo_provided[$name]:-}" ]]; then
      _bo_die_missing_required_option "$name"
      return 1
    fi
  done

  for name in "${_bo_arguments[@]}"; do
    cardinality="$(_bo_meta_get "$name" cardinality)"
    if [[ "$cardinality" == "required" && -z "${_bo_raw[$name]:-}" ]]; then
      _bo_die_missing_required_argument "$name"
      return 1
    fi
  done

  for name in "${_bo_options[@]}"; do
    if [[ -n "${_bo_provided[$name]:-}" ]]; then
      _bo_validate_type "$(_bo_display_flag "$name")" "${_bo_raw[$name]}" \
        "$(_bo_meta_get "$name" type)" "$(_bo_meta_get "$name" choices)" || return 1
    fi
  done

  for name in "${_bo_arguments[@]}"; do
    cardinality="$(_bo_meta_get "$name" cardinality)"
    if [[ "$cardinality" == "variadic" ]]; then
      local value
      for value in "${_bo_variadic_values[@]}"; do
        _bo_validate_type "$(_bo_display_argument "$name")" "$value" \
          "$(_bo_meta_get "$name" type)" "$(_bo_meta_get "$name" choices)" || return 1
      done
    elif [[ -n "${_bo_raw[$name]:-}" ]]; then
      _bo_validate_type "$(_bo_display_argument "$name")" "${_bo_raw[$name]}" \
        "$(_bo_meta_get "$name" type)" "$(_bo_meta_get "$name" choices)" || return 1
    fi
  done

  return 0
}

# ---------------------------------------------------------------------------
# Defaults
#
# Applied after validation and before variable population: an omitted
# option that declares a default is filled in with that default value.
# ---------------------------------------------------------------------------

_bo_apply_defaults() {
  local name
  for name in "${_bo_options[@]}"; do
    if [[ -z "${_bo_provided[$name]:-}" ]] && _bo_meta_has "$name" default; then
      _bo_raw[$name]="$(_bo_meta_get "$name" default)"
    fi
  done
}
