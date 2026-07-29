# Feature: Raw Passthrough Argument Capture

## Status

Implemented.

## Problem

`_bo_parse` treats any token starting with `-` as an option lookup, *unless*
it comes after a literal `--`:

```bash
if [[ "$tok" == --*=* ]]; then ...
if [[ "$tok" == --* ]]; then ... _bo_die_unknown_option "$tok" ...
if [[ "$tok" == -?* ]]; then ... _bo_die_unknown_option "$tok" ...
```

So today, forwarding arbitrary/undeclared dash-prefixed flags to an
underlying tool requires the caller to type a literal `--` first. Several
real commands in the audited consuming project need to forward such flags
*without* that requirement, to stay backward compatible with how they're
invoked today:

- `merge/remerge-diff` / `remerge-difftool` — recognizes its own `-f`/
  `--force` (checked only as `argv[0]`, not scanned generally), takes an
  optional `commit` positional, then forwards everything else straight to
  `git diff "$tree" "$commit" "$@"` / `git difftool ...`. Real invocations
  look like `remerge-diff HEAD --stat -M` with no `--`.
- `notes/log` — content-sniffs `argv[0]`: if it looks like a flag, there's
  no positional at all and *everything* forwards to `git log "$@"`.
- `review/result` / `review/source` — forward all args straight to
  `git show "$current" "$@"`, deliberately not parsing their own flags.
- `internal/ktfmt` — a thin wrapper that forwards every argument verbatim to
  a real `ktfmt` jar (its own flags, like `--kotlinlang-style`, are opaque
  to the wrapper by design).

## Proposed API

A new `argument` cardinality, `passthrough` (mutually exclusive with
`variadic` — only one "collects the rest" positional is allowed per
schema, whichever kind it is):

```bash
argument git_args passthrough help="Extra options forwarded to git log"
```

## Behavior

- `passthrough` must be the last declared argument (same schema rule
  already enforced for `variadic`).
- Parsing proceeds normally against declared `flag`/`option` names up to the
  first token that doesn't match any of them **and** isn't consumed as an
  option's value. From that token onward, *every remaining token — including
  ones starting with `-` — is captured verbatim into the passthrough array,
  and parsing stops*, exactly as if the previous token had been a literal
  `--`. No "Unknown option" error is raised for anything past that point.
- This means passthrough capture starts automatically at the same boundary
  `--` already creates manually — it's the same mechanism, just triggered by
  "first unrecognized token" instead of requiring the literal marker.
- Populated the same way `variadic` is: `declare -ga "$var"`, one element
  per remaining token, in order.

## Relationship to Existing Position-Sensitive Scripts

A couple of the motivating scripts check their own flag (`-f`/`--force`)
*only* at `argv[0]`, rather than scanning for it anywhere before the
passthrough boundary. Converting them to `flag force -f --force` +
`argument extra passthrough` would make `-f` recognizable anywhere before
the boundary, which is strictly more permissive than today's behavior, not a
regression — worth calling out to whoever migrates those scripts, but not a
blocker for this feature.

## Non-Goals (v1)

- No interleaving: once passthrough capture starts, declared options can no
  longer be recognized for the rest of `argv`, same simplifying rule `--`
  already has. A script that genuinely needs `--known-flag` recognized
  *after* some raw passthrough tokens have already started is out of scope.
- No completion support for the passthrough tail — matches "opaque to this
  script by design"; `--__complete` should offer nothing once past the
  passthrough boundary.
- No validation/typing of passthrough tokens (they're not run through
  `type=`/`choices=` at all — they're raw text, full stop).

## Backward Compatibility

Fully additive — a schema with no `passthrough` argument is unaffected.
Existing `variadic` behavior (which still hard-rejects a leading `-` token
that isn't preceded by `--`) is unchanged; `passthrough` is a distinct,
opt-in cardinality.

## Suggested Test Coverage

- `test/unit/schema.bats`: `passthrough` accepted only as the last argument;
  a schema declaring both `variadic` and `passthrough` is a schema error.
- `test/unit/parser.bats`: tokens starting with `-` are captured (not
  rejected as unknown options) once the passthrough boundary is reached;
  declared flags/options *before* the boundary still parse normally.
- `test/unit/population.bats`: passthrough array ordering matches input
  order exactly, including flag-shaped tokens.
- `test/integration/parsing.bats`: a `git log`-style fixture — declared
  `--author` option plus a `passthrough` tail — invoked both with and
  without the tail, confirming declared options still work before the
  boundary and raw flags pass through after it.
- `test/integration/help_usage.bats`: confirm `--help`/`--usage` render the
  passthrough argument sensibly (e.g. `[GIT_ARGS...]`) without listing
  fake choices/type info it doesn't have.
