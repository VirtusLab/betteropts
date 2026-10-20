# Feature: Define and Validate CLI Schema Identities

## Status

Partially implemented.
Metadata key isolation is implemented; schema corrections and unresolved policies remain below.
Concrete schema/integrity corrections are separate from unresolved identity and output-state policies.
No blanket naming, collision or spelling-shape policy is implied by current acceptance.

## Concrete schema and integrity corrections

### Required declaration names

The README `flag`, `option` and `argument` signatures require a name.
Their wrappers and `_bo_declare` in [betteropts.sh](../betteropts.sh) do not guard missing or explicitly empty names before accessing schema storage.
Missing names can produce raw nounset errors; an explicitly empty logical ID can pass finalization and public help/completion with `var=result`, then fail parsing on an empty associative key.
Without errexit, invalid-name paths can print Bash errors yet return to business logic successfully.

Reject zero-argument calls and explicitly empty logical names with library-owned declaration diagnostics before builtins or parsing.
Preserve variable-length valid modifier tails and distinguish a missing name from a present empty attribute value.
Do not require every nonempty logical ID to match output-variable syntax: hyphenated or space-containing IDs with a valid `var=` override currently work, and their permitted alphabet remains a separate policy.

### Ordinary output identifiers

[00, Variable Population](00-initial.MD#variable-population), [10](10-flag-var-override.md#proposed-api) and README `Overriding the populated variable name` promise shell variables.
Effective ordinary outputs such as `var=`, `var=bad-name` and `var=9bad` currently pass `_bo_finalize_schema`, including on flags and arguments.
Public help/completion can succeed, while normal population prints Bash identifier errors.
Without errexit, `option item --item var=bad-name; betteropts_parse --item value` can still return to business logic.

Reject effective ordinary output targets that are not valid Bash variable identifiers, whether derived from the logical name or an explicit override.
Validate before builtins and do not rely on caller shell flags to terminate a broken declaration.
Keep logical IDs and output identifiers separate.
`var=result[0]` creates array-shaped state for an ordinary scalar and fails multi population as `result[0][0]`; recommend rejecting such undocumented target expressions rather than silently defining an expression-target API.
Broader preexisting-variable and private-output policies remain open below.
Record prefixes already have the stricter explicit identifier/private-namespace rules in [15, Schema rules](15-fixed-arity-options.md#schema-rules).
Their trailing-newline validation bypass belongs to [19, Lossless metadata retrieval](19-inert-declaration-policy.md#lossless-metadata-retrieval), rather than a second prefix-normalization fix here.

### Metadata key isolation

Implemented.
Distinct logical IDs and metadata attributes remain independent under [DESIGN.MD, CLI Schema](../DESIGN.MD#cli-schema) and [Metadata Encapsulation](../DESIGN.MD#metadata-encapsulation).
The metadata accessors escape percent signs and dots in each component before joining them with a dot, keeping their boundary unambiguous even when a logical ID contains dots or resembles the encoding itself.
This encoding does not depend on locale-sensitive character counts, so changing locale cannot hide a non-ASCII ID's metadata.
Consumers access metadata only through the shared API; the public declaration API and permitted logical-name alphabet are unchanged.

Previously, an ordinary `item.value` type and record `item` field `value.type` shared one physical key.
Declaring either could silently change the other's validator, with the winner depending on registration order.
They now retain independent type, choice and presentation metadata, without duplicate-name/output rules or a blanket logical-name character ban.
`_bo_meta_has` distinguishes missing keys from present empty values independently for both declarations.

[test/unit/metadata.bats](../test/unit/metadata.bats) covers both write/registration orders, dotted logical IDs, present-empty existence semantics, literal accessor values, integer/string validation separation, and independent choices in parsing, help and completion.
The global matrix's identity assumptions and field context C8 include metadata independence rather than relying on simple IDs to avoid storage collisions.
[19, Lossless metadata retrieval](19-inert-declaration-policy.md#lossless-metadata-retrieval) separately owns exact value preservation through accessor consumers and record-prefix validation.

### Effective builtin spelling reservations

[DESIGN.MD, Built-in Commands](../DESIGN.MD#built-in-commands) reserves `-h`, `--help`, `--usage` and `--__complete`; the hidden completion interface must not appear in help.
Custom flag/option aliases using these spellings currently pass finalization.
A custom `--__complete` also appears in detailed help and synopsis, contrary to the hidden-interface invariant and [14](14-expanded-usage-synopsis.md#behavior).

Reject effective custom aliases colliding with those reserved spellings before any builtin runs.
Validate final effective short/long aliases, preserving the existing last-spelling-wins rule: `flag item --help --item` leaves `--item` as its alias.
Rejecting overwritten earlier spellings would impose a broader raw-token policy.
Reserve CLI spellings, not logical names or literal argv data; a logical name `--help` with safe `--custom var=result` is a different case, as is a literal `--help` operand after a real marker.

Builtin precedence does not make every conflicting alias universally unreachable.
A custom `--__complete` can parse later in argv, and `--help` can parse after raw prescan stops at a marker consumed as another option's value.
The defect is the reservation/help invariant, not a claim of uniform dispatch across all argv contexts.
C27 in [test/integration/compatibility.bats](../test/integration/compatibility.bats) characterizes current permissiveness and precedence; update it with reservation diagnostics and effective-alias controls when implementing this correction.
[23](23-builtin-prescan-policy.md#intended-outcome-and-open-decisions) separately owns raw-prescan and consumption policy.

### Unreachable long spellings

A literal declared long spelling containing `=` is unreachable under [00, Parsing Rules](00-initial.MD#parsing-rules) and `_bo_parse` / `_bo_find_by_long` in [betteropts.sh](../betteropts.sh).
For both `flag item --bad=name` and `option item --bad=name`, invoking that spelling instead looks up `--bad` and fails.
Reject effective long spellings containing `=` as unsupported names, without choosing a broader alias character alphabet.
Preserve ordinary long attachment syntax, where `=` separates a valid declared name from a supplied value.
Marker spelling `--` is a separate policy case below, not universally unreachable across declaration kinds.

## Intended outcome and open decisions

### Logical names, redeclarations and uniqueness

Define the permitted nonempty logical-name alphabet independently of output-variable identifiers and metadata storage encoding.
Logical `_bo_*` names with safe output overrides do not themselves overwrite private shell variables.
Do not generalize record-prefix restrictions into a global logical-name ban.

Repeated declaration calls currently overwrite some common metadata while retaining other attributes and adding duplicate kind-list entries.
Same-name flags can erase an earlier spelling and duplicate final help entries; cross-kind redeclarations can reach inconsistent raw storage; repeated same-name arguments can report a misleading repeated-cardinality error.
Recommend rejecting duplicate logical IDs across kinds unless an explicit replacement/update API is chosen, rather than supporting implicit partial merging.
This is a proposed policy, not a documented redeclaration contract.
The matrix's r1 final-token rule applies within one declaration and must remain distinct.

Define separate uniqueness rules for aliases and ordinary outputs.
C22 in [test/unit/compatibility.bats](../test/unit/compatibility.bats) describes duplicate alias lookup choosing the first matching declaration and a later unprovided flag overwriting a shared output with false.
A cross-kind alias collision can make a later required option impossible to satisfy.
Recommend rejecting conflicting aliases unless a deliberate shared-alias contract is chosen.

Shared ordinary outputs may be intentional, as [04's motivating cases](04-exclusive-flag-groups.md#problem) illustrate; do not infer every collision is a typo.
`_bo_populate` writes flags, then options, then arguments independently of argv order, so an option can overwrite a flag's shared result.
If sharing remains allowed, define that population contract explicitly.
Preserve [15's generated-output collision rejection](15-fixed-arity-options.md#schema-rules), including record-to-ordinary and record-to-record collisions.
A record's unused base prefix is not an output and may name a separate ordinary output.

### Missing and unconventional spellings

Resolve README flag prose requiring a short/long form versus its signature permitting both omitted.
A no-spelling flag currently always populates false; rejecting that unreachable declaration is recommended, but a general minimum-alias policy remains to be defined.
Do not blanket-reject options without spellings: [00, Supported Types, Defaults and Required Options](00-initial.MD) includes such examples, and `option item default=fallback` usefully populates its fallback.
Define required/no-spelling behavior separately; currently it cannot be satisfied and reports a blank option label.

Literal `-vf`, `-long` and `-x=value` can currently be exact short spellings for flags/options; this does not implement bundling or short-value attachment.
For an option, the exact `-x=value` spelling still consumes a following value.
Long `'--has space'` and `---` spellings are also invocable as exact tokens.
Choose spelling-shape restrictions deliberately rather than claiming these are proven unusable.
Preserve no-bundling semantics for conventional spellings.

A flag declared with spelling `--` is unusable through either a bare marker or attachment.
An ordinary option with that spelling can parse `--=value`, and a record option can parse `--=one two`; bare `--` remains a parsing boundary.
A uniform marker-alias prohibition would need a separator/reservation decision, not an assertion that every such alias is unreachable.

### Private outputs and preexisting variable attributes

Ordinary `var=_bo_summary` can overwrite private metadata, while record prefixes in `_bo`/`_bo_*` are already prohibited.
Define private-output protection consistently with library state; this does not itself ban safe logical IDs in that namespace.

Define treatment of preexisting scalars, arrays, readonly and exported outputs, including generated field variables.
Ordinary and record scalar population can preserve an existing array's shape/stale elements; scalar-to-multi population creates an indexed array.
Readonly targets can fail later through Bash errors, and an already-exported ordinary output remains exported.
Reconcile the `var=` × output row in [README, Runtime, presentation and completion interactions](../README.md#runtime-presentation-and-completion-interactions) saying no export is added with [00, Variable Population](00-initial.MD#variable-population) saying variables are never exported.
Choose whether to preserve attributes, reset them or reject unsupported states, with a deliberate public failure contract.
Static identifier rejection alone does not settle dynamic target-state policy or fatal population-error handling.

### Command text API shape

README `summary "text"` and `description "text"`, and [00's corresponding API sections](00-initial.MD#summary), describe single-text calls.
The current functions read `$1` directly, giving caller-mode-dependent behavior when text is missing and silently ignoring extra arguments.
Recommend an exact-one-text guard preserving explicit empty string, with library-owned diagnostics for missing or extra text.
This clarifies the signatures; neither [08](08-strict-schema-keywords.md#behavior) nor a separate explicit maximum-arity rule already settles these two command-text calls.
Do not impose an arbitrary maximum on flag/option/argument modifier tails.

## Acceptance and test work

Map changes into the existing matrix's identity assumptions, `var=`/spelling applicability, r1, C8/C9 field contexts, C22 and public builtin/output rows.
Keep the same matrix and extend missing identity/value/entrypoint contexts rather than maintaining a second inventory.
Cover same/cross-kind duplicate IDs, aliases and outputs; missing/malformed spellings; invalid effective output identifiers; builtin aliases; and metadata separation in both declaration orders.
Pin diagnostics for concrete rejections and behaviors for deliberately accepted cases.
Check normal parsing, public help, usage and hidden completion, including caller modes with and without errexit/nounset.
Static schema errors must terminate with library-owned errors before builtins, not print Bash errors and return to business logic.

Retain controls for valid var overrides without alias/help renaming, safe output names matching library loop-local names, effective final aliases and independent logical/output identifiers.
Preserve explicit empty ordinary values, literal builtin-looking data, record generated-output checks and supported default-only forms unless their separate policy is expressly changed.
Add command-text missing/empty/extra-argument cases if that clarification is adopted.
Test preexisting target attributes for each chosen policy instead of promising uniform behavior from identifier checks alone.

## Backward compatibility and dependencies

Stricter identity checks can reject working declarations; identify affected fixtures and consumers before adopting unresolved-policy rejections.
The concrete metadata-isolation fix must preserve independent valid declarations without narrowing their identity alphabet.
Do not treat all current acceptance as normative permission or every shared identity as accidental.
[04](04-exclusive-flag-groups.md#proposed-api) owns mutual exclusion, not identity or shared-output semantics.
[08](08-strict-schema-keywords.md#behavior) owns implemented keyword checks.
[19](19-inert-declaration-policy.md#concrete-contract-corrections) owns unsupported attributes, positional-spelling clarification and lossless metadata values.
Key-isolation and lossless-value work may share accessor changes while preserving separate acceptance criteria and Bash 4.2 support.
[23](23-builtin-prescan-policy.md#intended-outcome-and-open-decisions) owns dispatch/consumption policy; reserved aliases and static schema-error precedence can be corrected without changing raw prescan.
No resolved completion-boundary work is reopened by these identity tasks.
