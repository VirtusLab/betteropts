# Feature: Make Completion Replay Respect Parsing Boundaries

## Status

Implemented for explicit markers, attached tokens and bare-minus replay for ordinary and record options.
Broader bare-token and earlier-slot passthrough policy remains unresolved under [passthrough boundary contract](16-passthrough-boundary-contract.md#intended-outcome-and-open-decisions).

## Implemented replay rules

Completion and parsing classify mandatory value slots before interpreting markers or option spellings.
This allows each record field to consume one argv token while keeping a genuine parsing boundary distinct from a literal field value.
The replay uses schema metadata without a new public API.

1. A mandatory ordinary value or record field equal to `--` consumes its value slot and does not end option recognition.
   Bare implicit options consume no following word; each multi occurrence retains its declared arity.
2. A real `--` ends option-name completion and does not occupy a positional slot for ordinary arguments/variadic tails.
   Completion selects the next positional type; a real passthrough marker ends candidates.
3. An earlier known long attachment fills the ordinary value or first record field.
   Remaining record fields consume subsequent words before another option can be recognized.
4. Unknown attached options establish the same passthrough boundary as unknown unattached options.
   An attached flag such as `--verbose=true` is also unrecognized because flags accept no attached value, even when the base spelling names a declared flag.
   Such tokens remain literal data when consumed by a mandatory value or field slot.

These rules use one classifier rather than preserving different boundary behavior for records and ordinary options.
Completion candidates after real markers or unknown attachments therefore differ from the earlier behavior that continued suggesting declared options.

## Bare-minus replay

A bare `-` is positional to both `_bo_parse` and `_bo_complete`, including when passthrough exists.
For an option `--item` followed by a passthrough argument, parsing `- --item 1` still recognizes the option and keeps `-` positional.
Completion of the prefix `- --it` therefore continues to offer `--item` before a genuine boundary.

Replay advances the positional count for a bare `-` instead of starting passthrough capture.
This correction is independent of the undecided broader bare-token and earlier-slot policies in [passthrough boundary contract](16-passthrough-boundary-contract.md#intended-outcome-and-open-decisions), because it follows the parser's existing classification of this exact token.
A `-` consumed by a mandatory value slot remains literal value data and must not advance a positional slot.

## Intended outcome and acceptance

The bare-minus correction preserves the implemented replay rules above.

1. Add dedicated bare-minus regressions with and without passthrough, including multiple typed positional slots and known-option completion after `-`.
   Assert that `-` advances one positional slot, while a consumed value of `-` advances none.
   Keep unknown `-x` and `--unknown` as genuine capture triggers when undeclared, and offer no option candidates after a real `--` or unknown-option boundary.
2. Cover ordinary options independently and mixed ordinary/record declarations under the same replay rules.
   Include `-` and `--` consumed at each mandatory option value or record field slot.
   Neither option kind may receive a separate replay classifier that disagrees with parsing.
3. Preserve the implemented explicit-marker, unknown-attachment and attached-flag corrections, including the `C13` and `C14` cases in [`test/unit/compatibility.bats`](../test/unit/compatibility.bats).
   Assert positional slot selection as well as option-name suppression.
   Cover required/optional/variadic slots, earlier scalar slots before passthrough, short/long values, known/unknown attachments, implicit and multi options.
4. Keep option-name and value completion sourced from the schema without new public API or duplicated metadata.
   Sharing replay state with parsing is an implementation choice.

Dedicated [boundary replay regressions](../test/unit/completion_boundary_replay.bats) cover positional selection, mandatory value/field slots, implicit and repeated options, and genuine boundaries.
The [completion integration suite](../test/integration/completion.bats) also checks known-option completion after a bare `-` through the command's completion protocol.

## Remaining policy and compatibility

The actual parser currently keeps recognizing known options after bare positional words and assigns the shared positional stream to earlier scalar slots before passthrough.
Whether those policies should change is owned by [passthrough boundary contract](16-passthrough-boundary-contract.md#intended-outcome-and-open-decisions), and replay must follow its eventual decision.
This work does not select a bare-token boundary or reserve triggering tokens for the tail.

A current `--name=partial` word still has no value candidates; [attached-value completion](18-attached-value-completion.md#intended-outcome-and-open-decisions) owns that separate capability and interactive insertion policy.
Raw built-in prescan remains separate under [built-in prescan policy](23-builtin-prescan-policy.md#intended-outcome-and-open-decisions).
[Fish completion](12-fish-completion.md#proposed-api) supplies another adapter rather than replacing these engine rules.
