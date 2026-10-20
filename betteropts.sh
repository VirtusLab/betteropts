#!/usr/bin/env bash
# BetterOpts - a pure Bash runtime library for declarative CLI argument parsing.
#
# See DESIGN.MD for the full specification. Where the spec leaves a detail
# unstated, the choice made here is noted inline.
#
# Public API: summary, description, flag, option, argument, betteropts_parse.
# Everything else (anything prefixed `_bo_`) is a private implementation detail.

# ---------------------------------------------------------------------------
# Public API
#
# Runs the full execution lifecycle from DESIGN.MD: finalize the schema,
# handle built-in commands (-h/--help, --usage, --__complete), parse,
# validate, apply defaults, populate variables, return. Every other
# function in this file returns non-zero on failure instead of exiting, so
# this is the only place that calls `exit`.
# ---------------------------------------------------------------------------

betteropts_parse() {
  _bo_command_name="$(basename "$0")"

  _bo_finalize_schema || exit 1

  local tok
  for tok in "$@"; do
    [[ "$tok" == "--" ]] && break
    case "$tok" in
      -h | --help)
        _bo_help_text
        printf '\n'
        exit 0
        ;;
      --usage)
        _bo_usage_text
        printf '\n'
        exit 0
        ;;
      *) ;;
    esac
  done

  if [[ "${1:-}" == "--__complete" ]]; then
    shift
    _bo_complete "$@"
    exit 0
  fi

  _bo_parse "$@" || exit 1
  _bo_assign_positionals || exit 1
  _bo_validate || exit 1
  _bo_apply_defaults
  _bo_populate
}

# ---------------------------------------------------------------------------
# Schema
#
# The CLI schema is the single source of truth consumed by the parser,
# validator, help/usage generators, and completion engine. Storage is an
# implementation detail: ordered name lists plus an associative array, reached
# only through the _bo_meta_* accessor functions below.
# ---------------------------------------------------------------------------

_bo_summary=""
_bo_description=""
_bo_declaration_error=""
_bo_flags=()
_bo_options=()
_bo_flags_and_options=()
_bo_arguments=()
declare -gA _bo_meta=()

# Escaping percent signs before dots makes the component separator unique,
# independently of logical-ID characters or locale changes. Retrieval writes into
# the caller's variable: command substitution would strip trailing newlines.
# No getter locals may shadow that destination in Bash's dynamic scope.
_bo_meta_set() {
  set -- "${1//%/%25}" "${2//%/%25}" "$3"
  _bo_meta["${1//./%2E}.${2//./%2E}"]="$3"
}

_bo_meta_get() {
  set -- "${1//%/%25}" "${2//%/%25}" "$3"
  printf -v "$3" '%s' "${_bo_meta["${1//./%2E}.${2//./%2E}"]-}"
}

_bo_meta_has() {
  set -- "${1//%/%25}" "${2//%/%25}"
  [[ -n "${_bo_meta["${1//./%2E}.${2//./%2E}"]+set}" ]]
}

_bo_meta_is() {
  local _bo_meta_value
  _bo_meta_get "$1" "$2" _bo_meta_value
  [[ "$_bo_meta_value" == "$3" ]]
}

# Capture generated labels and logical IDs without command substitution's
# trailing-newline removal. Preserve status for lookups that may not match.
_bo_capture_text() {
  local _bo_capture_value _bo_capture_status
  _bo_capture_value="$("${@:2}"; _bo_capture_status=$?; printf '.'; exit "$_bo_capture_status")" &&
    _bo_capture_status=0 || _bo_capture_status=$?
  printf -v "$1" '%s' "${_bo_capture_value%.}"
  return "$_bo_capture_status"
}

summary() {
  _bo_summary="$1"
}

description() {
  _bo_description="$1"
}

# Whether `key` is a recognized key=value attribute for a declaration of the
# given kind, per README's per-kind modifier tables.
_bo_key_allowed() {
  local kind="$1" key="$2"
  case "$kind" in
    flag)
      case "$key" in
        help | var) return 0 ;;
        *) return 1 ;;
      esac
      ;;
    option)
      case "$key" in
        help | type | choices | default | var | metavar | implicit | fields) return 0 ;;
        *) [[ "$key" =~ ^[a-zA-Z_][a-zA-Z0-9_]*\.(type|choices)$ ]] ;;
      esac
      ;;
    argument)
      case "$key" in
        help | type | choices | default | var) return 0 ;;
        *) return 1 ;;
      esac
      ;;
    *) return 1 ;;
  esac
}

# Shared declaration-token parser for flag/option/argument.
#
# Recognizes:
#   --xxx        -> long flag name
#   -x           -> short flag name
#   key=value    -> attribute (must be in _bo_key_allowed's list for this
#                   kind; otherwise recorded as bad_key for
#                   _bo_finalize_schema to reject)
#   bareword     -> cardinality keyword (required/optional/variadic/
#                   passthrough), multi, or, for options, the metavar (first
#                   non-keyword bareword). A keyword not valid for this kind,
#                   or a bareword beyond an option's single metavar, is
#                   recorded as bad_keyword for _bo_finalize_schema to reject.
_bo_declare() {
  local kind="$1" name="$2" metadata
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
        local key="${tok%%=*}"
        if _bo_key_allowed "$kind" "$key"; then
          _bo_meta_set "$name" "$key" "${tok#*=}"
          if [[ "$key" == *.* ]]; then
            _bo_meta_get "$name" field_keys metadata
            _bo_meta_set "$name" field_keys "$metadata $key"
          fi
        else
          _bo_meta_set "$name" bad_key "$key"
        fi
        ;;
      required|optional|variadic|passthrough)
        if [[ "$kind" == "argument" ]]; then
          _bo_meta_set "$name" cardinality "$tok"
          _bo_meta_get "$name" cardinality_count metadata
          _bo_meta_set "$name" cardinality_count "$(( ${metadata:-0} + 1 ))"
        elif [[ "$kind" == "option" && "$tok" == "required" ]]; then
          _bo_meta_set "$name" required "true"
        else
          _bo_meta_set "$name" bad_keyword "$tok"
        fi
        ;;
      multi)
        if [[ "$kind" == "option" ]]; then
          _bo_meta_set "$name" multi "true"
        else
          _bo_meta_set "$name" bad_keyword "$tok"
        fi
        ;;
      *)
        if [[ "$kind" == "option" ]]; then
          if _bo_meta_has "$name" metavar; then
            _bo_meta_set "$name" bad_keyword "$tok"
          else
            _bo_meta_set "$name" metavar "$tok"
          fi
        else
          _bo_meta_set "$name" bad_keyword "$tok"
        fi
        ;;
    esac
    shift
  done
}

# Invalid names cannot enter associative storage; retain the first diagnostic
# for schema finalization so declarations keep their existing deferred-error API.
_bo_require_declaration_name() {
  if [[ $# -eq 1 ]]; then
    [[ -n "$_bo_declaration_error" ]] || _bo_declaration_error="Missing name for $1 declaration."
    return 1
  elif [[ -z "$2" ]]; then
    [[ -n "$_bo_declaration_error" ]] || _bo_declaration_error="Empty name for $1 declaration."
    return 1
  fi
}

flag() {
  _bo_require_declaration_name flag "$@" || return 0
  local name="$1"
  shift
  _bo_declare flag "$name" "$@"
  _bo_meta_set "$name" kind "flag"
  _bo_flags+=("$name")
  _bo_flags_and_options+=("$name")
}

option() {
  _bo_require_declaration_name option "$@" || return 0
  local name="$1"
  shift
  _bo_declare option "$name" "$@"
  _bo_meta_set "$name" kind "option"
  _bo_options+=("$name")
  _bo_flags_and_options+=("$name")
}

argument() {
  _bo_require_declaration_name argument "$@" || return 0
  local name="$1"
  shift
  _bo_declare argument "$name" "$@"
  _bo_meta_set "$name" kind "argument"
  _bo_arguments+=("$name")
}

# Fields remain schema metadata; consumers never inspect their storage.
_bo_field_names() {
  local fields
  _bo_meta_get "$1" fields fields
  printf '%s\n' "${fields//,/$'\n'}"
}

_bo_option_arity() {
  if _bo_meta_has "$1" fields; then
    local fields=() list
    _bo_meta_get "$1" fields list
    IFS=',' read -ra fields <<< "$list"
    printf '%s' "${#fields[@]}"
  else
    printf '1'
  fi
}

_bo_known_type() {
  case "$1" in
    string | integer | float | file | directory | choice | git-commitish | git-range) return 0 ;;
    *) return 1 ;;
  esac
}

_bo_finalize_fields() {
  local name="$1" fields field key type choices prefix output other other_field other_output field_keys
  local seen=()
  _bo_meta_get "$name" fields fields
  if [[ ! "$fields" =~ ^[a-zA-Z_][a-zA-Z0-9_]*(,[a-zA-Z_][a-zA-Z0-9_]*)*$ ]]; then
    echo "Invalid fields= list '$fields' for option '$name' (expected comma-separated shell identifiers)." >&2
    return 1
  fi
  for key in metavar type choices default implicit; do
    if _bo_meta_has "$name" "$key"; then
      echo "Option '$name' cannot combine fields= with $key=." >&2
      return 1
    fi
  done
  _bo_meta_get "$name" var prefix
  if [[ ! "$prefix" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ || "$prefix" == _bo || "$prefix" == _bo_* ]]; then
    echo "Invalid field variable prefix '$prefix' for option '$name'." >&2
    return 1
  fi
  while IFS= read -r field; do
    for key in "${seen[@]}"; do
      if [[ "$key" == "$field" ]]; then
        echo "Duplicate field '$field' for option '$name'." >&2
        return 1
      fi
    done
    seen+=("$field")
    _bo_meta_get "$name" "$field.type" type
    if _bo_meta_has "$name" "$field.type" && ! _bo_known_type "$type"; then
      echo "'$type' is not a recognized type for field '$field' of option '$name'." >&2
      return 1
    fi
    if _bo_meta_has "$name" "$field.choices" && [[ "$type" != choice ]]; then
      echo "Field '$field' of option '$name' requires type=choice for choices=." >&2
      return 1
    fi
    _bo_meta_get "$name" "$field.choices" choices
    if [[ "$type" == choice && -z "$choices" ]]; then
      echo "Field '$field' of option '$name' requires nonempty choices=." >&2
      return 1
    fi
    output="${prefix}_${field}"
    for other in "${_bo_flags_and_options[@]}" "${_bo_arguments[@]}"; do
      [[ "$other" == "$name" ]] && continue
      if _bo_meta_has "$other" fields; then
        while IFS= read -r other_field; do
          _bo_meta_get "$other" var other_output
          other_output+="_$other_field"
          if [[ "$output" == "$other_output" ]]; then
            echo "Field variable '$output' for option '$name' collides with '$other'." >&2
            return 1
          fi
        done < <(_bo_field_names "$other")
      elif _bo_meta_is "$other" var "$output"; then
        echo "Field variable '$output' for option '$name' collides with '$other'." >&2
        return 1
      fi
    done
  done < <(_bo_field_names "$name")
  local keys=()
  _bo_meta_get "$name" field_keys field_keys
  IFS=' ' read -ra keys <<< "$field_keys"
  for key in "${keys[@]}"; do
    field="${key%%.*}"
    if [[ ",$fields," != *",$field,"* ]]; then
      echo "Unknown field '$field' for option '$name'." >&2
      return 1
    fi
  done
}

_bo_validate_declaration_identity() {
  local _bo_schema_name="$1" _bo_schema_kind="$2" _bo_schema_value _bo_schema_key
  if ! _bo_meta_has "$_bo_schema_name" fields; then
    _bo_meta_get "$_bo_schema_name" var _bo_schema_value
    if [[ ! "$_bo_schema_value" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
      printf "Invalid output variable '%s' for %s '%s' (expected a shell identifier).\n" "$_bo_schema_value" "$_bo_schema_kind" "$_bo_schema_name" >&2
      return 1
    fi
  fi
  if [[ "$_bo_schema_kind" == argument ]]; then
    _bo_meta_get "$_bo_schema_name" cardinality _bo_schema_value
    if [[ "$_bo_schema_value" == passthrough ]]; then
      for _bo_schema_key in type choices; do
        if _bo_meta_has "$_bo_schema_name" "$_bo_schema_key"; then
          printf "Passthrough argument '%s' cannot declare %s=.\n" "$_bo_schema_name" "$_bo_schema_key" >&2
          return 1
        fi
      done
    fi
  else
    for _bo_schema_key in short long; do
      _bo_meta_get "$_bo_schema_name" "$_bo_schema_key" _bo_schema_value
      case "$_bo_schema_value" in
        -h|--help|--usage|--__complete)
          printf "Reserved spelling '%s' for %s '%s'.\n" "$_bo_schema_value" "$_bo_schema_kind" "$_bo_schema_name" >&2
          return 1
          ;;
        *) ;;
      esac
      if [[ "$_bo_schema_key" == long && "$_bo_schema_value" == *=* ]]; then
        printf "Invalid long spelling '%s' for %s '%s' (must not contain '=').\n" "$_bo_schema_value" "$_bo_schema_kind" "$_bo_schema_name" >&2
        return 1
      fi
    done
  fi
}

# Validates the schema itself (not user input). Called once at the start of
# betteropts_parse. Returns non-zero and prints to stderr on a broken schema.
_bo_finalize_schema() {
  local name kind cardinality count metadata collects_rest_count=0 optional_seen=false i last_index=$(( ${#_bo_arguments[@]} - 1 ))

  if [[ -n "$_bo_declaration_error" ]]; then
    printf '%s\n' "$_bo_declaration_error" >&2
    return 1
  fi

  for name in "${_bo_flags_and_options[@]}" "${_bo_arguments[@]}"; do
    _bo_meta_get "$name" kind kind
    if _bo_meta_has "$name" bad_key; then
      _bo_meta_get "$name" bad_key metadata
      echo "'$metadata' is not a recognized attribute for $kind '$name'." >&2
      return 1
    fi
    if _bo_meta_has "$name" bad_keyword; then
      _bo_meta_get "$name" bad_keyword metadata
      echo "'$metadata' is not a valid $kind modifier for '$name'." >&2
      return 1
    fi
    _bo_validate_declaration_identity "$name" "$kind" || return 1
    _bo_meta_get "$name" type metadata
    if _bo_meta_has "$name" type && ! _bo_known_type "$metadata"; then
      echo "'$metadata' is not a recognized type for $kind '$name'." >&2
      return 1
    fi
  done

  for name in "${_bo_options[@]}"; do
    if _bo_meta_has "$name" fields; then
      _bo_finalize_fields "$name" || return 1
    elif _bo_meta_has "$name" field_keys; then
      echo "Option '$name' requires fields= for field attributes." >&2
      return 1
    fi
    if _bo_meta_is "$name" multi "true" && _bo_meta_has "$name" default; then
      echo "A multi option cannot declare a default." >&2
      return 1
    fi
  done

  for name in "${_bo_arguments[@]}"; do
    _bo_meta_get "$name" cardinality cardinality
    if [[ "$cardinality" == "variadic" || "$cardinality" == "passthrough" ]]; then
      collects_rest_count=$(( collects_rest_count + 1 ))
    fi
  done
  if [[ "$collects_rest_count" -gt 1 ]]; then
    echo "Only one variadic or passthrough argument is allowed." >&2
    return 1
  fi

  for i in "${!_bo_arguments[@]}"; do
    name="${_bo_arguments[$i]}"
    _bo_meta_get "$name" cardinality cardinality
    _bo_meta_get "$name" cardinality_count count
    count="${count:-0}"

    if [[ "$count" -eq 0 ]]; then
      echo "Argument '$name' must declare exactly one of required, optional, variadic, or passthrough (none given)." >&2
      return 1
    elif [[ "$count" -gt 1 ]]; then
      echo "Argument '$name' declares more than one of required, optional, variadic, or passthrough (only one is allowed)." >&2
      return 1
    fi

    if [[ "$cardinality" == "required" ]] && _bo_meta_has "$name" default; then
      echo "A required argument cannot declare a default." >&2
      return 1
    fi

    if [[ "$cardinality" == "passthrough" ]] && _bo_meta_has "$name" default; then
      echo "A passthrough argument cannot declare a default." >&2
      return 1
    fi

    if [[ "$cardinality" == "required" && "$optional_seen" == "true" ]]; then
      echo "Argument '$name' is required but declared after an optional argument (required arguments must come before optional ones)." >&2
      return 1
    fi
    if [[ "$cardinality" == "optional" ]]; then
      optional_seen=true
    fi

    if [[ "$cardinality" == "variadic" || "$cardinality" == "passthrough" ]] && [[ "$i" -ne "$last_index" ]]; then
      echo "The variadic or passthrough argument must be the last declared argument." >&2
      return 1
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
  _bo_meta_get "$name" long long
  _bo_meta_get "$name" short short
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
  local label
  _bo_capture_text label _bo_display_flag "$1"
  _bo_print_error "Missing value" "$label"
}

_bo_die_unexpected_argument() {
  _bo_print_error "Unexpected argument" "$1"
}

_bo_die_missing_required_argument() {
  local label
  _bo_capture_text label _bo_display_argument "$1"
  _bo_print_error "Missing required argument" "$label"
}

_bo_die_missing_required_option() {
  local label
  _bo_capture_text label _bo_display_flag "$1"
  _bo_print_error "Missing required option" "$label"
}

_bo_die_not_in_git_repo() {
  _bo_print_error "Not inside a git repository" "$1 $2"
}

# $1 = display identifier (a flag form or an uppercased argument name)
# $2 = the offending raw value
# $3 = human-readable reason, e.g. "must be an integer"
_bo_die_invalid_value() {
  _bo_print_error "Invalid value" "$1 $2 ($3)"
}

# For invariants that schema finalization is supposed to guarantee. Reaching
# this means finalization itself has a bug, not that the user did anything
# wrong.
_bo_die_internal_error() {
  printf 'betteropts internal error: %s\n' "$1" >&2
  exit 1
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
declare -ga _bo_passthrough_values=()
declare -gA _bo_multi_values=()
declare -gA _bo_multi_count=()
declare -gA _bo_field_values=()

_bo_set_option_fields() {
  local name="$1" field idx=0
  shift
  if _bo_meta_is "$name" multi true; then
    idx="${_bo_multi_count[$name]:-0}"
  fi
  while IFS= read -r field; do
    _bo_field_values["$name.$idx.$field"]="$1"
    shift
  done < <(_bo_field_names "$name")
  _bo_provided[$name]=true
  _bo_multi_count[$name]=$((idx + 1))
}

# Records an occurrence of a (possibly multi) option's value: appended to an
# ordered per-name list for `multi` options, overwritten otherwise.
_bo_set_option_value() {
  local name="$1" value="$2" idx
  _bo_provided[$name]="true"
  if _bo_meta_is "$name" multi "true"; then
    idx="${_bo_multi_count[$name]:-0}"
    _bo_multi_values["$name.$idx"]="$value"
    _bo_multi_count[$name]=$((idx + 1))
  else
    _bo_raw[$name]="$value"
  fi
}

_bo_is_flag() {
  _bo_meta_is "$1" kind "flag"
}

_bo_find_by_long() {
  local tok="$1" name
  for name in "${_bo_flags_and_options[@]}"; do
    if _bo_meta_is "$name" long "$tok"; then
      printf '%s' "$name"
      return 0
    fi
  done
  return 1
}

_bo_find_by_short() {
  local tok="$1" name
  for name in "${_bo_flags_and_options[@]}"; do
    if _bo_meta_is "$name" short "$tok"; then
      printf '%s' "$name"
      return 0
    fi
  done
  return 1
}

# Whether the schema declares a passthrough argument. _bo_finalize_schema
# guarantees at most one, and that it's last, but this is also called from
# unit tests that invoke _bo_parse directly without finalizing first, so it
# checks by cardinality rather than assuming that invariant holds.
_bo_has_passthrough_argument() {
  local name
  for name in "${_bo_arguments[@]}"; do
    _bo_meta_is "$name" cardinality "passthrough" && return 0
  done
  return 1
}

_bo_parse() {
  _bo_provided=()
  _bo_raw=()
  _bo_positional_tokens=()
  _bo_multi_values=()
  _bo_multi_count=()
  _bo_field_values=()

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
      # For a plain positional/variadic argument, -- is pure syntax ("stop
      # parsing options") and is dropped, same as getopt. But when the tail
      # is a passthrough argument, tokens are forwarded raw to whatever the
      # caller ultimately invokes (e.g. git) - where a literal -- can carry
      # meaning too (e.g. disambiguating a pathspec from a revision).
      # Dropping it here would be indistinguishable from the caller never
      # having typed it, so it's kept - consistent with an unrecognized
      # flag triggering this same boundary, which is already kept below.
      _bo_has_passthrough_argument && _bo_positional_tokens+=("$tok")
      i=$((i + 1))
      continue
    fi

    if [[ "$tok" == --*=* ]]; then
      local long="${tok%%=*}" value="${tok#*=}" name
      if ! _bo_capture_text name _bo_find_by_long "$long" || _bo_is_flag "$name"; then
        if _bo_has_passthrough_argument; then
          after_dashdash=true
          _bo_positional_tokens+=("$tok")
          i=$((i + 1))
          continue
        fi
        _bo_die_unknown_option "$tok"
        return 1
      fi
      if _bo_meta_has "$name" fields; then
        local remaining=$(( $(_bo_option_arity "$name") - 1 ))
        if (( i + remaining >= n )); then
          _bo_die_missing_value "$name"
          return 1
        fi
        _bo_set_option_fields "$name" "$value" "${args[@]:i+1:remaining}"
        i=$((i + remaining + 1))
      else
        _bo_set_option_value "$name" "$value"
        i=$((i + 1))
      fi
      continue
    fi

    if [[ "$tok" == --* ]]; then
      local name
      if ! _bo_capture_text name _bo_find_by_long "$tok"; then
        if _bo_has_passthrough_argument; then
          after_dashdash=true
          _bo_positional_tokens+=("$tok")
          i=$((i + 1))
          continue
        fi
        _bo_die_unknown_option "$tok"
        return 1
      fi
      if _bo_is_flag "$name"; then
        _bo_provided[$name]="true"
        i=$((i + 1))
      elif _bo_meta_has "$name" implicit; then
        local implicit
        _bo_meta_get "$name" implicit implicit
        _bo_set_option_value "$name" "$implicit"
        i=$((i + 1))
      else
        local arity
        arity="$(_bo_option_arity "$name")"
        if (( i + arity >= n )); then
          _bo_die_missing_value "$name"
          return 1
        fi
        if _bo_meta_has "$name" fields; then
          _bo_set_option_fields "$name" "${args[@]:i+1:arity}"
        else
          _bo_set_option_value "$name" "${args[$((i + 1))]}"
        fi
        i=$((i + arity + 1))
      fi
      continue
    fi

    if [[ "$tok" == -?* ]]; then
      local name
      if ! _bo_capture_text name _bo_find_by_short "$tok"; then
        if _bo_has_passthrough_argument; then
          after_dashdash=true
          _bo_positional_tokens+=("$tok")
          i=$((i + 1))
          continue
        fi
        _bo_die_unknown_option "$tok"
        return 1
      fi
      if _bo_is_flag "$name"; then
        _bo_provided[$name]="true"
        i=$((i + 1))
      elif _bo_meta_has "$name" implicit; then
        local implicit
        _bo_meta_get "$name" implicit implicit
        _bo_set_option_value "$name" "$implicit"
        i=$((i + 1))
      else
        local arity
        arity="$(_bo_option_arity "$name")"
        if (( i + arity >= n )); then
          _bo_die_missing_value "$name"
          return 1
        fi
        if _bo_meta_has "$name" fields; then
          _bo_set_option_fields "$name" "${args[@]:i+1:arity}"
        else
          _bo_set_option_value "$name" "${args[$((i + 1))]}"
        fi
        i=$((i + arity + 1))
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
  _bo_passthrough_values=()

  local idx=0 total=${#_bo_positional_tokens[@]}
  local name cardinality

  for name in "${_bo_arguments[@]}"; do
    _bo_meta_get "$name" cardinality cardinality
    if [[ "$cardinality" == "variadic" ]]; then
      while (( idx < total )); do
        _bo_variadic_values+=("${_bo_positional_tokens[$idx]}")
        idx=$((idx + 1))
      done
    elif [[ "$cardinality" == "passthrough" ]]; then
      while (( idx < total )); do
        _bo_passthrough_values+=("${_bo_positional_tokens[$idx]}")
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

_bo_git_inside_work_tree=""

# Whether the current directory is inside a git working tree. Checked lazily
# (only once type=git-commitish/type=git-range validation is actually needed)
# and cached for the rest of the process, since every value of either type
# shares the same answer.
_bo_inside_git_work_tree() {
  if [[ -z "$_bo_git_inside_work_tree" ]]; then
    if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      _bo_git_inside_work_tree="true"
    else
      _bo_git_inside_work_tree="false"
    fi
  fi
  [[ "$_bo_git_inside_work_tree" == "true" ]]
}

_bo_choice_matches() {
  local value="$1" choices="$2"
  local -a list
  IFS=',' read -ra list <<< "$choices"
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
    git-commitish)
      _bo_inside_git_work_tree || {
        _bo_die_not_in_git_repo "$ident" "$value"
        return 1
      }
      git rev-parse --verify --quiet "${value}^{commit}" >/dev/null 2>&1 || {
        _bo_die_invalid_value "$ident" "$value" "not a valid git revision"
        return 1
      }
      ;;
    git-range)
      _bo_inside_git_work_tree || {
        _bo_die_not_in_git_repo "$ident" "$value"
        return 1
      }
      git rev-list --count "$value" >/dev/null 2>&1 || {
        _bo_die_invalid_value "$ident" "$value" "not a valid git revision range"
        return 1
      }
      ;;
    *)
      ;;
  esac
  return 0
}

_bo_validate() {
  local name cardinality count idx value type choices label

  for name in "${_bo_options[@]}"; do
    if _bo_meta_is "$name" required true && [[ -z "${_bo_provided[$name]:-}" ]]; then
      _bo_die_missing_required_option "$name"
      return 1
    fi
  done

  for name in "${_bo_arguments[@]}"; do
    _bo_meta_get "$name" cardinality cardinality
    if [[ "$cardinality" == "required" && -z "${_bo_raw[$name]:-}" ]]; then
      _bo_die_missing_required_argument "$name"
      return 1
    fi
  done

  for name in "${_bo_options[@]}"; do
    _bo_capture_text label _bo_display_flag "$name"
    _bo_meta_get "$name" type type
    _bo_meta_get "$name" choices choices
    if _bo_meta_has "$name" fields; then
      local field
      count="${_bo_multi_count[$name]:-0}"
      for ((idx = 0; idx < count; idx++)); do
        while IFS= read -r field; do
          _bo_meta_get "$name" "$field.type" type
          _bo_meta_get "$name" "$field.choices" choices
          _bo_validate_type "$label ${field^^}" \
            "${_bo_field_values["$name.$idx.$field"]}" \
            "$type" "$choices" || return 1
        done < <(_bo_field_names "$name")
      done
    elif _bo_meta_is "$name" multi "true"; then
      count="${_bo_multi_count[$name]:-0}"
      for ((idx = 0; idx < count; idx++)); do
        value="${_bo_multi_values["$name.$idx"]}"
        _bo_validate_type "$label" "$value" \
          "$type" "$choices" || return 1
      done
    elif [[ -n "${_bo_provided[$name]:-}" ]]; then
      _bo_validate_type "$label" "${_bo_raw[$name]}" \
        "$type" "$choices" || return 1
    fi
  done

  for name in "${_bo_arguments[@]}"; do
    _bo_capture_text label _bo_display_argument "$name"
    _bo_meta_get "$name" cardinality cardinality
    _bo_meta_get "$name" type type
    _bo_meta_get "$name" choices choices
    if [[ "$cardinality" == "variadic" ]]; then
      local value
      for value in "${_bo_variadic_values[@]}"; do
        _bo_validate_type "$label" "$value" \
          "$type" "$choices" || return 1
      done
    elif [[ -n "${_bo_raw[$name]:-}" ]]; then
      _bo_validate_type "$label" "${_bo_raw[$name]}" \
        "$type" "$choices" || return 1
    fi
  done

  return 0
}

# ---------------------------------------------------------------------------
# Defaults
#
# Applied after validation and before variable population: an omitted
# option or argument that declares a default is filled in with that default
# value. Like an option's default, an argument's default is trusted as-is
# and never itself type-checked.
# ---------------------------------------------------------------------------

_bo_apply_defaults() {
  local name cardinality default
  for name in "${_bo_options[@]}"; do
    if [[ -z "${_bo_provided[$name]:-}" ]] && _bo_meta_has "$name" default; then
      _bo_meta_get "$name" default default
      _bo_raw[$name]="$default"
    fi
  done

  for name in "${_bo_arguments[@]}"; do
    _bo_meta_has "$name" default || continue
    _bo_meta_get "$name" default default
    _bo_meta_get "$name" cardinality cardinality
    if [[ "$cardinality" == "variadic" ]]; then
      if [[ "${#_bo_variadic_values[@]}" -eq 0 ]]; then
        IFS=',' read -r -d '' -a _bo_variadic_values < <(printf '%s\0' "$default")
      fi
    elif [[ -z "${_bo_raw[$name]:-}" ]]; then
      _bo_raw[$name]="$default"
    fi
  done
}

# ---------------------------------------------------------------------------
# Variable Population
#
# Writes the final values into ordinary (never exported) shell variables in
# the caller's scope, using each declaration's var= name (defaulting to the
# declared name). Every assignment goes through `declare -g`: a plain
# `varname=value` would instead silently rebind one of this function's own
# local loop variables if a CLI author happened to name their option/argument
# the same thing (e.g. `option name ...` colliding with a local var "name").
# ---------------------------------------------------------------------------

_bo_populate() {
  local name var cardinality i count

  for name in "${_bo_flags[@]}"; do
    _bo_meta_get "$name" var var
    if [[ -n "${_bo_provided[$name]:-}" ]]; then
      declare -g "$var=true"
    else
      declare -g "$var=false"
    fi
  done

  for name in "${_bo_options[@]}"; do
    _bo_meta_get "$name" var var
    if _bo_meta_has "$name" fields; then
      local field field_var
      while IFS= read -r field; do
        field_var="${var}_${field}"
        if _bo_meta_is "$name" multi true; then
          declare -ga "$field_var=()"
          count="${_bo_multi_count[$name]:-0}"
          for ((i = 0; i < count; i++)); do
            declare -g "${field_var}[$i]=${_bo_field_values["$name.$i.$field"]}"
          done
        else
          declare -g "$field_var=${_bo_field_values["$name.0.$field"]:-}"
        fi
      done < <(_bo_field_names "$name")
    elif _bo_meta_is "$name" multi "true"; then
      declare -ga "$var=()"
      count="${_bo_multi_count[$name]:-0}"
      for ((i = 0; i < count; i++)); do
        declare -g "${var}[$i]=${_bo_multi_values["$name.$i"]}"
      done
    else
      declare -g "$var=${_bo_raw[$name]:-}"
    fi
  done

  for name in "${_bo_arguments[@]}"; do
    _bo_meta_get "$name" var var
    _bo_meta_get "$name" cardinality cardinality
    if [[ "$cardinality" == "variadic" ]]; then
      declare -ga "$var=()"
      for i in "${!_bo_variadic_values[@]}"; do
        declare -g "${var}[$i]=${_bo_variadic_values[$i]}"
      done
    elif [[ "$cardinality" == "passthrough" ]]; then
      declare -ga "$var=()"
      for i in "${!_bo_passthrough_values[@]}"; do
        declare -g "${var}[$i]=${_bo_passthrough_values[$i]}"
      done
    else
      declare -g "$var=${_bo_raw[$name]:-}"
    fi
  done
}

# ---------------------------------------------------------------------------
# Usage Generator
# ---------------------------------------------------------------------------

# Set by betteropts_parse from $0; overridable (e.g. by tests) before calling
# _bo_usage_line/_bo_usage_text/_bo_help_text directly.
_bo_command_name="${_bo_command_name:-}"

_bo_option_metavars() {
  local name="$1" field joined=""
  if _bo_meta_has "$name" fields; then
    while IFS= read -r field; do
      [[ -n "$joined" ]] && joined+=" "
      joined+="${field^^}"
    done < <(_bo_field_names "$name")
    printf '%s' "$joined"
  else
    _bo_meta_get "$name" metavar joined
    printf '%s' "$joined"
  fi
}

_bo_usage_line() {
  local line="$_bo_command_name" name cardinality token metavar long
  for name in "${_bo_flags_and_options[@]}"; do
    _bo_capture_text token _bo_display_flag "$name"
    if _bo_meta_is "$name" kind "option"; then
      _bo_capture_text metavar _bo_option_metavars "$name"
      metavar="${metavar:-VALUE}"
      if _bo_meta_has "$name" implicit; then
        # An implicit option accepts an explicit value only as --long=value.
        _bo_meta_get "$name" long long
        [[ -n "$long" ]] && token+="[=$metavar]"
      else
        token+=" $metavar"
      fi
    fi
    if _bo_meta_is "$name" required "true"; then
      line+=" $token"
      _bo_meta_is "$name" multi "true" && line+=" [$token]..."
    else
      line+=" [$token]"
      _bo_meta_is "$name" multi "true" && line+="..."
    fi
  done
  for name in "${_bo_arguments[@]}"; do
    _bo_meta_get "$name" cardinality cardinality
    _bo_capture_text token _bo_display_argument "$name"
    case "$cardinality" in
      required) line+=" $token" ;;
      optional) line+=" [$token]" ;;
      variadic|passthrough) line+=" [$token...]" ;;
      *) _bo_die_internal_error "unrecognized cardinality '$cardinality' for argument '$name'" ;;
    esac
  done
  printf '%s' "$line"
}

_bo_usage_text() {
  local line
  _bo_capture_text line _bo_usage_line
  printf '%s\n\nUsage:\n\n%s' "$_bo_summary" "$line"
}

# ---------------------------------------------------------------------------
# Help Generator
#
# --usage and --__complete are intentionally never listed here, matching
# DESIGN.MD's worked Help Output example (only -h/--help appears).
# ---------------------------------------------------------------------------

# Strips exactly the leading and trailing blank line a description's
# multi-line string literal carries (from `description "\n...\n"`), while
# preserving any blank lines in the middle of the text.
_bo_trim_description() {
  local text="$1"
  text="${text#$'\n'}"
  while [[ "$text" == *$'\n' ]]; do
    text="${text%$'\n'}"
  done
  printf '%s' "$text"
}

# The parenthesized, comma-separated annotation list for a declared name's
# --help entry (e.g. "required, repeatable, choices: a, b, c"), summarizing
# schema facts (required, multi/variadic, default=, implicit=, choices=)
# that would otherwise only be visible by reading the CLI's source. Empty
# for a flag (flags don't support any of these) and for anything that
# declares none of them.
_bo_annotations() {
  local name="$1" kind cardinality choices literal parts=()
  _bo_meta_get "$name" kind kind

  if [[ "$kind" == "argument" ]]; then
    _bo_meta_get "$name" cardinality cardinality
    [[ "$cardinality" == "required" ]] && parts+=("required")
    [[ "$cardinality" == "variadic" ]] && parts+=("repeatable")
  elif [[ "$kind" == "option" ]]; then
    _bo_meta_is "$name" required "true" && parts+=("required")
    _bo_meta_is "$name" multi "true" && parts+=("repeatable")
  fi

  if [[ "$kind" == "option" || "$kind" == "argument" ]]; then
    if _bo_meta_has "$name" default; then
      _bo_meta_get "$name" default literal
      parts+=("default: $literal")
    fi
    if [[ "$kind" == "option" ]]; then
      if _bo_meta_has "$name" implicit; then
        _bo_meta_get "$name" implicit literal
        parts+=("implicit: $literal")
      fi
    fi
    if _bo_meta_has "$name" fields; then
      local field
      while IFS= read -r field; do
        if _bo_meta_is "$name" "$field.type" choice; then
          _bo_meta_get "$name" "$field.choices" choices
          parts+=("${field^^} choices: ${choices//,/, }")
        fi
      done < <(_bo_field_names "$name")
    fi
    if _bo_meta_is "$name" type "choice"; then
      _bo_meta_get "$name" choices choices
      parts+=("choices: ${choices//,/, }")
    fi
  fi

  (( ${#parts[@]} == 0 )) && return 0

  local joined="${parts[0]}" i
  for ((i = 1; i < ${#parts[@]}; i++)); do
    joined+=", ${parts[$i]}"
  done
  printf '%s' "$joined"
}

# The label shown in the Options section: "-x, --xxx", "--xxx", or "-x"
# alone, plus a trailing metavar for options, plus a trailing parenthesized
# annotation list (see _bo_annotations) when any annotation applies.
_bo_option_label() {
  local name="$1" short long metavar annotations label
  _bo_meta_get "$name" short short
  _bo_meta_get "$name" long long
  if [[ -n "$short" && -n "$long" ]]; then
    label="$short, $long"
  elif [[ -n "$long" ]]; then
    label="$long"
  else
    label="$short"
  fi
  if _bo_meta_is "$name" kind "option"; then
    _bo_capture_text metavar _bo_option_metavars "$name"
    [[ -n "$metavar" ]] && label+=" $metavar"
  fi
  _bo_capture_text annotations _bo_annotations "$name"
  [[ -n "$annotations" ]] && label+=" ($annotations)"
  printf '%s' "$label"
}

_bo_help_text() {
  local out="$_bo_summary" name help label usage

  if [[ -n "$_bo_description" ]]; then
    out+=$'\n\n'"$(_bo_trim_description "$_bo_description")"
  fi

  _bo_capture_text usage _bo_usage_line
  out+=$'\n\n'"Usage:"$'\n\n'"$usage"

  if [[ ${#_bo_arguments[@]} -gt 0 ]]; then
    out+=$'\n\n'"Arguments"
    for name in "${_bo_arguments[@]}"; do
      local arg_header annotations
      _bo_capture_text arg_header _bo_display_argument "$name"
      _bo_capture_text annotations _bo_annotations "$name"
      [[ -n "$annotations" ]] && arg_header+=" ($annotations)"
      _bo_meta_get "$name" help help
      out+=$'\n\n'"$arg_header"$'\n'"    $help"
    done
  fi

  out+=$'\n\n'"Options"
  for name in "${_bo_flags_and_options[@]}"; do
    _bo_meta_get "$name" help help
    _bo_capture_text label _bo_option_label "$name"
    out+=$'\n\n'"$label"$'\n'"    $help"
  done
  out+=$'\n\n'"-h, --help"$'\n'"    Show this help"

  printf '%s' "$out"
}

# ---------------------------------------------------------------------------
# Completion
#
# Wire protocol (internal; --__complete "must not appear in help output"):
#
#   <command> --__complete -- word1 word2 ... wordN
#
# wordN (possibly empty) is the partial word being completed; word1..N-1 are
# the already-typed words before it. Candidates are printed one per line to
# stdout. This mirrors the shape real-world Bash-completion-over-a-hidden-flag
# tools use (e.g. argc's `--argc-compgen`, cobra's `__complete`): a single
# generic shell-side function (_bo_bash_completion below) that knows nothing
# about any particular command's schema, and delegates entirely to invoking
# that command with the hidden flag.
# ---------------------------------------------------------------------------

_bo_complete_choice() {
  local partial="$1" choices="$2"
  local -a list
  IFS=',' read -ra list <<< "$choices"
  local c
  for c in "${list[@]}"; do
    [[ "$c" == "$partial"* ]] && printf '%s\n' "$c"
  done
  return 0
}

_bo_complete_value() {
  local name="$1" partial="$2" field="${3:-}" type choices key=""
  [[ -n "$field" ]] && key="$field."
  _bo_meta_get "$name" "${key}type" type
  case "$type" in
    choice)
      _bo_meta_get "$name" "${key}choices" choices
      _bo_complete_choice "$partial" "$choices"
      ;;
    file) compgen -f -- "$partial" || true ;;
    directory) compgen -d -- "$partial" || true ;;
    *) ;;
  esac
  return 0
}

_bo_complete_option_names() {
  local partial="$1" name long short
  for name in "${_bo_flags_and_options[@]}"; do
    _bo_meta_get "$name" long long
    _bo_meta_get "$name" short short
    [[ -n "$long" && "$long" == "$partial"* ]] && printf '%s\n' "$long"
    [[ -n "$short" && "$short" == "$partial"* ]] && printf '%s\n' "$short"
  done
  [[ "--help" == "$partial"* ]] && printf '%s\n' "--help"
  [[ "-h" == "$partial"* ]] && printf '%s\n' "-h"
  return 0
}

# Resolves what `partial` (the last word) is completing: an option's value,
# an option name, or a positional argument's value - by replaying the
# already-typed words (a simplified re-walk of _bo_parse's logic, since the
# in-progress partial word makes the real parser's error paths the wrong
# tool here).
_bo_complete() {
  if [[ "${1:-}" == "--" ]]; then
    shift
  fi
  local words=("$@")
  local n=${#words[@]}
  (( n == 0 )) && return 0

  local partial="${words[$((n - 1))]}"
  local i=0 awaiting_name="" awaiting_field="" remaining=0 consumed=0 positional_count=0
  local past_passthrough_boundary=false after_dashdash=false
  local fields=()

  while (( i < n - 1 )); do
    local tok="${words[$i]}" name="" attached=false
    if (( remaining > 0 )); then
      remaining=$((remaining - 1))
      consumed=$((consumed + 1))
      i=$((i + 1))
      continue
    fi
    awaiting_name=""
    if [[ "$after_dashdash" == true ]]; then
      positional_count=$((positional_count + 1))
      i=$((i + 1))
      continue
    fi
    if [[ "$tok" == -- ]]; then
      if _bo_has_passthrough_argument; then
        past_passthrough_boundary=true
        break
      fi
      after_dashdash=true
      i=$((i + 1))
      continue
    elif [[ "$tok" == --*=* ]]; then
      _bo_capture_text name _bo_find_by_long "${tok%%=*}" || true
      attached=true
    elif [[ "$tok" == --* ]]; then
      _bo_capture_text name _bo_find_by_long "$tok" || true
    elif [[ "$tok" == -?* ]]; then
      _bo_capture_text name _bo_find_by_short "$tok" || true
    fi

    if [[ "$attached" == true && -n "$name" ]] && _bo_is_flag "$name"; then
      name=""
    fi

    if [[ -z "$name" && "$tok" == -?* ]] && _bo_has_passthrough_argument; then
      past_passthrough_boundary=true
      break
    fi
    if [[ -n "$name" ]] && ! _bo_is_flag "$name"; then
      if [[ "$attached" == true ]] || ! _bo_meta_has "$name" implicit; then
        awaiting_name="$name"
        remaining="$(_bo_option_arity "$name")"
        consumed=0
        if [[ "$attached" == true ]]; then
          remaining=$((remaining - 1))
          consumed=1
        fi
      fi
    elif [[ -z "$name" && "$attached" == false ]]; then
      positional_count=$((positional_count + 1))
    fi
    i=$((i + 1))
  done

  [[ "$past_passthrough_boundary" == true ]] && return 0

  if (( remaining > 0 )); then
    if _bo_meta_has "$awaiting_name" fields; then
      local field_list
      _bo_meta_get "$awaiting_name" fields field_list
      IFS=',' read -ra fields <<< "$field_list"
      awaiting_field="${fields[$consumed]}"
    fi
    _bo_complete_value "$awaiting_name" "$partial" "$awaiting_field"
    return 0
  fi

  if [[ "$after_dashdash" == false && "$partial" == -* ]]; then
    _bo_complete_option_names "$partial"
    return 0
  fi

  local arg_name idx=0 cardinality
  for arg_name in "${_bo_arguments[@]}"; do
    _bo_meta_get "$arg_name" cardinality cardinality
    if [[ "$cardinality" == "passthrough" ]]; then
      return 0
    fi
    if [[ "$cardinality" == "variadic" || "$idx" -eq "$positional_count" ]]; then
      _bo_complete_value "$arg_name" "$partial"
      return 0
    fi
    idx=$((idx + 1))
  done

  return 0
}

# Generic completion function for `complete -F _bo_bash_completion <cmd>...`.
# Knows nothing about any command's schema; delegates to that command's own
# --__complete. Register with -o nosort so candidate order (e.g. a choice
# list's declared order) is preserved instead of being alphabetized.
_bo_bash_completion() {
  local cmd="${COMP_WORDS[0]}"
  local -a words=("${COMP_WORDS[@]:1:COMP_CWORD}")
  mapfile -t COMPREPLY < <("$cmd" --__complete -- "${words[@]}" 2>/dev/null)
}
