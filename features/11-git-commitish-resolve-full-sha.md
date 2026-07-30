# Feature: `type=git-commitish` Resolves to the Full SHA

## Status

Proposed. Not yet implemented.

## Problem

`_bo_validate_type`'s `git-commitish` case only checks that a value
resolves to a commit; it never rewrites the value itself:

```bash
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
```

Whatever string the caller passed — a full SHA, an abbreviated SHA, a
branch name, a tag, or an expression like `HEAD~2` — is exactly what ends
up in `_bo_raw[$name]` and, later, the populated variable. Two callers
that pass different spellings of the same commit see different values:

```bash
mycommand --base main
mycommand --base a1b2c3d
mycommand --base HEAD~2
```

all populate `$base` with the literal text the user typed, even though
all three might resolve to the same commit. A consuming script that wants
to log the resolved commit, compare it against another commitish for
equality, or pass it to something that needs the unambiguous full form has
to re-run `git rev-parse` itself — despite `betteropts` already having run
that exact command once during validation.

This was noticed while reviewing `features/05-type-git-commitish.md`: the
validation call (`git rev-parse --verify --quiet "${value}^{commit}"`)
already computes the full SHA as its stdout when not redirected — today
that output is thrown away (`>/dev/null`).

The same inconsistency exists between a provided value and a `default=`.
`HEAD` is a common default for a git-commitish argument:

```bash
argument commit optional type=git-commitish default=HEAD
```

If only explicitly-provided values were resolved, `mycommand` (argument
omitted) would populate the literal string `HEAD`, while
`mycommand $(git rev-parse HEAD)` would populate the same commit's full
SHA — two invocations referring to the identical commit, populating
differently, purely because of which one happened to spell it out. That's
the same "different spellings, different populated values" problem this
feature exists to fix, just triggered by omission instead of by an
alternate spelling — so resolution needs to apply to defaults too, not
just to values that were actually typed on the command line.

## Proposed API

No new declaration syntax. `type=git-commitish` behaves exactly as
declared today:

```bash
option base -b --base VALUE type=git-commitish
argument commit optional type=git-commitish default=HEAD
```

Only the populated value changes: instead of the raw input string, the
variable is populated with the full, resolved SHA.

```bash
mycommand --base main
# today:      base=main
# proposed:   base=8f3a9c2e1d7b4560f2a1c9e8d7b6a5c4e3d2f1a0
```

## Behavior

- `_bo_validate_type`'s `git-commitish` case captures
  `git rev-parse --verify --quiet "${value}^{commit}"`'s stdout instead of
  discarding it, and that becomes the resolved value on success.
- `_bo_validate_type` currently only reports pass/fail (via its return
  code and the `_bo_die_*` calls) — it has no channel back to its callers
  for a rewritten value. It gains one: on a successful `git-commitish`
  resolution, it prints the resolved SHA to stdout (mirroring how
  `_bo_meta_get` already communicates values to callers via stdout); every
  other type's case prints nothing and callers keep using the original
  value, so non-git-commitish behavior is unchanged.
- `_bo_validate`'s three call sites for provided values —
  `_bo_raw[$name]` for a scalar option, `_bo_multi_values["$name.$idx"]`
  for a `multi` option, `_bo_raw[$name]`/`_bo_variadic_values[i]` for an
  argument — capture `_bo_validate_type`'s stdout and, when it printed a
  resolved value, overwrite the stored raw value with it before returning.
  This runs once per value, immediately after that value's own validation
  call, so a validation failure still aborts before any rewrite happens.
- Applies to every position a `git-commitish` value can appear: a plain
  option, a `multi` option (each occurrence independently), and an
  argument (`required`/`optional`, and each element of a `variadic`/
  `passthrough` array where a CLI author declared `type=git-commitish` on
  it).
- `type=git-range` is unaffected — a range doesn't identify a single
  commit object, so there's no single resolved SHA to rewrite it to.
- `_bo_apply_defaults` — which fills in `default=` for an option/argument
  that was never provided — gains the equivalent treatment for a
  `git-commitish`-typed field: after filling in the default text, it's
  immediately resolved through the same `git rev-parse --verify --quiet
  "${value}^{commit}"` call, and the resolved SHA is what gets stored (and
  later populated), not the literal default text. `default=HEAD` on a
  `git-commitish` argument therefore populates the current commit's full
  SHA, exactly as if the caller had typed `HEAD` explicitly.
  - This is a deliberate, narrow exception to the general rule (still true
    for every other type) that "a default is trusted as-is and never
    itself type-checked": for `git-commitish` specifically, resolving
    *is* the whole point of the type, so a default that skipped resolution
    would reintroduce the exact inconsistency described in Problem, just
    moved from "provided vs. provided" to "provided vs. default."
  - If a `git-commitish` default fails to resolve — the CLI author wrote
    `default=HEDA` by typo, or the command runs outside a git repository
    — `_bo_apply_defaults` reports it the same way an invalid *provided*
    value would (`Invalid value:` / `Not inside a git repository:`) and
    exits, instead of silently populating unresolvable text. This is new:
    today a bad default is never even attempted to be checked. Here it has
    to be, because "resolve it" and "check whether it resolves" are the
    same git call — there's no way to resolve a default without also
    finding out whether it's valid.

## Non-Goals (v1)

- Doesn't add an opt-out. `git-commitish` already promises "this resolves
  to a commit"; populating the canonical form of what was already promised
  isn't a new validation constraint, so there's no new failure mode to
  gate behind a flag.
- Doesn't change the `Invalid value:` / `Not inside a git repository:`
  error *shapes* — a default that fails to resolve reuses the exact same
  messages a bad provided value would, just triggered from
  `_bo_apply_defaults` instead of `_bo_validate`.
- Doesn't extend this "defaults get resolved/checked" exception to any
  other type. `option`/`argument` defaults for `string`, `integer`,
  `file`, etc. remain fully untouched — trusted as-is, never checked, as
  today. Only `git-commitish` has the property that makes resolving (and
  therefore incidentally validating) its default the correct behavior
  rather than a surprising new constraint.
- Doesn't affect completion (`type=git-commitish` still offers no
  candidates, per `features/05-type-git-commitish.md`).

## Backward Compatibility

Not additive — any existing schema using `type=git-commitish` changes what
gets populated for an abbreviated SHA, branch, tag, relative expression, or
default (a full SHA input is unaffected, since it already *is* the
resolved form). I checked `test/fixtures/git_commitish` and every
`type=git-commitish` test in
`test/unit/validation.bats`/`test/integration/types.bats`: none assert
that the populated value equals the exact input string for a non-SHA
input (the existing assertions check pass/fail, not the populated value's
exact text), so nothing currently shipped breaks on that front — but the
`git_commitish` fixture's `echo "commit=${commit:-}"` output changes for
its `default=HEAD` case (from the literal `HEAD` to a resolved SHA), and
the existing integration test asserting `commit=HEAD` (see below) breaks
outright and must be rewritten, not just re-verified. Any consuming
project asserting on either exact text — a non-SHA populated value, or a
literal `HEAD` default — would need updating.

## Suggested Test Coverage

- `test/unit/validation.bats`: a `git-commitish` option/argument given an
  abbreviated SHA, a branch name, a tag, and a relative expression
  (`HEAD~1`) each populate the full SHA (compare against
  `git rev-parse HEAD`/`HEAD~1` run directly in the test); a full SHA
  input populates unchanged; a `multi` option with several git-commitish
  occurrences resolves each independently; a `variadic` argument of
  git-commitish values resolves each element.
- `test/unit/validation.bats` (or a defaults-focused file): an omitted
  `git-commitish` argument/option with `default=HEAD` populates the
  current commit's resolved full SHA, not the literal string `HEAD`; a
  bogus `default=` on a `git-commitish` field reports `Invalid value:`
  when the argument is omitted (not silently populated); running outside
  a git repository with an omitted `git-commitish` default reports `Not
  inside a git repository:` rather than populating the literal default.
- `test/integration/types.bats`: extend "type=git-commitish accepts a full
  SHA, a branch, and a relative expression" (or add a new case) to assert
  the fixture's printed output is the resolved full SHA for the
  branch/relative-expression inputs, not the literal input text.
- `test/integration/types.bats`: rewrite "an omitted git-commitish
  argument's default is applied without being validated" — its premise is
  now false for `git-commitish` specifically. Replace it with a test
  asserting the omitted-argument case populates the resolved SHA for
  `HEAD` (e.g. compare `commit=` against `git rev-parse HEAD` computed in
  the test), and consider renaming it to reflect that `git-commitish`
  defaults are now resolved-and-checked, unlike every other type's
  defaults.
