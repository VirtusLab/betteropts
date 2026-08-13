# Feature: Implicit-Value Options

## Status

Implemented.

## Problem

`option` always requires an attached value — `-o value`, `--output value`,
or `--output=value`. There is no way to declare an option whose value may be
*omitted*, falling back to a well-known default for that one occurrence,
while still allowing an explicit value to be given.

Real CLIs use this pattern often. `git log --notes[=<ref>]` is the
motivating case:

```
git log                              # no notes shown
git log --notes                      # notes from refs/notes/commits (the default ref)
git log --notes=refs/notes/other     # notes from refs/notes/other
git log --notes --notes=refs/notes/other   # notes from both refs
```

Three distinct states — not passed at all, passed bare, passed with a value
— and it's repeatable. `multi` alone can't express "passed bare" (every
occurrence today must attach a value), and `default=` can't either (it's
already documented as "value used when the option isn't provided at all",
and combining it with `multi` is explicitly rejected — see
[`02-multi-value-options.md`](02-multi-value-options.md) — because "the
default list" has no single sensible meaning for zero-vs-many occurrences).

Neither gap is actually about lists, though: it's that `option` has no
concept of "this occurrence's value is optional."

## Proposed API

A new `key=value` attribute on `option`, `implicit=VALUE`. Its
presence is what makes the option's value optional — no separate bareword
modifier is needed:

```bash
option notes --notes REF multi implicit=refs/notes/commits \
    help="Show notes from REF"
```

The core mental model: **a bare occurrence behaves exactly as if the
implicit value had been typed explicitly.** `--notes` is indistinguishable,
downstream, from `--notes=refs/notes/commits` — same validation, same
population code path, same everything.

`implicit=` is orthogonal to the existing `default=` (which still
means "value used when the option is never provided at all") — the two can
be combined, matching Python argparse's `nargs='?'` + `const=` + `default=`
precedent:

```bash
option mode --mode VALUE default=off implicit=on \
    help="Feature mode"

# (not passed at all)   -> mode=off
# --mode                 -> mode=on
# --mode=custom          -> mode=custom
```

## Behavior

- **`--notes=value` / `--mode=value`** (long form with `=`): unchanged —
  always attaches the explicit value, exactly as it does for any other
  option today. No new logic needed here; this is the existing
  `--*=*` parse branch.
- **`--notes` / `--mode`** (long form, no `=`) and **`-n`** (short form),
  when the option declares `implicit=`: instead of requiring and
  consuming the next token, the parser records an occurrence with the
  declared `implicit` as the value — the *same* call
  (`_bo_set_option_value`) an explicit value would go through. A following
  bare token (e.g. `value` in `--notes value`) is **not** consumed; it's
  left for the next positional/option. This matches GNU `getopt_long`'s
  `--opt[=arg]` convention and is what avoids reintroducing the "is the
  next token this option's value or the next positional?" ambiguity
  `implicit=` exists to sidestep.
- **Short form (`-n`) is always bare** for an `implicit=` option —
  there's no `-nVALUE` or `-n value` attachment, consistent with
  betteropts' existing no-bundling, no-`-o=value` rule. An explicit value
  requires the long form with `=` (`--notes=value`); the short form can
  only ever substitute the implicit value.
- **Validation**: because a bare occurrence is recorded through the exact
  same path as an explicit value, `type=`/`choices=` validation applies to
  a substituted `implicit` exactly as it would if the user had typed
  it — unlike `default=`, which stays "trusted as-is, never validated"
  (that doesn't change; it's a separate, still-unvalidated fallback for the
  "never provided" case). No changes to `_bo_validate` are needed — this
  falls out for free from reusing `_bo_set_option_value`.
- **`multi` + `implicit=`**: each bare occurrence appends the
  implicit value to the array; each `--notes=value` occurrence appends that
  value. Zero occurrences still populates an empty array (or triggers
  `Missing required option` if `required` is also declared), unaffected by
  `implicit=`.
- **Defaults / population**: no changes needed to `_bo_apply_defaults` or
  `_bo_populate` — a bare occurrence is already a fully-formed value by the
  time either runs, same as today.

## Schema Validation Rules

- `implicit` is a recognized attribute only for `option` (added to
  `_bo_key_allowed`'s `option` case). Declaring it on a `flag` or
  `argument` is rejected the same way any other kind-mismatched attribute
  is today: `'implicit' is not a recognized attribute for flag 'x'.`
- The existing rule **"a `multi` option cannot declare a `default`"**
  (`_bo_finalize_schema`) is unchanged and still applies regardless of
  `implicit=` — `multi` + `default=` remains a schema error; the
  ambiguity that rule guards against (what a "default list" means for zero
  occurrences) isn't resolved by also having an `implicit=`.
- `implicit=` + `default=` together is allowed (they answer different
  questions: "value on a bare occurrence" vs. "value when never provided").
- `implicit=` + `required` is allowed: `required` only checks whether
  the option was provided at all (bare or with a value), unaffected by
  which kind of occurrence satisfied it.
- No schema-time check that `implicit`'s string satisfies the
  declared `type=`/`choices=` — same reasoning `default=` already
  documents (a schema-time check would need to run the same validators
  used at parse time, for a value that isn't actually being used yet); it's
  validated for real the moment a bare occurrence is actually parsed.

## Completion

`_bo_complete`'s replay loop (the simplified re-walk of `_bo_parse`'s logic
used to figure out what the in-progress word is completing) currently
treats every non-flag option as consuming the next word as its value. That
classification needs the same carve-out as the real parser: an
`implicit=` option must **not** be treated as consuming the next
word — it behaves like a flag for this purpose, so the word after a bare
`--notes` is offered the normal option-name/positional completions instead
of (wrongly) being completed as `--notes`'s value.

Completing an explicit value via `--notes=<partial>` is unaffected by this
feature — betteropts doesn't currently complete values attached with `=` in
the *current* (in-progress) word for any option, `implicit=` or not;
that's a pre-existing gap, out of scope here.

## Help Text

`_bo_annotations` gains a new fact, parallel to the existing `default:
<value>`: `implicit: <value>` when `implicit=` is declared. Example:

```bash
option notes --notes REF multi implicit=refs/notes/commits \
    help="Show notes from REF"
```

renders as:

```
--notes REF (repeatable, implicit: refs/notes/commits)
    Show notes from REF
```

The metavar continues to render unbracketed (`REF`, not `[REF]`) — the
annotation is what communicates optionality, consistent with how `required`
and `default:` are already surfaced there rather than via usage-line
syntax.

## Non-Goals (v1)

- No dynamic/computed implicit values (e.g. shelling out at parse time) —
  a literal string only, same restriction `default=` already has.
- No short-form value attachment (`-nVALUE`, `-n value`) — short form is
  always bare for an `implicit=` option, matching the confirmed
  design; an explicit value requires `--long=value`.
- No changes to `--*=<partial>` completion for the current word — pre-
  existing gap, not introduced or fixed by this feature.

## Backward Compatibility

Fully additive. `option` without `implicit=` is completely unaffected
— the new attribute only changes behavior for options that declare it.

## Suggested Test Coverage

- `test/unit/schema.bats`: `implicit` accepted on `option`; rejected
  (schema error) on `flag`/`argument`; `multi` + `default=` still rejected
  even when `implicit=` is also present; `implicit=` +
  `default=` together accepted; `implicit=` + `required` accepted.
- `test/unit/parser.bats`: bare long form (`--notes`) records the implicit
  value without consuming the next token; bare short form (`-n`) does the
  same; `--notes=value` still attaches the explicit value; a bare
  occurrence followed by another token leaves that token for
  positional/option parsing (e.g. `--notes foo` parses `foo` as a
  positional, not as `--notes`'s value).
- `test/unit/validation.bats`: an `implicit=` that fails
  `type=`/`choices=` is rejected with the usual `Invalid value:` error when
  a bare occurrence actually triggers it (unlike `default=`, which is never
  validated).
- `test/unit/population.bats`: `multi` + `implicit=` — mixed bare and
  explicit occurrences accumulate in order (`--notes --notes=other` →
  `notes=(refs/notes/commits other)`); non-`multi` `implicit=` +
  `default=` — all three states (never provided, bare, explicit value)
  populate correctly.
- `test/unit/completion.bats`: `--__complete` after a bare `implicit=`
  option offers option-name/positional candidates for the next word, not
  that option's value candidates.
- `test/integration/parsing.bats`: end-to-end fixture mirroring `git log
  --notes[=<ref>]` — not passed, passed bare, passed with a value, and
  passed multiple times mixing bare and explicit.