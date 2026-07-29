# Feature: `type=git-commitish` — Git Revision Validation

## Status

Implemented.

## Problem

The built-in types (`string`, `integer`, `float`, `file`, `directory`,
`choice`) cover a lot, but a git-focused CLI has a value shape none of them
address: "this must be a commit-ish that resolves in the current repo" — a
SHA, branch, tag, or any other git revision expression.

This showed up in roughly ten commands while auditing a real consuming
project's CLI:

- `merge/reformat-pick`'s `commit`, `review/review`'s `base-commit`
  (currently validated with an ad hoc `git rev-parse` call written directly
  in the script body)
- `merge/remerge-diff`/`-difftool`/`-tree`'s `commit`
- `notes/copy`'s `from-commit`/`to-commit`, `notes/add`/`edit`'s `commit`
- `todo/complete`'s `sha`
- `state-marker/put`'s `base_commit`/`original_commit` — currently **not
  validated at all**, just passed through as opaque strings

Every one of these either hand-rolls the same `git rev-parse` check, or
skips validation entirely and lets a bad value surface as a confusing
failure several steps later.

## Proposed API

```bash
argument commit optional type=git-commitish default=HEAD
option base -b --base VALUE type=git-commitish
```

## Validation

A value is valid if:

```bash
git rev-parse --verify --quiet "${value}^{commit}" >/dev/null
```

succeeds. This accepts anything git itself would accept as a commit-ish
(SHA, abbreviated SHA, branch, tag, `HEAD~2`, etc.) and rejects anything
that doesn't resolve to a commit object (e.g. a tree/blob SHA without
`^{commit}`, or a name that doesn't exist).

On failure, report consistently with the existing `Invalid value:` shape:

```
Invalid value:

--base bogus (not a valid git revision)
```

**Not-a-git-repo case**: if `git rev-parse --is-inside-work-tree` fails
before we even get to validating the value, report that distinctly (e.g.
`Not inside a git repository`) rather than letting git's own stderr for the
inner call leak through confusingly.

## Completion

There's no small, enumerable candidate list for "any valid git revision" —
unlike `file`/`directory`, which complete against the real filesystem,
completing every possible commit-ish isn't practical or useful. **v1: no
completion** (same completion behavior row as `type=string` — empty
candidates from `--__complete`).

A future version could offer branch/tag name completion specifically (e.g.
`git for-each-ref --format='%(refname:short)' refs/heads refs/tags`) as an
opt-in refinement, but that's a deliberately separate, smaller value space
than "any commit-ish" and shouldn't be bundled into v1 of this type.

## Non-Goals (v1)

- No distinction between "must be a branch," "must be a tag," "must be a
  SHA specifically" — one type, any commit-ish, matching what every
  motivating example actually needs.
- No completion (see above).
- Does not imply anything about the working tree being clean, HEAD being
  detached, etc. — purely "does this string resolve to a commit object."

## Backward Compatibility

Fully additive — a new `type=` value; existing types are unaffected.

## Suggested Test Coverage

- `test/unit/validation.bats`: valid SHA/branch/tag/`HEAD~N` accepted;
  nonexistent ref rejected; a tree/blob SHA (not a commit) rejected; running
  outside a git repo produces the distinct "not inside a git repository"
  error rather than a raw git stderr dump.
- `test/unit/completion.bats`: `--__complete` for `type=git-commitish` returns no
  candidates (matches `string`'s empty-completion row).
- `test/integration/types.bats`: end-to-end fixture with a `type=git-commitish`
  option and argument, run against a real throwaway git repo. This is new
  territory for betteropts' own test suite (it has no git-aware tests
  today) — a `setup_git_repo`-style helper, similar to the one already used
  by the consuming project's `notes/show` tests, would need to be added to
  `test/`.
