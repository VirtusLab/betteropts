# Feature: Define Explicit Empty Positional Presence

## Status

Proposed. Not yet implemented. Whether explicit empty input should count
as supplied remains an open policy decision.

## Problem and observed baseline

At `05f8cb5`, `_bo_assign_positionals` stores an explicit scalar `''`, but
`_bo_validate` and `_bo_apply_defaults` use nonempty value checks for
scalar arguments. C16/C23 in
[`compatibility.bats`](../test/unit/compatibility.bats) characterize:

1. Required scalar `''` reports a missing required argument.
2. Optional `type=integer` scalar `''` bypasses integer validation.
3. Optional scalar `''` is replaced by its declared default.
4. An explicitly empty option is provided and type-checked; empty implicit
   string can satisfy option requiredness. Typed array elements are also
   checked when empty.

For example, in a fresh schema:

```bash
argument item optional type=integer default=fallback
betteropts_parse ''
# item=fallback; neither the empty input nor the trusted default errors.
```

The default remains trusted, consistent with
[01](01-argument-defaults.md); the discrepancy is that “omitted” also means
an explicitly supplied empty scalar. Raw shell argument boundaries alone
do not imply that scalar presence is tracked separately today.

## Intended outcome and open decisions

1. Rule on preserving this empty-as-omitted policy versus tracking scalar
   positional presence independently of content.
2. For the selected policy, explicitly define requiredness, validation and
   default replacement for omitted and empty required/optional scalars.
   Compare with options and variadic elements rather than assuming all
   declaration kinds must share one answer.
3. Align README argument/default/lifecycle prose, feature 01 and the
   compatibility matrix with that decision. Do not start validating trusted
   defaults incidentally; that would be a separate contract change.

## Acceptance and test work

Exercise omitted/empty/nonempty input for required and optional scalars,
with/without defaults, for string and constraining types. Check multiple
positional slots so an empty supplied token cannot silently move a later
token into the wrong slot. Preserve empty array elements and option
occurrence semantics unless explicitly changed. Keep C16/C23 as baseline
evidence until their expectations are deliberately updated.

## Backward compatibility and dependencies

Changing empty presence can turn success into type errors, missing-input
errors into success, or default values into empty strings. Document these
effects. [19](19-inert-declaration-policy.md) owns empty choice-list policy;
[21](21-retained-scalar-validation-contract.md) owns scalar option overwrite
documentation, not this presence decision. Proposed
[11](11-git-commitish-resolve-full-sha.md) separately proposes a narrow
default-resolution exception; do not duplicate or silently implement it.
