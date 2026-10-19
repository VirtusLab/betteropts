# Feature: Reconcile Built-in Prescan with Argument Consumption

## Status

Proposed contract/policy work. Not yet implemented. Raw prescan is existing
documented behavior; its differences from parser consumption are not by
themselves a ruling to replace it.

## Problem and observed baseline

At `05f8cb5`, `betteropts_parse` finalizes the schema, then scans raw argv
for the first `-h`, `--help` or `--usage` up to the first literal `--`.
Only afterward does first-word `--__complete` dispatch or `_bo_parse` run.
The prescan does not know option arity, implicit values or passthrough
state. `_bo_parse` consumes a mandatory next token verbatim, including `--`.

C24–C26 in
[`integration/compatibility.bats`](../test/integration/compatibility.bats)
establish schema-error precedence, first help/usage wins, help as an
otherwise-consumed value, help after an unknown passthrough token, explicit
marker protection, and completion dispatch only in argv position one.

For a fresh option schema, `--item --help` prints help. In contrast,
`--item -- --help` stops raw prescan at the consumed value `--`; actual
parsing continues and encounters `--help` as an unknown option. The latter
combined case is source-established in `betteropts_parse` / `_bo_parse`
and confirmed by a synthetic public-API trial, but needs a dedicated
automated regression. C17 separately checks marker consumption as a value.
The same trial with `argument extra passthrough` succeeds with `item=--`
and `extra=(--help)`, without printing help.

## Intended outcome and open decisions

1. Decide whether raw help/usage precedence is retained and documented
   precisely, or detection follows parser consumption/capture boundaries.
   Keeping help available beside otherwise-invalid argv is part of the
   existing contract and must be weighed explicitly.
2. Decide consumed-marker behavior, built-in-looking mandatory values and
   built-ins after passthrough capture. Do not change the general parser's
   verbatim mandatory-value rule incidentally.
3. Specify completion dispatch position and its relationship to help/usage
   prescan and the protocol marker. Distinguish these mechanisms instead
   of describing all built-ins as a uniform raw scan.

## Acceptance and test work

Add the missing combined consumed-marker/public-built-in cases, with and
without passthrough. Cover ordinary/implicit/multi options, requiredness,
unknown options, first help/usage ordering, explicit markers and completion
protocol words. Keep schema-error precedence unless expressly changed.
Update README lifecycle prose, the matrix and affected C24–C26 assertions
together for the chosen policy; retain the original counterexamples.

## Backward compatibility and dependencies

Changing detection may turn help output into a value, tail capture or parse
error, or the reverse. Document those effects before implementing.
[16](16-passthrough-boundary-contract.md) owns parser capture policy;
[17](17-completion-boundary-replay.md) owns completion replay after parsing
boundaries; [22](22-schema-identity-validation.md) owns reserved-name
validation. Decisions interact, but existing consumed-marker and raw-scan
documentation cases can be handled without waiting for unrelated changes.
