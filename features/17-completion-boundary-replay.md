# Feature: Make Completion Replay Respect Parsing Boundaries

## Status

Proposed.
Not yet implemented.
Completion must follow parser token classification without selecting a broader passthrough policy.

## Problem

`_bo_complete` and `_bo_parse` in [`betteropts.sh`](../betteropts.sh) disagree about token boundaries.
Without passthrough, replay counts a real `--` as a positional word and continues suggesting options after parsing has stopped recognizing them.
Replay also skips earlier `--name=value` tokens before lookup, so unknown attachments and attached flags such as `--verbose=true` do not establish the passthrough boundary that parsing establishes.
Flags do not accept attached values even when their base spelling is declared.

With two typed positional slots, counting the real marker as a word can select the second slot's candidates instead of the first slot's candidates.
These disagreements require replay corrections, not changes to the parser's existing marker or attached-token rules.

## Bare-minus replay

A bare `-` is positional to `_bo_parse`, but `_bo_complete` treats it as an unknown dash token when passthrough exists and stops offering candidates.
For an option `--item` followed by a passthrough argument, parsing `- --item 1` still recognizes the option and keeps `-` positional.
Completion of the prefix `- --it` must therefore continue to offer `--item` before a genuine boundary.

Correct replay to advance the positional count for a bare `-` instead of starting passthrough capture.
This correction is independent of the undecided broader bare-token and earlier-slot policies in [passthrough boundary contract](16-passthrough-boundary-contract.md#intended-outcome-and-open-decisions), because it follows the parser's existing classification of this exact token.
A `-` consumed by a mandatory value slot remains literal value data and must not advance a positional slot.

## Intended outcome and acceptance

1. Classify mandatory value slots before interpreting option names or markers.
   A mandatory option value equal to `--` or `-` consumes its value slot and does not establish a boundary or occupy a positional slot.
   Bare implicit options consume no following word; each multi occurrence keeps its declared value consumption.
2. After a real `--`, complete the appropriate positional type without occupying a slot for the marker or suggesting declared options.
   A passthrough boundary ends tail candidates.
3. Unknown long attachments and attached flag values must establish the same passthrough boundary as unknown unattached options.
   Known option attachments still fill their option value, and all such tokens remain literal data when consumed by a mandatory value slot.
4. Add dedicated bare-minus regressions with and without passthrough, including multiple typed positional slots and known-option completion after `-`.
   Assert that `-` advances one positional slot, while a consumed value of `-` advances none.
   Keep unknown `-x` and `--unknown` as genuine capture triggers when undeclared, and offer no option candidates after a real `--` or unknown-option boundary.
5. Cover ordinary options independently of any multi-field option feature.
   When such a feature is available, apply the same boundary regressions to mixed ordinary and multi-field declarations, including `-` and `--` consumed at each mandatory field slot.
   Neither option kind may receive a separate replay classifier that disagrees with parsing.
6. Keep the `C13` unknown-attached and `C14` real-marker cases in [`test/unit/compatibility.bats`](../test/unit/compatibility.bats), changing their expected candidates only with the corresponding correction.
   Assert positional slot selection as well as option-name suppression.
   Cover required/optional/variadic slots, earlier scalar slots before passthrough, short/long values, known/unknown attachments, implicit and multi options.
7. Keep option-name and value completion sourced from the schema without new public API or duplicated metadata.
   Sharing replay state with parsing is an implementation choice.

## Backward compatibility and dependencies

Corrected candidates may disappear, remain available after `-`, or change positional slots; the parser need not change for these corrections.
The confirmed marker, attachment and bare-minus corrections can proceed without a ruling on [broader passthrough policy](16-passthrough-boundary-contract.md#intended-outcome-and-open-decisions), then be rechecked if that policy changes.
They do not make ordinary bare words into capture triggers or reserve triggering tokens for the tail.

Current-word attached values remain a separate capability in [attached-value completion](18-attached-value-completion.md#intended-outcome-and-open-decisions).
[Built-in prescan](23-builtin-prescan-policy.md#intended-outcome-and-open-decisions) owns raw command detection, and [Fish completion](12-fish-completion.md#proposed-api) supplies another adapter rather than repairing this engine.
