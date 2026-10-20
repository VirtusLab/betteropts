# Feature: Reconcile Built-in Prescan with Argument Consumption

## Status

Standalone help/usage restriction implemented. The broader relationship between
raw prescan and parser consumption remains proposed contract/policy work.
Their differences are not by themselves a ruling to replace raw detection.

## Problem and observed baseline

At `05f8cb5`, `betteropts_parse` finalized the schema, then scanned raw argv
for the first `-h`, `--help` or `--usage` up to the first literal `--`, printed
its output and exited 0. Only afterward did first-word `--__complete` dispatch
or `_bo_parse` run. The prescan did not know option arity, implicit values or
passthrough state. `_bo_parse` consumes a mandatory next token verbatim,
including `--`.

A consumer migrating a quoted question tuple to separate fields reported:

```text
add-tag FILE --slug RetryPolicies --judged-at HEAD \
  --question Q-backoff medium --help
```

The passage token triggered help and exit 0 without executing the write after
`betteropts_parse`. A caller could therefore mistake a skipped write for
successful execution. This is the reason for the restriction below.

## Implemented standalone restriction

1. Schema finalization still precedes all built-in handling. A schema error
   exits 1 even when help, usage or completion was requested.
2. Raw argv is scanned for exact `-h`, `--help` and `--usage` tokens before
   the first literal `--`. Each succeeds only when the complete argv consists
   of that one token. Standalone aliases print help, standalone `--usage`
   prints summary/usage, and each exits 0 before business logic, bypassing
   missing required arguments/options and value validation.
3. Any detected help/usage token with another argv token causes an
   `Invalid invocation` error on stderr, explaining that the built-in must be
   used alone, and exits 1 before parsing or the caller's business/write logic.
   This includes values, field slots, implicit/multi options, unknown options,
   positionals, passthrough tails, repeated built-ins, help/usage combinations
   in either order, and a following literal `--`. Rejection prints no help.
   `--usage` follows the same rule because its former successful early exit
   could hide a skipped write in exactly the same way.
4. Detection boundaries stay raw: the first literal `--` ends scanning even
   when parsing later consumes it as a mandatory value/field. Thus
   `--item --help` now rejects the mixed invocation; `--item -- --help`
   still consumes `item=--` and encounters an unknown `--help`, or captures
   it as passthrough data when declared. A real marker protects later data.
   Attached `--item=--help` stays data, and `--item=--` does not contain a raw
   marker. Equals-pair `key=--help` likewise remains data.
5. Only a first argv word of `--__complete` dispatches completion, after the
   help/usage scan. The protocol marker in `--__complete -- <words...>`
   protects completion words. Malformed `--__complete --help` now rejects
   as mixed help; a later `--__complete` remains an ordinary parser token.

This intentionally breaks the former successful mixed help/usage exits,
including the old first-help/usage-wins behavior. Callers must request help or
usage separately. The restriction prevents an intercepted built-in from
silently looking like a successful command invocation without changing which
mandatory values or passthrough tokens the parser consumes.

## Intended outcome and open decisions

1. Decide whether detection should eventually follow parser consumption/capture
   boundaries instead of raw argv. The standalone restriction above is settled;
   the broader boundary policy is not. Previously keeping help available beside
   otherwise-invalid argv does not override the new mixed-invocation error.
2. Decide consumed-marker behavior, built-in-looking mandatory values and
   built-ins after passthrough capture for any future boundary redesign. Do not
   change the general parser's verbatim mandatory-value rule incidentally.
3. Any future redesign must specify completion dispatch position and its
   relationship to help/usage detection and the protocol marker. These remain
   separate mechanisms; completion is not a uniform raw-scanned built-in.

## Acceptance and test work

[`integration/help_usage.bats`](../test/integration/help_usage.bats) covers the
consumer's exact argv shape in a synthetic CLI with a real temporary corpus file and a write after
`betteropts_parse`, verifying status 1, explanatory stderr and unchanged contents
in plain, `-e`, `-u` and `-eu` callers. A successful literal passage exercises the
same write. It also covers standalone built-ins, both mixed argument orders,
ordinary/implicit/multi/field/equals inputs, unknown options, positionals,
passthrough capture, duplicate built-ins and a following marker.

C24–C26 and C44 in
[`integration/compatibility.bats`](../test/integration/compatibility.bats)
retain the original counterexamples with the new error outcomes, schema-error
precedence, consumed versus real marker protection, attached literal data,
help/usage ordering and completion dispatch/protocol protection. The combined
consumed-marker cases run both with and without passthrough. Field and equals
integration tests use the same policy. The README lifecycle and global runtime
matrix describe the restriction separately from the unresolved boundary policy.

## Backward compatibility and dependencies

Mixed detected help/usage tokens now cause errors instead of output and exit 0.
Tokens protected by the existing raw marker or embedded in attachments/pairs
retain their existing parser meaning; changing those boundaries could turn
errors into values or tail capture, or the reverse, and needs its own decision.
[16](16-passthrough-boundary-contract.md) owns parser capture policy;
[17](17-completion-boundary-replay.md) owns completion replay after parsing
boundaries; [22](22-schema-identity-validation.md) owns reserved-name validation.
The standalone restriction does not settle those independent policies.
