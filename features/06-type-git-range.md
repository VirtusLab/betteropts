# Feature: `type=git-range` — Git Revision Range Validation

## Status

Implemented. Depends conceptually on
[`05-type-git-commitish.md`](05-type-git-commitish.md) (a range validator can reuse the
single-revision check as one of its cases) but should ship as its own
distinct type — see Relationship to `git-commitish` below.

## Problem

Some values aren't a single commit-ish, they're a *range*: `A..B`, `A...B`,
or a bare revision meaning "everything reachable from here." This is a
different shape than `type=git-commitish` and shows up in at least two real
commands in the audited consuming project:

- `todo/build`'s `range` argument (e.g. `last..tags/some-tag`), currently
  validated with `git rev-parse "$range" >/dev/null 2>&1` written directly
  in the script.
- `notes/copy-range`'s `from-range`/`to-range` positionals, currently
  unvalidated free strings, later fed into `git rev-list`/`git log` where a
  malformed range would surface as a confusing downstream failure instead
  of a clean parse-time error.

## Proposed API

```bash
argument range required type=git-range
argument from_range required type=git-range
argument to_range required type=git-range
```

## Validation

A value is valid if:

```bash
git rev-list --count "$value" >/dev/null 2>&1
```

succeeds. `git rev-list` accepts both a bare revision and `A..B`/`A...B`
range syntax, and fails cleanly on a malformed range or an unresolvable
endpoint — one check covers both shapes this type needs to accept, without
needing to hand-parse `..`/`...` ourselves.

Error shape, consistent with the rest of the library:

```
Invalid value:

RANGE last..bogus-tag (not a valid git revision range)
```

Same not-a-git-repo handling as `type=git-commitish`: check
`git rev-parse --is-inside-work-tree` first and report that distinctly if
it fails, rather than surfacing a confusing `git rev-list` stderr.

## Relationship to `type=git-commitish`

Deliberately kept as a **separate type**, not "git-commitish, but ranges also
allowed." A plain single-commit field (e.g. `state-marker/put`'s
`base_commit`) should *not* silently accept `a..b` range syntax — that
would be a wrong value there, not a valid edge case. Keeping the two types
distinct means each field only accepts the shape it actually means. The two
validators may share an internal "is this a resolvable git revision" helper
function, but the public `type=` names and their accepted syntax stay
separate.

## Completion

Same reasoning as `git-commitish`: no small enumerable candidate set for an
arbitrary range. **v1: no completion.**

## Non-Goals (v1)

- No structured decomposition of the range into its endpoints (e.g.
  automatically populating `${name}_from`/`${name}_to` variables) — the
  type just validates the whole string and populates it as given, same as
  every other type. A script that needs the individual endpoints parses
  them itself, same as today.
- No completion (see above).
- Does not validate that the range is non-empty (i.e. contains at least one
  commit) — `todo/build` currently treats "range resolves but has zero
  commits" as a distinct business-logic error (`$exitcode_no_commits`)
  *after* successful parsing, and that split should stay: this type only
  answers "is this syntactically and referentially a valid range," not "is
  it a non-empty one."

## Backward Compatibility

Fully additive — a new `type=` value; existing types are unaffected.

## Suggested Test Coverage

- `test/unit/validation.bats`: a bare revision, a `A..B` range, and a
  `A...B` range are all accepted; a range with a bogus endpoint is
  rejected; running outside a git repo produces the distinct
  "not inside a git repository" error.
- `test/unit/completion.bats`: `--__complete` for `type=git-range` returns
  no candidates.
- `test/integration/types.bats`: end-to-end fixture mirroring
  `notes/copy-range`'s two-range shape, using the same git-repo test
  fixture helper proposed in `05-type-git-commitish.md`.
