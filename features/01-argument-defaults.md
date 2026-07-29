# Feature: Default Values for Positional Arguments

## Status

Implemented.

## Problem

`argument` supports three cardinalities — `required`, `optional`, `variadic` —
but none of them accept a `default=`. An omitted `optional` argument
populates an empty string; an empty `variadic` populates an empty array.
There is no declarative way to say "if this positional wasn't given, use
this value instead."

`option` already has this exact feature (`option jobs -j --jobs N
default=4`). Arguments are the odd one out.

This was the single most common gap found while auditing a real consuming
project (a ~55-command Bash CLI at `android-deps-build-config/merge-scripts`)
for betteropts conversion candidates. At least 13 commands hand-roll a
defaulted positional today, e.g.:

```bash
# current hand-rolled pattern, repeated across the codebase
base_ref="${1:-master}"
tag="${1:-studio-2025.3.2}"
commit="${1:-HEAD}"          # appears in at least 4 separate commands
remote="${1:-origin}"
folders_to_check=("$@")      # defaults to (".") when empty
```

Converting any of these to betteropts today means dropping to manual
post-parse code:

```bash
argument commit optional
betteropts_parse "$@"
[[ -z "$commit" ]] && commit=HEAD
```

which is exactly the kind of boilerplate the library exists to remove.

## Proposed API

Extend `argument`'s declaration grammar to accept `default=VALUE` on
`optional` and `variadic` arguments (a `required` argument with a default is
a contradiction — see Schema Rules below):

```bash
argument commit optional default=HEAD
argument base_ref optional default=master

# variadic: a comma-separated default list, same convention as `choices=a,b,c`
argument folders variadic default=.
argument reviewers variadic default=alice,bob
```

## Behavior

- **`optional` + `default=`**: if the argument wasn't supplied, populate the
  declared variable with the default string instead of `""`.
- **`variadic` + `default=`**: if zero positional tokens were collected for
  this argument, populate the array by splitting `default=` on commas (one
  element if there's no comma), instead of an empty array.
- **Ordering**: defaults apply in the same lifecycle slot arguments already
  use for options — after `_bo_validate`, before `_bo_populate`. This
  preserves the existing rule (stated in the README for `option`) that *"a
  default value is trusted as-is and is never itself type-checked."* An
  argument's default is not run through `type=`/`choices=` validation
  either, for consistency.
- **No default given**: unchanged existing behavior (`optional` → `""`,
  `variadic` → `()`).

## Schema Validation Rules

- `default=` on a `required` argument is a schema error, caught by
  `_bo_finalize_schema` (same enforcement point that already catches
  "variadic argument must be last"): a required argument that also has a
  default is a contradictory declaration — that's a bug in the CLI author's
  script, not user input, so it should be reported the same way other
  broken-schema cases are.
- `default=` is otherwise orthogonal to `type=`/`choices=` — no interaction
  effects beyond "the default is never validated."

## Non-Goals (v1)

- No default-value *expressions* (e.g. shelling out to compute a default at
  parse time) — a literal string/comma-list only, matching `option`'s
  existing `default=` behavior exactly.
- No warning/error if a default value would fail the declared `type=`/
  `choices=` check — same as `option` today.

## Backward Compatibility

Fully additive. Scripts that don't use `default=` on `argument` are
unaffected; `optional`/`variadic` without `default=` behave exactly as
before.

## Suggested Test Coverage

Mirroring the existing `test/unit/` + `test/integration/` split:

- `test/unit/schema.bats`: `default=` accepted on `optional`/`variadic`;
  rejected (schema error) on `required`.
- `test/unit/population.bats`: omitted `optional` argument populates the
  default string; omitted `variadic` argument populates the default array
  (single-element and comma-split multi-element cases).
- `test/unit/validation.bats`: a default value that would fail `type=`/
  `choices=` is NOT rejected (defaults are trusted as-is, matching
  `option`'s documented behavior) — add a regression test for this since
  it's an easy place to accidentally introduce validation.
- `test/integration/parsing.bats`: end-to-end fixture with a defaulted
  optional positional and a defaulted variadic positional, both omitted and
  both explicitly provided (4 cases).
