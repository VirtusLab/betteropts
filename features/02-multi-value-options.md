# Feature: Repeated / Multi-Value Options

## Status

Implemented.

## Problem

`option` always populates a scalar variable. Confirmed in
`_bo_populate`:

```bash
for name in "${_bo_options[@]}"; do
  var="$(_bo_meta_get "$name" var)"
  declare -g "$var=${_bo_raw[$name]:-}"
done
```

and in `_bo_parse`, every recognized option occurrence simply overwrites
`_bo_raw[$name]`. If the same option flag is passed twice, the second value
silently replaces the first — no error, no accumulation, no way to ask "give
me every value the user passed."

Two real commands in the audited consuming project need exactly this:

- `notes/rev-list --exclude-topic X --exclude-topic Y` — repeatable,
  accumulates into a bash array (`exclude_topics+=("$2")`), later checked
  for mutual exclusivity against a separately-repeatable
  `--include-topic`.
- `notes/show -t conflicts -t builds` — repeatable topic selector. This one
  was actually converted to betteropts already, and the conversion had to
  document a real regression in its own `--help` text: *"betteropts has no
  repeated-option support ... only the LAST -t/--topic wins instead of
  accumulating."*

## Proposed API

A new modifier on `option`, `multi` (parallel to `argument`'s `variadic`
cardinality):

```bash
option topic -t --topic VALUE multi \
    type=choice choices="$(dynamic_topic_list)" \
    help="Note topic to show (repeatable)"
```

## Behavior

- Each time the option is recognized on the command line, append the raw
  value to an ordered list instead of overwriting a scalar.
- `_bo_populate` declares the variable as an array (`declare -ga "$var"`)
  instead of a scalar, one element per occurrence, in the order given.
- `type=`/`choices=` validation applies to *each* value independently, same
  rule as a non-multi option — a single bad value among several still fails
  validation and reports which value/option failed.
- `required` + `multi` means "at least one occurrence is required" (zero
  occurrences is a `Missing required option` error, same message shape as
  today).
- Zero occurrences and no `required`: populate an empty array (not an empty
  string) — callers should be able to rely on `"${#topic[@]}"` regardless of
  whether the option is `multi`.

## Schema Validation Rules

- `default=` combined with `multi` is out of scope for v1 (see Non-Goals) —
  flag as a schema error at `_bo_finalize_schema` time rather than silently
  picking one interpretation.
- `var=` override works the same way it does today, just naming an array
  instead of a scalar.

## Completion

`--__complete` for a `multi` option should keep offering the full candidate
list (from `type=choice`'s `choices=`, static or dynamically computed) on
every invocation — do **not** try to filter out values already chosen on the
command line. This matches how most real CLIs with repeatable flags behave
(e.g. `git commit --trailer` lets you pick the same value twice if you want)
and keeps the completion implementation simple.

## Non-Goals (v1)

- No `default=` for `multi` options (what would "the default list" mean
  when the user provides zero, one, or many overrides? Punt rather than
  guess — revisit once there's a real use case).
- No dedup / uniqueness enforcement across repeated values — if the user
  passes `--topic builds --topic builds`, both are kept. Business logic
  can dedup after `betteropts_parse` returns if it cares.
- No interaction with `variadic` positional arguments — `multi` is an
  `option`-only concept; positionals already have their own multi-value
  primitive (`variadic`).

## Backward Compatibility

Fully additive — `option` without `multi` keeps today's overwrite-on-repeat
behavior exactly.

## Suggested Test Coverage

- `test/unit/schema.bats`: `multi` accepted on `option`; `multi` +
  `default=` together is a schema error.
- `test/unit/parser.bats`: repeated `-t`/`--topic` occurrences (short form,
  long form, `--topic=value` form, and mixed) all accumulate in the order
  given.
- `test/unit/validation.bats`: one invalid value among several repeated
  values still fails validation, with an error identifying which value.
- `test/unit/population.bats`: zero occurrences → empty array; `required` +
  zero occurrences → `Missing required option` error.
- `test/unit/completion.bats`: `--__complete` for a `multi` option returns
  the full choice list regardless of values already present earlier in
  `argv`.
- `test/integration/parsing.bats`: end-to-end fixture exercising
  `rev-list`-style dual-repeatable-and-mutually-exclusive options — this
  feature combined with mutual exclusivity (see
  [`04-exclusive-flag-groups.md`](04-exclusive-flag-groups.md)).
