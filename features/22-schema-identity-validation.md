# Feature: Define and Validate CLI Schema Identities

## Status

Proposed. Not yet implemented. Identifier, spelling, collision and reserved
name policies must be decided before introducing blanket rejections.

## Problem and observed baseline

At `05f8cb5`, `_bo_declare` / `_bo_finalize_schema` do not comprehensively
validate schema names, shell output identifiers, required flag/option
spellings, spelling shape, uniqueness or reserved spellings. Source
inspection establishes missing checks, not a guarantee that every
arbitrary invalid string can be used safely.

Verified examples include:

1. C22 in [`compatibility.bats`](../test/unit/compatibility.bats): duplicate
   `--same` names select the first matching declaration; duplicate output
   variables can later be overwritten by an unprovided flag's false value.
2. C27 in [`integration/compatibility.bats`](../test/integration/compatibility.bats):
   a declared `--help` is schema-accepted, but the built-in takes precedence.
3. Independent baseline trials: an option with no spelling can populate a
   default; a literally declared `-vf` is accepted as one exact spelling,
   with no bundling into `-v` and `-f`.
4. Cross-kind shared output names are written in `_bo_populate` order:
   flags, then options, then arguments, independently of argv order. An
   independent flag/option trial observed the option overwriting the flag.

```bash
flag first --same var=result
flag second --same var=result
betteropts_parse --same
# Lookup provides first; population subsequently writes result=false.
```

## Intended outcome and open decisions

1. Define valid schema/output identifiers, spelling shapes and whether
   flag/option declarations require a usable spelling. Decide how to treat
   intentionally default-only declarations and literal multi-letter short
   spellings; they are current behavior, not proven accidental defects.
2. Define separate uniqueness rules for schema names, short/long spellings
   and output variables. Decide whether deliberate shared output variables
   are allowed and, if so, their precise population contract.
3. Define reserved built-in spellings and any internal-name restrictions.
   Reject conflicts early where that is the chosen policy, before help,
   completion or population can produce misleading results.

## Acceptance and test work

Cover duplicate names across kinds, duplicate aliases and output variables,
missing/malformed spellings, invalid Bash identifiers and reserved names.
Pin diagnostics for rejected cases and behavior for intentionally accepted
ones. Trial preexisting scalar/array, exported and readonly output variables
before promising their treatment: their complete runtime behavior was not
verified by the matrix. Preserve no-bundling behavior for ordinary spellings.

## Backward compatibility and dependencies

Stricter identity checks can reject working declarations. Inventory current
fixtures and affected consumers before adopting rejections; do not infer
that every collision is a typo. Proposed [04](04-exclusive-flag-groups.md)
owns mutual exclusion, not identity validation or shared-output semantics.
[08](08-strict-schema-keywords.md) owns implemented keyword checks;
[19](19-inert-declaration-policy.md) owns recognized but ineffective metadata.
These tasks can be decided independently but must agree on finalization
and reserved-name behavior with [23](23-builtin-prescan-policy.md).
