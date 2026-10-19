# Feature: Make Completion Replay Respect Parsing Boundaries

## Status

Proposed. Not yet implemented. These are observed replay/parser
disagreements, not newly supported completion behavior.

## Problem and observed baseline

At `05f8cb5`, `_bo_complete` replays argv independently of `_bo_parse` in
[`betteropts.sh`](../betteropts.sh). Two boundaries diverge:

1. Without passthrough, a literal `--` is counted as a positional word;
   completion can advance to the wrong positional slot and still suggest
   options after parsing has stopped recognizing them.
2. Every earlier `--name=value` is skipped before lookup. An unknown
   attached option therefore fails to establish the passthrough boundary
   that the actual parser establishes.

C13/C14 in [`compatibility.bats`](../test/unit/compatibility.bats) preserve
the evidence. In fresh schemas, these synthetic trials illustrate it:

```bash
option item --item N
argument extra passthrough
_bo_complete -- --unknown=value --it  # emits --item
# _bo_parse captures --unknown=value and all following tokens instead.
```

```bash
option item --item N
argument extra variadic
_bo_complete -- -- --it              # emits --item
# The real -- ends option recognition.
```

The independent baseline trial with two choice positionals also returned
the second slot's choices for `_bo_complete -- -- ""`; that specific slot
error is not yet an automated assertion.

## Intended outcome and acceptance

1. Classify replayed markers and known/unknown attached options consistently
   with parsing. A mandatory option value equal to `--` is a value, not a
   boundary; bare implicit options consume no following word.
2. After an ordinary marker, complete the appropriate positional type
   without treating the marker as an occupied scalar slot or suggesting
   declared options. After a passthrough boundary, offer no tail candidates.
3. Add the missing positional-slot assertion; convert C13/C14 into intended
   behavior assertions while retaining reproductions of both original cases.
   Cover required/optional/variadic slots, earlier scalar slots before
   passthrough, short/long values, known/unknown `=`, implicit and multi.
4. Keep option-name and value completion sourced from the schema. Whether
   replay state can be shared with parsing is an implementation question;
   no duplicated schema metadata or new public API is required.

## Backward compatibility and dependencies

Corrected candidates may disappear or change slots; argv parsing need not
change for the confirmed cases. The bare-token/earlier-slot policy in
[16](16-passthrough-boundary-contract.md) remains open. The confirmed
explicit-marker and unknown-attached cases can be addressed independently,
then rechecked if that policy changes. Current-word attached values are a
separate gap in [18](18-attached-value-completion.md). Built-in prescan is
separate in [23](23-builtin-prescan-policy.md); proposed
[12](12-fish-completion.md) supplies another adapter and does not repair replay.
