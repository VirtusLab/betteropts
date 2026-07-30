# Feature: `var=` Override for Flags

## Status

Implemented.

## Problem

`_bo_populate` already populates a flag's boolean result through its `var`
metadata field, exactly like `option`/`argument`:

```bash
for name in "${_bo_flags[@]}"; do
  var="$(_bo_meta_get "$name" var)"
  if [[ -n "${_bo_provided[$name]:-}" ]]; then
    declare -g "$var=true"
  else
    declare -g "$var=false"
  fi
done
```

`_bo_declare` defaults `var` to the declared name for every kind, including
`flag` (`_bo_meta_set "$name" var "$name"` runs unconditionally, before the
per-token loop). So the machinery to rename a flag's populated variable
already exists and already works correctly — but there's no way for a CLI
author to reach it. `_bo_key_allowed`'s `flag` allow-list is `help` only
(`features/08-strict-schema-keywords.md`), and README's `flag` grammar and
"Overriding the populated variable name" section explicitly restrict `var=`
to `option`/`argument`. A flag's populated variable name is therefore
always identical to its declared name, purely because the declaration
grammar was never extended to expose an already-working field — not
because of any underlying limitation in `_bo_populate` or storage.

This matters for the same reason `var=` exists for `option`/`argument` at
all: a flag's declared name doubles as its schema identifier (shown in
messages and used to key its metadata), which can clash with a more natural
shell variable name, or with a name already used for something else in the
calling script's scope. Today the only workaround is renaming the flag
itself, which also changes its `-x`/`--xxx` forms and `--help` output, when
only the populated variable name needed to change.

## Proposed API

Allow `var=name` as a recognized `flag` attribute, exactly matching
`option`/`argument`'s existing syntax:

```bash
flag verbose -v --verbose \
    var=is_verbose \
    help="Enable verbose logging"
```

Populates `$is_verbose` (`true`/`false`) instead of `$verbose`; `-v`/
`--verbose` and `--help` output are unaffected.

## Behavior

- Add `var` to `flag`'s recognized key=value attributes in
  `_bo_key_allowed`.
- No other implementation change: `_bo_declare` already defaults and stores
  `var` for every kind, and `_bo_populate` already reads it for flags. This
  is purely a validation-loosening change plus documentation — the
  underlying feature already works today for any kind whose grammar happens
  to expose `var=`.
- README's `flag` declaration grammar line and the "Overriding the
  populated variable name" section both get `var=name` added for `flag`,
  mirroring the existing `option`/`argument` wording exactly.

## Non-Goals (v1)

- No new metadata or storage — `var` already exists and is already read for
  flags; this only exposes it through the declaration grammar.
- Doesn't change any of `flag`'s other restrictions. `required`, `multi`,
  `default=`, `choices=`, and `type=` remain unsupported for `flag` — those
  are inert or nonsensical for a boolean switch, unlike `var=`, which is
  fully meaningful and already functionally wired up.
- Doesn't affect `--help`/`--usage`/completion rendering — those key off a
  flag's `short`/`long`/`help` metadata, never `var`.

## Backward Compatibility

Fully additive — no existing schema declares `flag ... var=...` today (it
would currently be rejected by `features/08-strict-schema-keywords.md`'s
strict validation as an unrecognized attribute), so nothing changes for
schemas that don't opt in. I checked: no test or fixture currently declares
this, so there's no existing "rejects flag var=" test that needs flipping.

## Suggested Test Coverage

- `test/unit/schema.bats`: `flag ... var=custom` is accepted by
  `_bo_finalize_schema`; `_bo_meta_get name var` reflects the override
  (mirroring the existing "option var overrides the populated variable
  name" / "argument var overrides the populated variable name" tests).
- `test/unit/population.bats`: a flag declared with `var=` populates the
  overridden variable name — `true` when provided, `false` otherwise —
  matching the existing `option`/`argument` var= override population
  tests.
- `test/integration/*.bats`: (optional) extend an existing fixture, or add
  a case to `varnames`, with a flag `var=` override, confirming the
  end-to-end behavior through `betteropts_parse`.
