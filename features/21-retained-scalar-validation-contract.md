# Feature: Clarify Validation of Retained Scalar Option Values

## Status

Implemented documentation correction. Runtime behavior is unchanged;
validating discarded occurrences would require a separate explicit
runtime-policy decision.

## Retained-value contract

`_bo_set_option_value` overwrites ordinary scalar option raw
values, and `_bo_validate` checks only the final retained value. A `multi`
option retains and validates every occurrence. An implicit substitution
uses the same storage path as explicit input; it is not validated at the
moment the bare token is parsed.

C20 in [`compatibility.bats`](../test/unit/compatibility.bats) checks
ordinary and implicit overwrite cases. This synthetic fresh-schema
example succeeds:

```bash
option item --item N type=integer implicit=invalid
betteropts_parse --item --item=1
# item=1; the discarded implicit value is never validated.
```

The corresponding `multi` declaration fails on `invalid`. This is
consistent with last-occurrence-wins scalar population. Unused implicit
literals are not validated at schema time, and overwritten scalar
implicit or explicit values are not validated after parsing. Defaults
remain trusted and are applied after validation. Required options still
need an occurrence; an implicit occurrence can satisfy that requirement.

## Intended outcome and acceptance

1. [x] Reconcile lifecycle/default/implicit documentation with retained scalar
   versus every multi value and the validation-after-parsing order in
   [README](../README.md),
   [02](02-multi-value-options.md#behavior) and
   [13](13-implicit-value-options.md#behavior).
2. [x] State that unused or overwritten scalar implicit values are not checked
   at schema time or when encountered. Keep this distinct from defaults,
   which remain trusted, and from required occurrence checks.
3. [x] Audit the full affected documents, including README, 02 and 13, for
   inconsistent claims. Preserve accurate existing statements, including
   DESIGN.MD's parse/validate/default lifecycle. The global matrix already
   records final scalar versus every multi validation; its C5 link now
   points to this implemented contract without calling it an open policy.
4. [x] Retain C20, which already covers the example and corresponding multi
   failure. No additional regression is needed for this documentation-only
   correction; parsing and failure precedence remain unchanged.

## Runtime policy and backward compatibility

This correction documents current semantics. If rejecting invalid
discarded scalar occurrences is desired instead, decide that explicitly:
it requires retaining or validating more data and changes successful
invocations into errors. No such runtime policy is approved by this record.

## Dependencies

No implementation dependency on [20](20-empty-positional-presence.md): it
owns the separate scalar positional empty-value question. Passthrough
validation/help is owned by [19](19-inert-declaration-policy.md), and
proposed [11](11-git-commitish-resolve-full-sha.md) owns Git normalization
and its proposed default exception. Do not expand this wording correction
to implement either change.
