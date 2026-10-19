# Feature: Resolve Accepted but Ineffective Declarations

## Status

Proposed. Not yet implemented. Some cases are misleading defects; others
are current semantics requiring an explicit schema-policy ruling. No
blanket rejection or new validation policy has been approved.

## Problem and observed baseline

The strict-keyword work in [08](08-strict-schema-keywords.md) validates
recognized tokens. These recognized combinations still have ineffective
or misleading consequences at `05f8cb5`:

| Declaration | Actual result | Automated evidence |
| --- | --- | --- |
| Positional `-x` / `--name` | Stored, but not usable aliases and absent from positional help/completion. | C11 |
| Passthrough `type=` / `choices=` | Recognized type name required; tail not validated, yet `type=choice` choices appear in help. | C10/C19 |
| `choices=` without `type=choice` | No choice validation, candidates or annotation. | C07 |
| `type=choice` with absent `choices`, or explicit `choices=` | Both schemas accepted; nonempty and explicitly empty option inputs cannot match either empty list. | C08 checks absent attribute/nonempty input; the other cases are live-probe-only |
| Required option with `default=` | Schema accepted; omission fails before the fallback can apply. | C06 |

C IDs refer to [`compatibility.bats`](../test/unit/compatibility.bats).
The relevant source functions are `_bo_declare`, `_bo_finalize_schema`,
`_bo_validate`, `_bo_annotations` and `_bo_complete_value` in
[`betteropts.sh`](../betteropts.sh).

These synthetic declarations reproduce the main inconsistencies:

```bash
argument extra passthrough type=choice choices=one,two
# --not-a-choice succeeds, but help advertises choices: one, two.
```

```bash
option item --item required default=fallback
# An omitted --item still fails with Missing required option.
```

## Intended outcome and open decisions

1. Choose per case whether to reject the declaration, define an effective
   meaning, or explicitly support inert metadata. Do not treat token
   recognition as proof of runtime support.
2. Keep help/completion truthful about enforced constraints. In particular,
   [03](03-passthrough-arguments.md) deliberately excludes tail typing;
   adding passthrough validation would be a new policy, not a small help fix.
3. Decide whether a choice type requires a nonempty choices list, and
   whether empty string itself can be a choice. Preserve the distinction
   from optional scalar empty-value bypass, owned by
   [20](20-empty-positional-presence.md).
4. Decide whether the unreachable required-option default is rejected or
   documented. Changing requiredness so defaults satisfy it is a separate
   behavior choice, not an assumed remedy.

## Acceptance, compatibility and dependencies

Update schema diagnostics, help, completion, README matrix and affected
characterization tests together only for the chosen policies. Add separate
regressions for absent versus explicit-empty `choices=`, each with nonempty
and explicitly empty argv input. Check default and implicit interactions
without removing the `multi` + `default=` exclusion.
Rejecting previously accepted declarations is a compatibility break.

This extends 08's subject without reopening its implemented status or
duplicating its completed work. [22](22-schema-identity-validation.md)
owns invalid/colliding identities; changes may share finalization code but
have no mandatory ordering dependency. Proposed
[11](11-git-commitish-resolve-full-sha.md) includes passthrough/default
assumptions that must be reconciled with any selected typing policy; its
SHA-normalization work remains separate.
