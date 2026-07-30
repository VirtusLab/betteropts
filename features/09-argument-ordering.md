# Feature: Argument Cardinality Ordering Constraint

## Status

Implemented.

## Problem

`_bo_finalize_schema` already enforces that a `variadic`/`passthrough`
argument must be the last declared argument, and that at most one of them
exists. But nothing constrains the relative order of `required` and
`optional` arguments before that point — a schema like

```bash
argument mode optional
argument source required
```

is accepted today, and it's a footgun. `_bo_assign_positionals` distributes
positional tokens with a single strictly-increasing index, walking declared
arguments in order and handing each `required`/`optional` argument exactly
one leftover token when its turn comes:

```bash
for name in "${_bo_arguments[@]}"; do
  cardinality="$(_bo_meta_get "$name" cardinality)"
  if [[ "$cardinality" == "variadic" ]]; then
    ...
  elif [[ "$cardinality" == "passthrough" ]]; then
    ...
  elif (( idx < total )); then
    _bo_raw[$name]="${_bo_positional_tokens[$idx]}"
    idx=$((idx + 1))
  fi
done
```

With the schema above and a single positional token (`mycommand foo`), `mode`
(declared first) greedily claims it, leaving `source` — the one actually
`required` — unfulfilled. Validation then reports `Missing required
argument: SOURCE`, which is a confusing message given the caller supplied
exactly one value; there's no way from the error alone to tell that the
value went to the wrong slot.

This was found while explaining how `optional` interacts with a trailing
`variadic`/`passthrough` argument. That specific interaction — whether a
`variadic`/`passthrough` argument could receive tokens while an earlier
`optional` argument goes unfulfilled — turns out to already be impossible:
`_bo_assign_positionals`'s index only ever increases, so once tokens run
out at any position, every argument after it (optional or variadic) also
gets nothing. That guarantee needs no fix, and is now locked in by two
regression tests in `test/unit/population.bats` ("an optional argument
before a variadic argument claims the first token, leaving variadic empty"
and "...before a passthrough argument claims the first token, even a
flag-shaped one") — both pass against today's code, independent of whether
this proposal is implemented. The `optional`-before-`required` ordering is
the one real gap, and it's a distinct bug from that (already-safe) case:
here there's no shortage of tokens, just a token going to the wrong
declared name.

## Proposed API

No new declaration syntax — this only adds an ordering constraint on top of
cardinalities `argument` already supports.

## Behavior

- `_bo_finalize_schema` gains a new check, alongside the existing
  variadic/passthrough-must-be-last check: once an `optional`-cardinality
  argument has been declared, no subsequent argument may declare `required`.
- Combined with the existing last-position rule for `variadic`/`passthrough`,
  this leaves exactly one valid cardinality ordering for a schema's
  arguments:

  ```
  required* optional* (variadic | passthrough)?
  ```

- This is a schema error, not a user-input error — checked once at
  declaration-finalization time, the same as the existing
  variadic/passthrough-must-be-last rule, reported via `echo ... >&2; return
  1` rather than the `_bo_die_*`/`_bo_print_error` runtime-error machinery.
- No change to `_bo_assign_positionals` itself. Its existing greedy
  left-to-right algorithm already produces the intended behavior once this
  ordering is guaranteed: `required` arguments fill first, in order, failing
  normally (and unambiguously) if too few tokens are given; `optional`
  arguments fill next, in order; a trailing `variadic`/`passthrough`
  argument gets whatever tokens are left over. The bug this closes is purely
  a schema-legality gap, not an algorithm defect.

## Non-Goals (v1)

- Doesn't change token-distribution behavior at runtime in any way — only
  which schemas are legal changes; `_bo_assign_positionals` is untouched.
- Doesn't introduce any smarter/lookahead-based positional matching (e.g.
  reserving tokens for required arguments ahead of a variadic list). The
  ambiguity that would require was only reachable through an
  `optional`-before-`required` schema, which this proposal rejects outright
  rather than trying to resolve cleverly at runtime.
- Doesn't touch `option` at all — options have no ordering relationship to
  each other or to arguments; this is purely about the relative declaration
  order of positional arguments.
- Doesn't restrict how many `optional` (or `required`) arguments may appear
  in a row — only the *transition* from `optional` back to `required` is
  disallowed.

## Backward Compatibility

Not additive in principle — a schema with `optional` declared before
`required` will start failing schema validation. In practice, I checked
every `test/fixtures/*` CLI and every `argument` sequence across
`test/unit/*.bats`/`test/integration/*.bats`: none declare an `optional` (or
`variadic`/`passthrough`) argument before a `required` one, so nothing
currently shipped is affected.

## Suggested Test Coverage

All added:

- `test/unit/population.bats`:
  - "an optional argument before a variadic argument claims the first
    token, leaving variadic empty"; "...before a passthrough argument
    claims the first token, even a flag-shaped one" — lock in existing
    behavior that never depended on the new constraint (see Problem above).
  - "required arguments fill first, then optional, then variadic gets the
    remainder" — the positive-path regression test cementing the property
    this proposal exists to guarantee, now that the ambiguous ordering it
    depends on is unreachable.
- `test/unit/schema.bats`:
  - "rejects a required argument declared after an optional one".
  - "accepts a required argument declared before an optional one".
  - "accepts an optional argument declared before a variadic one" / "...a
    passthrough one".
  - "accepts required, then optional, then variadic".
  - "accepts two optional arguments in a row" (the constraint is about the
    optional→required transition specifically, not "at most one optional").
  - the existing variadic/passthrough-must-be-last tests pass unmodified
    (this feature doesn't change that check).
