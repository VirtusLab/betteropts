# Feature: Validate Declaration Attributes and Preserve Metadata Values

## Status

Partially implemented.
Passthrough attribute rejection and lossless metadata retrieval are implemented; other corrections and open policies remain below.
Concrete contract corrections below are separate from the open ordinary-choice and default policies.
Current schema acceptance does not establish that an ignored attribute is supported grammar.

## Concrete contract corrections

### Passthrough declaration attributes

[03, Non-Goals](03-passthrough-arguments.md#non-goals-v1) defines passthrough as raw, untyped text, with no `type=`/`choices=` processing.
Explicit `type=` and `choices=` declarations on passthrough are rejected as unsupported attributes, rather than advertising constraints that are never enforced.
Adding validation of the forwarded tail would change its raw contract.

Before this correction, `_bo_declare` accepted these ordinary argument attributes and `_bo_finalize_schema` only checked that a declared type name was recognized.
The same declaration now fails before parsing:

```bash
argument extra passthrough type=choice choices=one,two
betteropts_parse --not-a-choice
# Passthrough argument 'extra' cannot declare type=.
```

Reject either attribute by presence, including explicit `type=string`, `type=`, `choices=`, repeated attributes and either token order.
Keep omitted type metadata valid; omission and explicitly declaring `type=string` are different schema cases here.
Reject the static declaration before normal parsing, help, usage or hidden completion executes.
The diagnostic must identify the declaration and unsupported attribute.
Help-only suppression would conceal the schema defect.

Implemented regressions cover public normal/help/usage/completion entrypoints under plain, errexit, nounset and combined caller modes in [schema_identity.bats](../test/integration/schema_identity.bats).
The compatibility expectations retain valid untyped passthrough controls.

This corrects the existing applicability T/C argument entries, pair cells P×T/P×C, C2 and the type table's passthrough column in the [global matrix](../README.md#compatibility-matrices).
Its omitted/string row distinguishes omission from an explicit type attribute.
C01–C04's cardinality-sensitive expectations and the formerly permissive C09/C10/C19 cases and C36 record/passthrough control were updated in [test/unit/compatibility.bats](../test/unit/compatibility.bats), retaining valid untyped passthrough controls.
The record/passthrough and completion-replay fixtures omit type/choices metadata on their raw passthrough tails; their boundary expectations are preserved.
No [passthrough boundary](16-passthrough-boundary-contract.md#intended-outcome-and-open-decisions) policy decision is needed for this schema rejection.

### Positional spelling correction

The README `argument` signature lists positional cardinality and attributes without switch spellings; flag/option signatures explicitly include them.
[00, Positional Arguments](00-initial.MD#positional-arguments) defines operands by position, while its Flags, Options and Parsing Rules define switch lookup.
Currently `_bo_declare` stores `-x` and `--name` on arguments, but those tokens provide no aliases, help labels or completion behavior.
For example:

```bash
argument item optional --item
betteropts_parse --item value
# Unknown option: --item
```

The recommended correction is to reject short/long spelling tokens on every argument cardinality, consistent with that positional grammar and [08's strict-grammar rationale](08-strict-schema-keywords.md#problem).
Clarify 08's ambiguous “argument additionally supports” wording when implementing this correction; it does not explicitly define whether spellings are inherited from the preceding flag sentence.
Permitting inert positional spellings instead would require an explicit grammar exception and reason; current C11 acceptance alone is not that decision.
This recommendation is distinct from the settled raw passthrough attribute restriction.

Cover either/both spellings, all four cardinalities, repeated spellings and placement among valid positional attributes.
Update C11, applicability s/l, pair cells O/V/P×s/l and kind-specific C3 contexts together with the chosen clarification.
Preserve final-spelling-wins on flag/option declarations and literal dash-looking argv data in value slots or after a real delimiter.
[22](22-schema-identity-validation.md#concrete-schema-and-integrity-corrections) owns the validity and reservations of actual flag/option spellings.

### Lossless metadata retrieval

Implemented.
Metadata retains its declared bytes before structural validation and literal use.
[08](08-strict-schema-keywords.md#behavior) requires exact recognized type values, [15, Schema rules](15-fixed-arity-options.md#schema-rules) requires exact field-list/prefix identifiers, and [13](13-implicit-value-options.md#proposed-api) makes an implicit literal equivalent to that explicit value.
Defaults remain trusted values; trusting them does not authorize changing their text.

The shared `_bo_meta_get name attribute destination` accessor in [betteropts.sh](../betteropts.sh) writes into a caller variable rather than returning text through command substitution, which removes trailing newlines.
`_bo_meta_has` preserves the distinction between missing metadata and present empty content.
All schema, parser, validator, default, population, help and completion consumers use these accessors, preserving the single metadata API required by [DESIGN.MD, Metadata Encapsulation](../DESIGN.MD#metadata-encapsulation).
Generated text and logical-ID lookups use shared lossless capture so later label/metavar/annotation composition cannot strip the same bytes again.
The runtime remains a dependency-free single file using Bash 4.2-compatible primitives.

Structural values are validated in full: `type=$'integer\n'`, `value.type=$'integer\n'`, `fields=$'left,right\n'` and record `var=$'result\n'` are rejected rather than normalized.
Recognized replacements still use their final values, so an earlier malformed value replaced by a valid final value is accepted.
Defaults, implicit literals, help prose and metavars retain internal and trailing newlines.
Variadic defaults split only on commas; a newline within a member remains part of that member.
For `type=integer implicit=$'1\n'`, a retained bare occurrence fails just like the corresponding explicit attached value; unused implicit values remain unchecked, scalar replacement still applies, and every multi occurrence is checked.
No trimming, newline ban for literals or default validation is introduced.

Exact-byte regressions in [test/unit/metadata.bats](../test/unit/metadata.bats) cover empty values, zero/one/multiple trailing newlines, internal newlines, caller-local destinations, defaults/implicit equivalence, annotations/metavars/help, logical-ID lookup and public normal/help/usage/completion entrypoints under plain and strict callers.
C38 in [test/unit/compatibility.bats](../test/unit/compatibility.bats) and malformed-field/prefix cases in [test/unit/option_fields.bats](../test/unit/option_fields.bats) include newline-bearing structural values.
The existing matrix's C4/C5 and presentation rows record preservation through consumers.

[22, Metadata key isolation](22-schema-identity-validation.md#metadata-key-isolation) owns ambiguous composite keys, a separate cause with independent regressions.
Record-prefix normalization is owned here and cross-linked from 22 rather than fixed independently at each identity check.
Comma-list member validation/completion, including internal newlines and empty members, remains an open policy below; preserving metadata does not define a new choice-list grammar.

## Intended outcome and open decisions

### Ordinary choices and choice-list grammar

`choices=` without ordinary `type=choice` is accepted but provides no validation, candidates or annotation, as described by C07 and C2.
Ordinary `type=choice` with absent choices or explicit `choices=` is also schema-accepted, but neither list matches a supplied nonempty or explicitly empty option value.
C08 locates the absent-list case; cover absence and explicit-empty metadata separately when defining their policy.

Decide whether ordinary choices on another type are rejected, given an effective meaning or explicitly supported as inert metadata.
Decide whether choice type requires a nonempty list and whether empty string can be a candidate.
The stricter record requirements in [15, Schema rules](15-fixed-arity-options.md#schema-rules) do not settle these ordinary cases.

Define the comma-list member grammar for both ordinary and field choices.
A nonempty attribute such as `,` or `a,,b` is currently accepted for a choice field and can match an empty field, despite empty `choices=` itself being rejected there.
Neither a blanket empty-member ban nor an empty-member guarantee is specified by the existing nonempty-list rule.
A list containing an internal newline is accepted, but `_bo_choice_matches` reads only its first line; for example `$'a\nb,c'` rejects `c` although help advertises it.
Choose coherent literal candidate handling or explicit rejection of unsupported list values; do not silently introduce a newline or empty-member ban.
Keep this choice-list policy distinct from the lossless retrieval correction above.
Coordinate accepted candidate display/completion with [18](18-attached-value-completion.md#intended-outcome-and-open-decisions).

Add cases for absent choices, explicit `choices=`, empty members at each position and newline-bearing lists, each with nonempty and explicitly empty argv inputs.
Keep optional scalar empty-value bypass separate under [20](20-empty-positional-presence.md#intended-outcome-and-open-decisions).

### Required ordinary option defaults

A required ordinary option with `default=` is schema-accepted, but omission fails requiredness before the fallback can apply, as C06/C1 describe.
For example:

```bash
option item --item required default=fallback
betteropts_parse
# Missing required option: --item
```

Decide whether to reject this unreachable default or explicitly support the redundant metadata.
Making defaults satisfy requiredness would be a separate behavior change, not an assumed remedy.
[01](01-argument-defaults.md#schema-validation-rules) already rejects required positional defaults; that does not itself decide the ordinary-option policy.

## Acceptance, compatibility and dependencies

Apply concrete corrections independently of unresolved policies where possible.
Update schema diagnostics, help/completion behavior, the existing README matrix and affected characterization expectations together for each implemented correction or chosen policy.
Check schema finalization and public normal parse/help/usage/completion contexts, with errors independent of caller `set -e`/`set -u` settings.
Do not add a second compatibility inventory or make pairwise acceptance stand in for cardinality, value-content and higher-order contexts.

Preserve legitimate empty metavar fallback, repeated recognized attributes using their final values, unknown-key rejection, field dependencies and scalar-only attribute conflicts.
Defaults remain trusted without type validation.
Unused invalid implicit literals remain unchecked; retained scalar implicit values validate after later scalar replacement, while every multi occurrence validates, as described by [21](21-retained-scalar-validation-contract.md#intended-outcome-and-acceptance).
Keep the `multi` + `default=` exclusion even with `implicit=`.
Rejecting previously accepted declarations is a compatibility break; literal preservation can also change outputs that previously lost text.

This extends [08](08-strict-schema-keywords.md#behavior) without reopening its implemented status.
[22](22-schema-identity-validation.md#acceptance-and-test-work) owns invalid/colliding identities and API call shape; shared metadata/finalization changes must preserve both contracts without conflating their causes.
[23](23-builtin-prescan-policy.md#intended-outcome-and-open-decisions) owns builtin consumption policy, while static schema errors must precede builtins.
Proposed [11](11-git-commitish-resolve-full-sha.md#behavior) contains passthrough/default assumptions that must agree with the raw contract and any selected ordinary typing policy; SHA normalization remains separate.
