# Feature: Auto-Annotated Help Text for Schema Metadata

## Status

Implemented.

## Problem

`--help` shows an option's label (short/long form plus metavar) or an
argument's uppercased name, followed only by whatever literal string the CLI
author wrote in `help="..."`. Every other schema fact the author already
declared — `required`, `multi` (repeatable), `default=`, `type=choice`'s
`choices=`, an argument's `optional`/`variadic` cardinality — is invisible
in `--help` unless the author manually re-states it in their own `help=`
prose.

Confirmed directly against the `build` fixture (`test/fixtures/build`),
whose schema declares `option output ... required` and
`option jobs ... default=4`. Its actual `--help` output
(`test/integration/help_usage.bats`) renders both identically to a plain,
optional, default-less option:

```
-o, --output PATH
    Output directory

-j, --jobs N
    Worker count
```

There is nothing in either line indicating `--output` must be passed or
that `--jobs` defaults to `4` — a user has to already know the CLI, or read
its source, to find out. This is the same gap `features/02-multi-value-options.md`
ran into directly: its `multi_option` fixture had to hand-write
`help="Note topic to show (repeatable)"` because nothing else would tell the
user `-t`/`--topic` can be repeated. Nothing enforces that every `multi`
author remembers to do this, or phrases it consistently — `multi` was just
the first case to surface the pattern; `required`, `default=`, and
`choices=` all have the identical problem today.

## Proposed API

No new declaration syntax. Every fact this feature surfaces is already
captured by existing schema metadata (`required`, `multi`, `default`,
`type`/`choices`, `cardinality`) via the existing `flag`/`option`/`argument`
grammar (including `features/01-argument-defaults.md`'s argument `default=`
and `features/02-multi-value-options.md`'s option `multi`, whether or not
those two have already landed). This feature only changes how `--help`
renders that metadata: after the existing label, append a single
parenthesized, comma-separated list of every applicable annotation, in a
fixed order:

```
required, repeatable, default: <value>, choices: <a, b, c>
```

Only the annotations that actually apply are included; if none apply, the
line is byte-for-byte identical to today (no trailing space, no empty
parens).

Worked example — a schema exercising every annotation at once:

```bash
option output -o --output PATH \
    required \
    type=directory \
    help="Output directory"

option jobs -j --jobs N \
    default=4 \
    type=integer \
    help="Worker count"

option topic -t --topic VALUE \
    multi \
    type=choice choices=fast,slow,auto \
    help="Note topic to show"

argument source required \
    type=directory \
    help="Source directory"

argument reviewers variadic \
    default=alice,bob \
    help="Reviewers"
```

renders as:

```
Options

-o, --output PATH (required)
    Output directory

-j, --jobs N (default: 4)
    Worker count

-t, --topic VALUE (repeatable, choices: fast, slow, auto)
    Note topic to show

Arguments

SOURCE (required)
    Source directory

REVIEWERS (repeatable, default: alice,bob)
    Reviewers
```

(Since the `multi_option` fixture's `help=` text no longer needs to spell
out "(repeatable)" itself once this lands, it should be trimmed back to
`help="Note topic to show"` — see Backward Compatibility.)

## Behavior

- A new helper (e.g. `_bo_annotations`) computes the annotation list for a
  given declared name, checking existing `_bo_meta_get`/`_bo_meta_has`
  fields — no new metadata fields are introduced:
  - `required` == `"true"` → `required`
  - `multi` == `"true"` (options) **or** `cardinality` == `variadic`
    (arguments) → `repeatable`. Unifying the wording here is deliberate:
    both mean "this can supply more than one value," and it means `multi`
    options and `variadic` arguments read consistently in `--help`.
  - `_bo_meta_has name default` → `default: <value>`, the value printed
    verbatim (including an unmodified comma-separated variadic/multi
    default list, e.g. `alice,bob`) — no reformatting, matching the
    existing "a default is trusted as-is" convention.
  - `type` == `choice` → `choices: <a, b, c>`, reusing the exact
    `${choices//,/, }` formatting `_bo_validate_type`'s "Invalid value"
    error already uses for choices, for one consistent rendering of a
    choice list across the codebase.
- `_bo_option_label` (options) and whatever builds each Arguments-section
  entry header (arguments) both call this helper and append its output
  (parenthesized) after the existing label, only when non-empty.
- `flag` declarations are unaffected: flags don't support `required`,
  `multi`, `default=`, or `choices=` at all, so their label never grows an
  annotation.
- An argument's cardinality can only ever contribute `required` **or**
  `repeatable` (never both — a `argument` declares exactly one of
  `required`/`optional`/`variadic`), while an `optional` argument
  contributes neither by itself, mirroring how a non-`required` option
  contributes no `required` annotation either. An `option`, unlike an
  argument, *can* show both `required` and `repeatable` together (`required
  multi`), since those are independent modifiers for options.
- `--usage`'s one-line usage summary is untouched by this feature — only
  the itemized `--help` "Arguments"/"Options" sections gain annotations.

## Schema Validation Rules

None. This is a pure rendering change against metadata every existing
schema-validation rule already enforces (e.g. `multi` + `default=` is
already rejected by `_bo_finalize_schema` per
`features/02-multi-value-options.md`, so `repeatable, default: ...` can
never appear together for an option).

## Non-Goals (v1)

- No localization. English only, hardcoded strings (`required`,
  `repeatable`, `default:`, `choices:`) — matching every other user-facing
  string in this library (error messages, `Missing required option`, etc.).
  There is no ambition to support multiple languages, now or later.
- No deduplication against hand-authored `help=` prose that happens to
  already mention one of these facts (e.g. today's `multi_option` fixture).
  The library does not parse or rewrite an author's own `help=` string; a
  CLI that doesn't update its `help=` text after adopting this feature will
  just read redundantly (e.g. "(repeatable)" both in the new annotation and
  in the old prose) until its author trims it.
- No reformatting/prettifying of a `default=` value beyond printing it
  verbatim — no quoting, no re-splitting a variadic/multi default's
  comma-list into a nicer join.
- No configurability of the annotation vocabulary, wording, or order —
  fixed strings in a fixed order, matching this library's existing
  no-configuration-knobs style (e.g. the fixed shape of every error
  message).
- No interaction with `features/04-exclusive-flag-groups.md`'s proposed
  group membership — if that feature lands, whether/how its own `--help`
  group rendering combines with these per-flag annotations is a follow-up
  concern, not addressed here.

## Backward Compatibility

Not fully additive at the text level, unlike most other proposals in this
directory: any *existing* option or argument that already declares
`required`, `multi`, `default=`, or `type=choice` will render different
`--help` output once this lands, even though nothing about its schema
declaration changes. Concretely:

- `test/unit/help_usage.bats`'s `"help text matches the DESIGN.MD worked
  example"` test and `test/integration/help_usage.bats`'s `"--help prints
  full help text matching the CLI schema"` test both assert an exact
  `--help` string against the `build` fixture, which declares `output` as
  `required` and `jobs` with `default=4`. Both golden strings need updating
  as part of this change, not just extending.
- **DESIGN.MD's own worked "Help Output" example** (the `# Help Output`
  section) needs updating too — unlike `features/01-argument-defaults.md`
  and `features/02-multi-value-options.md`, which only added previously
  unsupported syntax and left DESIGN.MD's existing worked examples
  untouched, this feature changes the rendered output of a schema DESIGN.MD
  already shows verbatim. Since DESIGN.MD is described (in README.md) as
  "the full specification this library implements," this is worth flagging
  explicitly before implementation, not discovering it as a side effect of
  a failing test.
- Any schema that declares none of `required`/`multi`/`default=`/
  `type=choice` (e.g. a plain `flag`, or an `option`/`argument` with no
  modifiers) renders byte-for-byte identically to today.

## Suggested Test Coverage

- `test/unit/help_usage.bats`: one test per annotation in isolation
  (`required` alone, `multi` alone, `default=` alone, `choices=` alone) for
  both `option` and `argument` (where applicable — arguments can't be
  `multi`, only `variadic`); a combined case (`required multi
  type=choice`); and an explicit regression test confirming an option/
  argument with none of these modifiers renders with no parenthesized
  suffix at all (byte-for-byte match to today's output).
- `test/unit/help_usage.bats`: `flag` never gains an annotation regardless
  of how it's declared (there's nothing to annotate it with).
- Update the two existing golden-output tests named above
  (`test/unit/help_usage.bats` and `test/integration/help_usage.bats`) to
  match the new `build`-fixture output, per Backward Compatibility.
- `test/integration/help_usage.bats`: a new fixture (or an extension of an
  existing one) exercising every annotation at once, matching this
  proposal's worked example above, asserted end-to-end through `--help`.
- Update DESIGN.MD's `# Help Output` worked example to match, per Backward
  Compatibility, and add/update a corresponding unit test asserting
  `_bo_help_text` against the revised DESIGN.MD text (mirroring how
  `"help text matches the DESIGN.MD worked example"` already pins the
  current text).
