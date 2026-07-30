# Feature: Mutually Exclusive Flags / Required-Choice Groups

## Status

Proposed. Not yet implemented.

## Problem

There's no way to declare "at most one of these flags" or "exactly one of
these flags is required." Two real commands in the audited consuming
project need this and currently enforce it by hand, with two different
(inconsistent) results when violated:

- `review/next` — `--accept` and `--skip` are mutually exclusive *and*
  exactly one is required; the script explicitly checks
  `"$accept" && "$skip"` post-parse and errors.
- `todo/list` — `--progress` and `--pending` both write the same `mode`
  variable; if both are passed, the script silently keeps whichever was
  parsed last (no error at all — a real (minor) usability gap in the
  original script, not something to faithfully preserve).

## Proposed API

A new top-level declaration, `exclusive-group`, taking a list of
previously-declared flag names plus an optional `required` keyword:

```bash
flag accept --accept
flag skip --skip
exclusive-group accept skip required   # exactly one of these is mandatory

flag progress --progress
flag pending --pending
exclusive-group progress pending       # at most one; neither required
```

## Behavior

- Validated in `_bo_validate`, after normal per-option validation:
  - More than one member of a group was provided → error, e.g.:
    ```
    Mutually exclusive options:

    --accept, --skip
    ```
  - `required` and zero members were provided → error, e.g.:
    ```
    One of these options is required:

    --accept, --skip
    ```
- Group membership is otherwise transparent — each flag still populates its
  own `true`/`false` variable exactly as if it weren't in a group. The
  group only adds a validation constraint, not a new variable.

## Schema Validation Rules

- Every name passed to `exclusive-group` must already be declared via
  `flag` (or `option` — see Non-Goals) *before* the `exclusive-group` call;
  an unknown name is a schema error, caught at `_bo_finalize_schema` time
  (same rigor as the existing "variadic argument must be last" check).
- A flag/option belonging to more than one `exclusive-group` is a schema
  error in v1 (keep the mental model simple: one group membership per
  flag).

## Non-Goals (v1)

- Scope to `flag` only for the first version — both real motivating
  examples are boolean flags. Extending `exclusive-group` to cover `option`
  (e.g. "at most one of `--from-file`/`--from-url` may be given a value")
  is a plausible follow-up, but adds ambiguity (what if the *option* group
  should also be required-XOR with a specific value present vs absent?) —
  worth its own follow-up proposal once there's a concrete option-level use
  case.
- No group nesting or overlapping groups.
- No "if A then B is required" (conditional requirements) — this proposal
  only covers exclusivity and required-choice-among-a-set, not general
  cross-flag dependency rules.

## Backward Compatibility

Fully additive — a schema with no `exclusive-group` declarations is
unaffected.

## Suggested Test Coverage

- `test/unit/schema.bats`: `exclusive-group` referencing an undeclared name
  is a schema error; a flag in two groups is a schema error.
- `test/unit/validation.bats`: two group members both provided → mutual
  exclusivity error; `required` group with zero members provided → required
  error; exactly one member provided → no error, in both the `required` and
  non-`required` cases.
- `test/integration/errors.bats`: end-to-end fixture matching `review/next`
  shape (`--accept`/`--skip`, required) and `todo/list` shape
  (`--progress`/`--pending`, optional) — confirm error text and exit code
  for each violation.
- `test/integration/help_usage.bats`: confirm `--help` renders exclusive
  groups in a readable way (e.g. grouped together, or annotated) rather than
  listing the flags with no indication they're mutually exclusive.
