# Feature: Clarify Validation of Retained Scalar Option Values

## Status

Proposed documentation correction. Not yet implemented. The recommended
scope clarifies existing behavior; validating discarded occurrences would
require a separate explicit runtime-policy decision.

## Problem and observed baseline

At `05f8cb5`, `_bo_set_option_value` overwrites ordinary scalar option raw
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
consistent with existing last-occurrence-wins population. README's
lifecycle statement “every provided value” and
[13](13-implicit-value-options.md)'s claim that a bare implicit value is
validated “the moment” it is parsed overstate the actual lifecycle.

## Intended outcome and acceptance

1. Reconcile lifecycle/default/implicit documentation with retained scalar
   versus every multi value and the validation-after-parsing order.
2. State that unused or overwritten scalar implicit values are not checked
   at schema time or when encountered. Keep this distinct from defaults,
   which remain trusted, and from required occurrence checks.
3. Audit the full affected documents, including README, 02 and 13, for
   inconsistent claims. Preserve accurate existing statements; update the
   global matrix/evidence links if necessary.
4. Retain C20 and add a focused public-API regression if the documentation
   examples need one. A documentation-only implementation must leave
   parsing and failure precedence unchanged.

## Open decision and backward compatibility

The recommendation is to document current semantics. If rejecting invalid
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
