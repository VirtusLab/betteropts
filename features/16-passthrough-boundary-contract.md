# Feature: Reconcile the Passthrough Boundary Contract

## Status

Proposed. Not yet implemented. The boundary and earlier-slot policies below
remain undecided; this record does not authorize a runtime change.

## Problem and observed baseline

At `05f8cb5`, [03](03-passthrough-arguments.md) and README's argument prose
say the first unrecognized token starts passthrough capture. Actual
`_bo_parse` starts capture on an unknown dash-shaped token or literal `--`,
not an ordinary positional word. `_bo_assign_positionals` subsequently
assigns the shared positional stream to scalar slots before the tail.

These synthetic examples are characterized by C12 and C28 in
[`compatibility.bats`](../test/unit/compatibility.bats):

```bash
option item --item N
argument extra passthrough
betteropts_parse operand --item 1 --unknown --item 2
# item=1; extra=(operand --unknown --item 2)
```

In a separate fresh schema:

```bash
argument first required
argument extra passthrough
betteropts_parse -- operand
# first=--; extra=(operand)
```

Thus a triggering delimiter is not necessarily `extra[0]`. An earlier
optional argument can likewise claim the first unknown flag; the existing
[`population.bats`](../test/unit/population.bats) test explicitly checks
that case. This contradicts an unconditional tail-first interpretation,
but does not establish which replacement policy callers need.

## Intended outcome and open decisions

1. Rule on whether bare positionals start capture, or retain the actual
   unknown-option/explicit-marker boundary and correct the contract.
2. Rule on whether earlier scalar slots may receive retained markers and
   unknown flags, or whether capture reserves those tokens for the tail.
3. Publish one precise contract across README, 03, parser and completion.
   Preserve declared option-value consumption and the existing placement
   rule `required* optional* (variadic | passthrough)?` unless separately
   changed by an explicit decision.

## Acceptance and test work

1. Compare the chosen policy with C12/C28 and change characterization
   expectations only where an approved behavior change requires it.
2. Cover known options before/after bare words, unknown short/long/attached
   options, mandatory values, implicit options, repeated options, `--`, and
   earlier required/optional slots. Assert exact token preservation.
3. Preserve the dedicated bare `-` regressions from
   [17](17-completion-boundary-replay.md#intended-outcome-and-acceptance): it is currently positional,
   unlike a dash followed by more characters (`_bo_parse`, independently
   trialled in the baseline audit). Include negative positionals before
   and after a real boundary; do not treat that syntax as a new defect.

## Backward compatibility and dependencies

Changing the boundary can redirect existing known options into the tail;
changing earlier-slot assignment can change requiredness and output.
Document those effects before implementation. [17](17-completion-boundary-replay.md)
owns completion agreement; [23](23-builtin-prescan-policy.md) owns whether
raw help/usage detection respects any capture boundary. Their existing
independent cases need not wait for this decision, but final contracts
must agree. Passthrough typing is owned by [19](19-inert-declaration-policy.md).
