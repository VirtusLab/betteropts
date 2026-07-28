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
  _bo_flags+=("$name")
}

option() {
  local name="$1"
  shift
  _bo_declare option "$name" "$@"
  _bo_options+=("$name")
}

argument() {
  local name="$1"
  shift
  _bo_declare argument "$name" "$@"
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
