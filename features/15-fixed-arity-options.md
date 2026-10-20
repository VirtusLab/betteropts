# Feature: Fixed-Arity Option Fields

## Status

Implemented.
The [global compatibility matrices](../README.md#compatibility-matrices) define how fields compose with the existing declaration and runtime dimensions.

## Problem

A command accepting a question label, verdict and passage needs those fields separately in its business logic.
A quoted `SPEC` leaves the command splitting one string to recover them.
Separate argv values provide boundaries without an embedded grammar or delimiter escaping.

## Declaration and output

```bash
option question -q --question multi fields=label,value,passage \
    value.type=choice value.choices=high,medium,low \
    help="Record a question verdict"
```

Invoking `--question Q-order high '§4.2, Table 3'` produces:

```bash
question_label=(Q-order)
question_value=(high)
question_passage=('§4.2, Table 3')
```

1. `fields=` fixes logical arity; `multi` independently controls repetition.
   Each complete occurrence appends one element to each field array in order.
   Without `multi`, fields are scalars and the last occurrence wins, matching ordinary options.
   No redundant base/raw variable is populated.
2. `var=` changes the output prefix.
   With `var=verdict`, outputs become `verdict_label`, `verdict_value`, and `verdict_passage`.
3. Omission populates empty arrays with `multi`, empty strings otherwise.
   `required` checks that at least one complete occurrence was provided.
4. Fields default to `string`.
   `<field>.type=` uses existing validators and completion; `<field>.choices=` supplies a choice field's candidates.
   Scalar records validate only their final retained occurrence; multi records validate every retained field in every occurrence.
   Validation errors name both the option and uppercased field.
5. The declaration is still one `option` call, preserving the minimal public API.
   Each subsystem obtains field schema through `_bo_meta_get` and `_bo_meta_has` in [betteropts.sh](../betteropts.sh).

## Schema rules

1. `fields=` is option-only and must contain a nonempty comma-separated list of distinct shell identifiers (`[a-zA-Z_][a-zA-Z0-9_]*`).
   A one-field record is valid.
   Explicit `fields=` keeps extra barewords invalid under [strict keyword validation](08-strict-schema-keywords.md#behavior).
2. The variable prefix must be a shell identifier outside `_bo`/`_bo_*`.
   Generated variables must not collide with any other declared output, including another field under a different prefix.
   The unused base prefix is not an output.
   These field-specific rules do not settle the broader ordinary [schema identity policy](22-schema-identity-validation.md#intended-outcome-and-open-decisions).
3. Only `type` and `choices` are supported field attributes, and the named field must occur in the final `fields=` list.
   Attributes can precede `fields=` and repeated recognized attributes use their final value.
   Unknown fields and attributes remain errors, including an attribute orphaned by a later `fields=` replacement.
   A choice field requires nonempty choices; choices on another type are rejected.
   These requirements make field choice validation and completion effective without adopting a policy for the accepted but ineffective ordinary cases in [declaration policy](19-inert-declaration-policy.md#intended-outcome-and-open-decisions).
4. Ordinary metavar, `type=`, `choices=`, `default=` and `implicit=` cannot be combined with `fields=`, even when empty.
   Per-field metavar/default/implicit declarations are unsupported.
   Rejecting those combinations avoids implicit record serialization and partial-record defaults.

## Parsing boundaries

The following separate-argument format is the default.
[Equals field syntax](25-equals-field-syntax.md) optionally selects a single-token
input format for exactly two fields, reusing the logical fields and outputs below.

Supported default forms:

```text
--question LABEL VALUE PASSAGE
-q LABEL VALUE PASSAGE
--question=LABEL VALUE PASSAGE
```

The attached long form supplies the first field only.
Every remaining field consumes exactly one argv token, preserving whitespace, quotes, backslashes, empty strings, newlines and shell metacharacters without splitting or evaluation.
Short attachment and bundling remain unsupported.

Value slots consume tokens verbatim, including hyphen-leading tokens, declared option names and literal `--`, matching ordinary scalar option consumption.
Outside a value slot, `--` retains its ordinary positional/passthrough meaning.
After a full record, option/positional recognition resumes; too few remaining tokens reports `Missing value` for the option.
A flag-shaped token in a value slot is a field value rather than evidence of a missing field.
The parser's bare-token and earlier-slot passthrough behavior remains subject to [passthrough boundary policy](16-passthrough-boundary-contract.md#intended-outcome-and-open-decisions).

Public built-ins retain raw detection: [betteropts.sh](../betteropts.sh), `betteropts_parse`, scans for help/usage before its first literal `--`.
A detected `--help`, `-h` or `--usage` succeeds only as the sole argv token.
A built-in in a field slot therefore causes an explanatory stderr error and exit 1 before business logic instead of the previous successful help/usage exit.
A literal `--` ends that prescan even when record parsing consumes it as a field, after which later ordinary options may still parse.
An attached first field `--question=--` is not a raw marker and does not stop the prescan.
The [standalone restriction](23-builtin-prescan-policy.md#implemented-standalone-restriction) prevents skipped writes from looking successful.
The broader [built-in boundary policy](23-builtin-prescan-policy.md#intended-outcome-and-open-decisions) remains unresolved.

## Help, usage, and completion

1. Uppercased field names provide metavars.
   Usage shows the complete occurrence, such as `[--question LABEL VALUE PASSAGE]...`, or `--question LABEL VALUE PASSAGE [--question LABEL VALUE PASSAGE]...` when required and repeatable.
2. Detailed help retains required/repeatable annotations and appends field-qualified choice annotations in field order, such as `VALUE choices: high, medium, low`.
3. Completion replays the same arity, including attached first fields, short options, flag-shaped fields and `--` inside a record.
   It selects the next field's own type/choices and resumes normal completion after a complete occurrence.
   Repetition does not filter previously used choices.
4. Correct replay requires classifying an attached token before counting its remaining field slots and distinguishing a consumed `--` from a real boundary.
   The same replay rules apply to ordinary options: real markers stop option-name suggestions without occupying positional slots, and unknown attached options or invalid attached flags start passthrough capture.
   [Completion boundary replay](17-completion-boundary-replay.md#implemented-replay-rules) records these rules and the remaining passthrough-policy dependency.
5. Without `syntax=equals`, a current `--option=<partial>` word remains unsupported for ordinary and record options under [attached-value completion](18-attached-value-completion.md#intended-outcome-and-open-decisions).
   A completed attached first field correctly advances completion to later fields.

## Compatibility and scope

Ordinary scalar, multi, default and implicit option parsing is preserved.
Completion candidates change where the uniform replay rules now honor real markers and attached passthrough boundaries.
Fields share retained-scalar versus every-multi validation semantics with ordinary options; [retained scalar validation](21-retained-scalar-validation-contract.md#intended-outcome-and-acceptance) owns the separate ordinary documentation task.
Empty supplied fields are type-checked, while the scalar positional empty-value policy remains with [empty positional presence](20-empty-positional-presence.md#intended-outcome-and-open-decisions).
Label uniqueness, topic membership, passage reference policies and verdict aggregation remain consumer business logic.
The original fields increment adds no consumer changes, default validation, current-word attachment completion or new public declaration functions.
[Equals field syntax](25-equals-field-syntax.md) adds bounded current-word completion for its selected format.
