# Feature: Strict Schema Keyword Validation

## Status

Implemented.

## Problem

`_bo_declare` (the shared token parser behind `flag`/`option`/`argument`)
accepts a lot of input it doesn't actually understand, and never says so:

- **Any `key=value` token is accepted, regardless of the key.**
  `_bo_meta_set "$name" "${tok%%=*}" "${tok#*=}"` stores whatever's left of
  the `=` verbatim as a metadata field name. A typo — `deafult=4`,
  `chocies=a,b,c`, `tpye=integer` — doesn't error; it silently creates a
  dead metadata field under the misspelled key, while the real field
  (`default`/`choices`/`type`) stays unset. The CLI author gets no
  indication anything is wrong: no default gets applied, no choice list
  gets enforced, no type gets validated — it just quietly behaves as if
  the attribute was never declared.
- **Cardinality/requiredness keywords aren't checked against the
  declaration kind.** `required`, `optional`, `variadic`, and `passthrough`
  are recognized for every kind (`flag`, `option`, `argument`), but only
  `argument` actually has a cardinality concept, and only `option`
  documents `required` as a modifier. This was the concrete bug fixed
  outside this proposal (`option jobs -j --jobs N optional` silently set
  `required=true` instead of erroring, later failing validation with a
  confusing "Missing required option"). That specific case is now
  rejected by `_bo_finalize_schema`, but the same class of gap remains
  elsewhere:
  - `multi` is accepted — and silently stored as live-looking metadata —
    on an `argument` or a `flag`, neither of which does anything with it.
    `argument reviewers required multi` and `flag verbose -v --verbose
    multi` both parse without complaint; the `multi` is simply never read
    again.
  - `required` itself is still accepted on a `flag`, per the same
    reasoning: nothing downstream reads a flag's `required` metadata
    (`_bo_validate` only checks it for names in `_bo_options`), so it's
    live-looking but inert.
- **Any other unrecognized bareword is silently accepted or silently
  dropped**, depending on kind:
  - For an `option`, the *first* unrecognized bareword becomes the
    metavar; every one after that is silently discarded with no error
    (`option output -o --output PATH BOGUS` accepts `BOGUS` invisibly —
    it's parsed but never stored anywhere, and never surfaced as a
    schema problem).
  - For a `flag` or `argument`, an unrecognized bareword (e.g. a
    misspelled cardinality keyword like `requried`, or a copy-paste
    leftover) falls into the same catch-all and is dropped with zero
    effect and zero error.
- **An `argument`'s cardinality is never checked for presence or
  uniqueness**, even though README states "Exactly one of `required`,
  `optional`, `variadic`, or `passthrough` must be given." This is a
  distinct gap from the misspelling case above (which is about rejecting
  a bad token that *was* given) — here there's no bad token to catch:
  - **Omitted entirely**: `argument src` (no cardinality keyword at all)
    leaves `_bo_meta_get src cardinality` as `""`. Every downstream
    check (`_bo_assign_positionals`, `_bo_validate`) treats `""`
    identically to `optional` — the argument silently becomes optional,
    with no schema error and no indication the author forgot the
    keyword. Confirmed: `argument src` followed by `betteropts_parse
    "$@"` with no positional given returns success with `src` empty,
    exactly as if `optional` had been declared.
  - **Given more than once**: `argument src required optional` — both
    are individually valid keywords for `argument`, so neither is
    rejected by the fix above; the second silently overwrites
    `cardinality`, and the conflict (the author almost certainly meant
    only one) is never flagged. Confirmed: this parses cleanly and
    behaves as `optional`, with no error or warning that `required` was
    specified and then immediately discarded.

In every case above, the author's mistake is invisible until (at best) the
resulting CLI behaves subtly wrong at runtime — no default, no
choice-list enforcement, no required-check, an unexplained missing
argument — and (at worst) it behaves *actively* wrong, as the fixed
`optional`/`variadic`/`passthrough`-on-`option` bug did. A hand-authored
declarative schema is exactly the kind of input this library should be
strict about, the same way `_bo_finalize_schema` already refuses to
guess when two `argument`s both declare `variadic`.

## Proposed API

No new declaration syntax. This only tightens validation of the existing
`flag`/`option`/`argument` grammar (README's per-kind modifier tables are
already the intended contract — `flag` supports `-x`/`--xxx`/`help=`
only; `option` additionally supports `METAVAR`/`required`/`type=`/
`choices=`/`default=`/`multi`/`var=`; `argument` additionally supports
exactly one of `required`/`optional`/`variadic`/`passthrough`, plus
`type=`/`choices=`/`default=`/`var=`). This feature makes the parser
enforce that contract instead of silently tolerating anything outside it.

## Behavior

- Maintain an explicit allow-list of recognized attribute keys
  (`type`, `choices`, `default`, `var`, plus `metavar` for `option`) per
  kind, and of recognized bareword keywords (`required` for `option`;
  `required`/`optional`/`variadic`/`passthrough` for `argument`; `multi`
  for `option` only) per kind.
- A `key=value` token whose key isn't in that kind's allow-list is a
  schema error (surfaces the offending key so a typo is obvious, e.g.
  `Unknown attribute 'chocies' for option 'mode' (did you mean
  'choices'?)` — exact wording TBD, but it must name the bad key and the
  declaration).
- A bareword keyword not valid for the given kind (`multi`/`required` on
  a `flag` or `argument`, any cardinality keyword on a `flag` or
  `option` other than `required` on `option`) is a schema error, unifying
  with the check `_bo_finalize_schema` already added for
  `optional`/`variadic`/`passthrough` on non-`argument` kinds.
- For `option`, any bareword beyond the first (the metavar) is a schema
  error rather than a silent no-op — there is never a legitimate reason
  for a second bare metavar-shaped token.
- For `flag`/`argument`, any bareword that isn't a recognized keyword is
  a schema error rather than falling through the catch-all unnoticed.
- Every `argument` must declare **exactly one** of
  `required`/`optional`/`variadic`/`passthrough` — zero occurrences (a
  missing cardinality entirely) and two-or-more occurrences (a conflict)
  are both schema errors, not silently coerced to `optional` or to
  whichever keyword happened to be seen last. This is a presence/
  uniqueness check on top of the per-token rejection above: even a
  schema where every individual token is independently valid can still
  violate this constraint (`argument src required optional` — both
  tokens are valid `argument` keywords, but declaring both together
  isn't).
- These are schema errors, not user-input errors: following this
  project's existing convention (`_bo_finalize_schema`'s
  multi+default / required+default / variadic-ordering checks), they
  should be caught as early as possible — ideally at declaration time in
  `_bo_declare` itself (a broken schema is a bug in the CLI author's own
  script, so failing loudly and immediately, before any argument parsing
  even happens, is more useful than deferring to `_bo_finalize_schema`).
  Whether that means giving `_bo_declare`/`flag`/`option`/`argument`
  themselves a return-non-zero-and-let-the-caller-decide contract (a
  change to their current always-succeeds shape), or keeping the
  "record now, validate in `_bo_finalize_schema`" pattern the
  `optional`/`variadic`/`passthrough` fix used, is an implementation
  choice for whoever picks this up — not decided here.

## Non-Goals (v1)

- No did-you-mean/Levenshtein-distance suggestion engine — if a
  misspelled key's correction is included in an error message at all, a
  fixed lookup table (or nothing beyond naming the bad key) is enough;
  fuzzy suggestion matching is out of scope.
- No change to what's valid — this doesn't add or remove any currently
  *documented* modifier, it only rejects what was never documented but
  happened to be silently tolerated.
- Does not revisit whether `flag` *should* gain `required`/`multi`/
  `default=`/`choices=` support — the grammar's current shape (per
  README) is taken as given; this proposal only enforces it.

## Backward Compatibility

Not additive — any existing schema that (accidentally or not) relies on
today's laxity will start failing schema validation once this lands.
Concretely, this includes the schema used by
`test/unit/help_usage.bats`'s `"_bo_annotations is never shown for a
flag, regardless of how it's declared"` test, which deliberately declares
`flag verbose -v --verbose required default=true help="..."` specifically
*because* that's currently accepted — that test's own premise, a `flag`
currently accepting `required`/`default=` without complaint, goes away
once this lands, and the test needs to be rewritten to prove the same
underlying property (`_bo_annotations` never annotates a `flag`) without
relying on schema laxity to declare its fixture.

Any schema that only uses documented modifiers for each kind is
completely unaffected.

## Suggested Test Coverage

- `test/unit/schema.bats`: a `key=value` token with an unrecognized key
  is rejected, for each kind (`flag`, `option`, `argument`); the specific
  bad key is named in the error.
- `test/unit/schema.bats`: `multi` on a `flag` or `argument` is rejected;
  `required` on a `flag` is rejected — closing the two gaps this
  proposal identifies beyond the already-fixed
  `optional`/`variadic`/`passthrough`-on-non-`argument` case.
- `test/unit/schema.bats`: a second bareword after an `option`'s metavar
  is rejected; an unrecognized bareword on a `flag` or `argument` (e.g. a
  misspelled cardinality keyword) is rejected.
- `test/unit/schema.bats`: an `argument` declared with no cardinality
  keyword at all is rejected; an `argument` declared with two (e.g.
  `required optional`) is rejected.
- `test/unit/schema.bats`: every currently-documented modifier for every
  kind still declares cleanly (a regression guard proving the stricter
  parser doesn't reject anything legitimate).
- Rewrite the `_bo_annotations`-never-shown-for-a-flag unit test (see
  Backward Compatibility) to use a plain `flag` declaration and assert
  directly against `_bo_meta_get`/`_bo_annotations` behavior for the
  `flag` kind, rather than depending on a `flag ... required default=...`
  declaration succeeding.
