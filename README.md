# BetterOpts

[![CI](https://github.com/VirtusLab/betteropts/actions/workflows/ci.yml/badge.svg?branch=master)](https://github.com/VirtusLab/betteropts/actions/workflows/ci.yml?query=branch%3Amaster)

BetterOpts is a pure Bash runtime library for declarative command-line
argument parsing. You declare flags, options, and positional arguments up
front; the library parses `$@`, validates it, applies defaults, populates
shell variables, and generates `--help`/`--usage`/Bash completion — all from
that one declaration.

## Requirements

- Bash 4.2 or newer (associative arrays, `declare -g`, `mapfile`). macOS
  ships Bash 3.2 by default — install a newer one (e.g. `brew install bash`)
  and point your script's shebang at it.
- No other dependencies. `betteropts.sh` is a single file; copy it into your
  project (or add this repo as a submodule) and `source` it.

## Quick start

```bash
#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/betteropts.sh"

summary "Build a project"

description "
Compile a project and write the resulting artifacts.

Supports incremental and parallel builds.
"

flag verbose -v --verbose \
    help="Enable verbose logging"

flag force -f --force \
    help="Overwrite existing output"

option output -o --output PATH \
    required \
    type=directory \
    help="Output directory"

option jobs -j --jobs N \
    default=4 \
    type=integer \
    help="Worker count"

argument source required \
    type=directory \
    help="Source directory"

argument destination optional \
    type=directory \
    help="Destination directory"

betteropts_parse "$@"

echo "$output"
echo "$jobs"
echo "$source"
```

You never touch `$@`, write your own `case`/`getopts` loop, or hand-roll
`--help` — declare the CLI, call `betteropts_parse "$@"`, then write your
business logic against the variables it populates.

## Declaring the CLI

### `summary "text"`

A one-line description, shown by both `--help` and `--usage`.

### `description "text"`

An optional longer description, shown only by `--help`. Written as a
multi-line string with a leading and trailing newline (see the quick-start
example); the leading/trailing blank lines are stripped automatically, any
blank lines in the middle are preserved.

### `flag <name> [-x] [--xxx] [var=name] [help="..."]`

A boolean switch. Give a short form (`-x`), a long form (`--xxx`), or both.
Populates `<name>=true` if the flag was passed (any number of times),
`<name>=false` otherwise.

```bash
flag verbose -v --verbose help="Enable verbose logging"
flag quiet --quiet help="Suppress output"   # long-only is fine
```

### `option <name> [-x] [--xxx] METAVAR [required] [type=T] [choices=a,b,c] [default=D] [implicit=V] [multi] [var=name] [help="..."]`

A flag that takes a value. `METAVAR` (e.g. `PATH`, `N`) is the placeholder
name shown in `--help`/usage. Accepts:

```
-o value
--output value
--output=value
```

`-o=value` and bundled short flags (`-vf`) are intentionally **not**
supported, to keep the parser simple.

```bash
option output -o --output PATH required type=directory help="Output directory"
option jobs -j --jobs N default=4 type=integer help="Worker count"
```

Without `multi`, repeated occurrences overwrite the scalar. Parsing finishes
before validation, so only the final retained value is checked against its
type/choices; an earlier invalid value that was overwritten does not cause
an error.

Add `multi` to make the option repeatable: each occurrence appends its value
to an ordered **bash array** instead of overwriting a scalar.

```bash
option topic -t --topic VALUE multi type=choice choices=fast,slow,auto \
    help="Note topic to show (repeatable)"
```

`--topic fast --topic slow` populates `topic=(fast slow)`. `type=`/`choices=`
validation applies to each value independently. `required` + `multi` means
"at least one occurrence is required" — zero occurrences is a `Missing
required option` error, same as a non-multi required option. Zero
occurrences without `required` populates an empty array, so
`"${#topic[@]}"` is always safe to check regardless of whether the option is
`multi`. `default=` combined with `multi` is a schema error (checked at
startup, same as the other schema rules above) — there's no single sensible
meaning for "the default list" when zero, one, or many values may be
supplied.

Add `implicit=VALUE` to make the option's value optional: a bare occurrence
(no attached value) is treated exactly as if `implicit`'s value had been
typed explicitly. This is the pattern behind `git log --notes[=<ref>]`:

```bash
option notes --notes REF multi implicit=refs/notes/commits \
    help="Show notes from REF"
```

```
git log                              # no notes shown -> notes=()
git log --notes                      # -> notes=(refs/notes/commits)
git log --notes=refs/notes/other     # -> notes=(refs/notes/other)
git log --notes --notes=refs/notes/other   # -> notes=(refs/notes/commits refs/notes/other)
```

Only `--notes=value` (long form with `=`) attaches an explicit value; a
following bare token (`--notes value`) is **not** consumed as `--notes`'s
value — it's left for the next positional/option, matching GNU
`getopt_long`'s `--opt[=arg]` convention. The short form, if declared, is
always bare (`-n` behaves like the bare long form; there's no `-nVALUE` or
`-n value` attachment) — an explicit value always requires `--long=value`.

`implicit=` is orthogonal to `default=` — `default=` still means "value
used when the option is never provided at all", while `implicit=` means
"value used when the option is provided bare". The two can be combined:

```bash
option mode --mode VALUE default=off implicit=on help="Feature mode"

# (not passed at all)   -> mode=off
# --mode                -> mode=on
# --mode=custom         -> mode=custom
```

A bare occurrence's value is recorded through the exact same path an
explicit value would be, so `type=`/`choices=` validation applies to it
after parsing: only the final retained scalar value is checked, while every
`multi` value is checked. The `implicit=` literal is not checked at schema
time; an unused or overwritten scalar implicit value is never checked.
Unlike implicit values retained from an occurrence, `default=` stays
trusted-as-is and is never validated. `implicit=` combined with
`multi` and `default=` together remains a schema error, same as `multi` +
`default=` without `implicit=` — that rule is about "the default list"
having no single sensible meaning for zero-vs-many occurrences, which
`implicit=` doesn't resolve.

### Options with several fields

Declare `fields=` to consume a fixed number of separate arguments per occurrence.
`multi` independently makes the whole occurrence repeatable:

```bash
option question -q --question multi fields=label,value,passage \
    value.type=choice value.choices=high,medium,low \
    help="Record a question verdict"

# --question Q-order high '§4.2, Table 3' -q Q-path low 'Appendix A'
# question_label=(Q-order Q-path)
# question_value=(high low)
# question_passage=('§4.2, Table 3' 'Appendix A')
```

The shell supplies the argument boundaries; betteropts preserves each value verbatim.
Each field populates `<option>_<field>`, and values at the same array index belong to the same occurrence.
`var=verdict` changes that prefix to `verdict_label`, `verdict_value`, and `verdict_passage`.
No base variable (`question` or `verdict`) is populated.
Without `multi`, fields populate scalars and the last occurrence replaces the earlier one.
An omitted option populates empty arrays with `multi`, empty scalars otherwise.
`required` requires at least one complete occurrence.

Field names must be distinct shell identifiers (`[a-zA-Z_][a-zA-Z0-9_]*`), in a nonempty comma-separated list.
One field is allowed.
The output prefix must also be a shell identifier and cannot use the library's `_bo`/`_bo_` namespace.
Generated field variables cannot collide with another declared output.
Each field accepts `<field>.type=` and `<field>.choices=`; types and completion follow the table below, with `string` as the default.
A choice field requires nonempty `choices=`, and `choices=` requires `type=choice`.
Unknown field names or attributes are schema errors.
Field attributes may appear before or after `fields=`.

`fields=` replaces the ordinary option's metavar, `type=`, `choices=`, `default=`, and `implicit=`; combining any of those with `fields=` is a schema error.
Per-field defaults, implicit values, and custom metavars are not supported.
Field names uppercased provide the metavars, so the example renders as `[--question LABEL VALUE PASSAGE]...` in usage and shows `VALUE choices: high, medium, low` in detailed help.

Accepted forms are `--question LABEL VALUE PASSAGE`, `-q LABEL VALUE PASSAGE`, and `--question=LABEL VALUE PASSAGE`.
The attached form provides only the first field.
As with existing single-value options, value slots consume argv tokens verbatim, including negative numbers, option names, and a literal `--`.
After all fields have been consumed, ordinary option and positional parsing resumes.
Too few remaining tokens produces a `Missing value` error; a token that resembles an option still fills the next field slot.
There is no short attachment or bundling.

The built-in prescan still applies: `--help`/`-h`/`--usage` before the first literal `--` must be the sole argv token.
Mixed invocations fail with an explanatory stderr error and exit 1 before business logic, even when the built-in token occupies a field slot.
That first literal `--` ends the prescan even when field parsing later consumes it as a value.
Completion replays complete occurrences and offers the next field's choices or paths.
A literal `--` outside a record ends option-name completion and switches to positionals (or no candidates for a passthrough tail).
Without `syntax=equals`, completing a current word of the form `--question=<partial>` remains unsupported, as for ordinary options; a completed attached first field is understood when completing later fields.

For exactly two fields, add `syntax=equals` to consume one `KEY=VALUE` token
instead of two separate arguments:

```bash
option set -s --set fields=key,value syntax=equals multi
# --set kind=topic -s axis=true --set=kind=test
# set_key=(kind axis kind)
# set_value=(topic true test)
```

This declaration accepts only the equals format. Each occurrence requires a
literal `=` and splits at its first occurrence; further equals signs remain in
the second field. Empty fields use their existing type validation. Keys cannot
contain `=`; there is no escaping grammar, `+=` operation, per-key type selection
or mapping conversion. Field validation, scalar/array outputs, repeated keys,
`var=` and requiredness are unchanged. Help and usage show `KEY=VALUE`.
The only accepted `syntax=` value is `equals`, requiring exactly two declared
fields; omitting the attribute preserves separate-argument syntax.
Completion offers first-field candidates ending in `=`, then second-field
candidates with the first field preserved, including attached long options.
The Bash adapter supports unquoted current pair tokens and safely escapes
inserted candidates; decoding already quoted or escaped current tokens remains
outside this bounded completion contract (see [equals syntax](features/25-equals-field-syntax.md#completion-contract)).

### `argument <name> <required|optional|variadic|passthrough> [type=T] [choices=a,b,c] [default=D] [var=name] [help="..."]`

A positional argument. Exactly one of `required`, `optional`, `variadic`, or
`passthrough` must be given:

- `required` — must be supplied. Cannot declare a `default=` (a required
  argument with a default is a contradiction — checked at startup as a
  schema error, the same way "more than one variadic argument" is).
- `optional` — may be omitted; populates an empty string when it is, or the
  `default=` value if one was declared.
- `variadic` — collects every remaining positional token into a **bash
  array**, zero or more. If none were given and a `default=` was declared,
  the array is populated by splitting the default on commas (same
  convention as `choices=a,b,c`).
- `passthrough` — like `variadic`, but the parser stops looking for declared
  flags/options as soon as it hits the first token that isn't one of them,
  and captures every remaining token verbatim into a **bash array** —
  including tokens starting with `-`, with no "Unknown option" error. This
  is the same boundary a literal `--` already creates, just triggered
  automatically instead of requiring the marker. If a literal `--` is what
  triggers the boundary, it's captured too, as the array's first element -
  unlike plain `variadic`, where a leading `--` is just syntax and is
  dropped. This matters because passthrough tokens are typically forwarded
  raw to another command, where the `--` can itself carry meaning (e.g.
  disambiguating a pathspec from a revision for `git`); dropping it would
  be indistinguishable from the caller never having typed it. Explicit
  `type=`, `choices=` and `default=` attributes are rejected;
  the forwarded tail stays raw and untyped.

Only one `variadic` **or** `passthrough` argument is allowed per CLI
(whichever kind it is), and it must be the last one declared (checked at
startup; a broken schema is a bug in your script, not user input, so it's
reported the same way a parse error is).

Declared arguments must also follow one fixed order: any `required`
arguments first, then any `optional` ones, then the trailing `variadic`/
`passthrough` argument if there is one — `required* optional* (variadic |
passthrough)?`. Declaring a `required` argument after an `optional` one is
a schema error rather than being silently accepted, since positional
tokens are assigned left to right in declaration order — an earlier
`optional` argument would otherwise greedily claim the token meant for the
later `required` one, surfacing as a confusing `Missing required argument`
error instead of a clear schema-declaration error.

```bash
argument source required type=directory help="Source directory"
argument destination optional type=directory help="Destination directory"
argument files variadic help="Extra files"   # populates files=(...)

argument commit optional default=HEAD help="Commit ref"
argument reviewers variadic default=alice,bob help="Reviewers"

argument git_args passthrough help="Extra options forwarded to git log"
```

```bash
option author -a --author VALUE help="Filter by author"
argument git_args passthrough help="Extra options forwarded to git log"
```

invoked as `mycommand --author alice --stat -M` populates `author=alice` and
`git_args=(--stat -M)` — `--stat`/`-M` are never looked up as declared
options once the boundary is crossed.

As with `option`'s `default=`, an argument's default is trusted as-is and is
never itself type-checked.

### Overriding the populated variable name

By default the populated variable is named after the declared name. Add
`var=name` to any `flag`, `option`, or `argument` to change that:

```bash
flag verbose -v --verbose var=is_verbose
option output -o --output PATH var=build_dir
argument source required var=input_dir
```

populates `$is_verbose`, `$build_dir`, and `$input_dir` instead of
`$verbose`/`$output`/`$source`.

### Types

| Type        | Validates                          | Completion behavior  |
| ----------- | ----------------------------------- | -------------------- |
| `string`    | (no validation)                     | none                  |
| `integer`   | matches `^-?[0-9]+$`                 | none                  |
| `float`     | matches `^-?[0-9]+(\.[0-9]+)?$`       | none                  |
| `file`      | path exists and is a regular file    | file completion       |
| `directory` | path exists and is a directory       | directory completion  |
| `choice`    | one of `choices=a,b,c`               | the listed choices    |
| `git-commitish` | resolves to a commit via `git rev-parse` | none            |
| `git-range` | resolves via `git rev-list --count`  | none                  |

On typed declarations, omitting `type=` is the same as `type=string`;
passthrough arguments require omission and reject every explicit `type=`.
A default value (`default=`) is trusted as-is and is never itself type-checked.

`type=git-commitish` accepts anything git itself would accept as a
commit-ish — a SHA (full or abbreviated), branch, tag, or an expression like
`HEAD~2` — by running `git rev-parse --verify --quiet "<value>^{commit}"`.
A tree/blob SHA (not a commit) or an unresolvable name is rejected with the
usual `Invalid value:` error. If the command isn't running inside a git
repository at all, that's reported distinctly as `Not inside a git
repository:` rather than letting git's own error for the inner check leak
through.

```bash
option base -b --base VALUE type=git-commitish help="Base commit to diff against"
argument commit optional type=git-commitish default=HEAD help="Commit to inspect"
```

`type=git-range` accepts either a bare revision or a `A..B`/`A...B` range,
by running `git rev-list --count "<value>"`. Kept as a separate type from
`git-commitish` rather than an extension of it, so a plain single-commit
field doesn't silently start accepting range syntax. Same not-in-a-repo
handling as `git-commitish`.

```bash
argument from_range required type=git-range help="Range to copy notes from"
argument to_range required type=git-range help="Range to copy notes to"
```

### Schema validation

A broken CLI declaration is treated as a bug in your script, not user
input: `betteropts_parse` rejects it before parsing `$@` at all, naming the
exact bad token.

An unrecognized `key=value` attribute (a typo like `chocies=` instead of
`choices=`) is rejected:

```
'chocies' is not a recognized attribute for option 'mode'.
```

So is a bareword keyword that isn't valid for the given kind — `required`
or `multi` on a `flag`, `optional`/`variadic`/`passthrough` on anything but
an `argument`, or a second bareword after an `option`'s metavar:

```
'optional' is not a valid option modifier for 'jobs'.
```

An `argument` must declare **exactly one** of `required`, `optional`,
`variadic`, or `passthrough` — declaring none, or more than one, is also a
schema error rather than silently behaving as `optional`.

Every declaration requires a nonempty logical name. Ordinary output targets,
whether derived from that name or set with `var=`, must match
`[a-zA-Z_][a-zA-Z0-9_]*`; array expressions such as `var=result[0]` are rejected.
A logical name may differ from the output identifier when a valid `var=` is supplied.

Effective flag/option spellings cannot use the reserved builtins `-h`, `--help`,
`--usage` or `--__complete`; long spellings cannot contain `=`.
Repeated recognized attributes and spellings use their final values.
Passthrough rejects explicit `type=` and `choices=` attributes by presence,
including empty values and `type=string`.

A `type=` value that isn't one of the recognized types (a typo like
`type=int` instead of `type=integer`) is rejected the same way, rather than
silently being treated as no type constraint:

```
'int' is not a recognized type for option 'jobs'.
```

### Usage synopsis

`--usage` prints the summary and a single usage line; `--help` includes the
same line before its detailed entries. The quick-start CLI renders as:

```text
build [--verbose] [--force] --output PATH [--jobs N] SOURCE [DESTINATION]
```

Declared flags and options appear in declaration order, using the long
name when available and the short name otherwise. Optional entries are
bracketed; required options and arguments are bare. Value-taking options
include their metavar (or `VALUE` when it is missing or empty), and
variadic/passthrough arguments retain their `[NAME...]` form. The synopsis
omits descriptions and help annotations.
Built-in commands remain outside the synopsis; `-h, --help` still appears
in detailed help.

An `implicit=` option uses `--name[=METAVAR]` to show that an explicit value
must be attached with `=`; a short-only implicit option is shown bare,
since its short form cannot attach a value. A `multi` option uses
`[--name METAVAR]...` when optional and
`--name METAVAR [--name METAVAR]...` when required, so the ellipsis repeats
the whole occurrence rather than suggesting several values follow one
option name.

### Help text annotations

`--help` appends a parenthesized, comma-separated annotation list after an
option's or argument's label, summarizing schema facts that would otherwise
only be visible by reading the CLI's source: `required`, `repeatable` (a
`multi` option or a `variadic` argument), `default: <value>` (printed
verbatim, e.g. an unmodified `alice,bob` default list), `implicit: <value>`
(an option's `implicit=`, printed verbatim), and `choices: <a, b, c>` (for
`type=choice`). Only the annotations that actually apply are shown; an
option or argument with none of these renders exactly as it did before.
`flag` declarations never gain an annotation — they don't support
`required`, `multi`, `default=`, `implicit=`, or `choices=` at all.

```bash
option output -o --output PATH required type=directory help="Output directory"
option jobs -j --jobs N default=4 type=integer help="Worker count"
option topic -t --topic VALUE multi type=choice choices=fast,slow,auto help="Note topic to show"
option notes --notes REF multi implicit=refs/notes/commits help="Show notes from REF"
```

renders as:

```
-o, --output PATH (required)
    Output directory

-j, --jobs N (default: 4)
    Worker count

-t, --topic VALUE (repeatable, choices: fast, slow, auto)
    Note topic to show

--notes REF (repeatable, implicit: refs/notes/commits)
    Show notes from REF
```

## Compatibility matrices

This is the global compatibility reference for declaration syntax, value handling, output, help and completion.
Every CLI feature must keep these global tables consistent with its declaration and runtime contracts.
Proposed exclusive groups, Git SHA normalization and Fish completion are excluded because they are not implemented.

Read the applicability table before the pairwise table and runtime rules.
`S` means supported within the stated applicability; `X` means rejected; `C` means conditional on its numbered rule; `I` means accepted but ignored in that context.
A schema-accepted pair does not make arbitrary values or dependent combinations valid.
The tables include current quirks whose unresolved policies belong to the linked feature records.
Acceptance, including `I`, does not establish permission under the intended grammar.
[Passthrough attribute rejection](features/19-inert-declaration-policy.md#passthrough-declaration-attributes) is enforced; the [proposed positional-spelling correction](features/19-inert-declaration-policy.md#positional-spelling-correction) remains unresolved.
[Lossless metadata retrieval](features/19-inert-declaration-policy.md#lossless-metadata-retrieval) preserves internal/trailing newlines in literal metadata and checks structural values in full; simple declaration pairs do not establish these value-content rules.

### Declaration applicability

Cardinality rows select an argument's cardinality once; they do not add a second one.
Per-field attributes use an actual declared field name in place of `<field>`.

| Declaration token | `flag` | `option` | `argument` | Restriction or meaning |
| --- | --- | --- | --- | --- |
| `-x` | S | S | I | Exact short spelling; positional spellings are unused. |
| `--long` | S | S | I | Exact long spelling; positional spellings are unused. |
| Bare `METAVAR` | X | S | X | One bare placeholder; absent/empty falls back to `VALUE` in synopsis only; cannot combine with `fields=`. |
| `metavar=NAME` | X | S | X | Same metadata as bare placeholder; ordering matters when both occur; cannot combine with `fields=`. |
| `required` | X | S | S | Option occurrence versus nonempty required scalar positional. |
| `optional` | X | X | S | Scalar positional, possibly empty or defaulted. |
| `variadic` | X | X | C | At most one collect-rest positional, declared last. |
| `passthrough` | X | X | C | Same placement rule; raw tail with [boundary conditions](features/16-passthrough-boundary-contract.md#intended-outcome-and-open-decisions). |
| `multi` | X | S | X | Ordered arrays of option occurrences; independent of record arity; no `default=`. |
| `type=T` | X | S | C | Ordinary option/argument type; recognized names only; rejected on passthrough even when empty/string; scalar positional empty exception; cannot combine with `fields=`. |
| `choices=a,b` | X | C/I | C/I | Active only with ordinary `type=choice`; rejected on passthrough even when empty; cannot combine with `fields=`. |
| `default=D` | X | C | C | Rejected with `multi`, record fields, required positional or passthrough; unreachable on required ordinary option. |
| `implicit=V` | X | S | X | Bare ordinary occurrence substitutes V; explicit attachment requires long `=`; cannot combine with `fields=`. |
| `var=name` | C | C | C | Ordinary outputs require shell identifiers; record prefixes also follow field output rules. |
| `help=text` | S | S | S | Literal detailed-help prose; does not change parsing. |
| `fields=a,b` | X | S | X | Nonempty list of distinct shell identifiers; fixed arity; one field is allowed. |
| `<field>.type=T` | X | C | X | Requires the field in `fields=`; choice type also requires nonempty field choices; default field type is string. |
| `<field>.choices=a,b` | X | C | X | Requires the field in `fields=` and its type to be choice; cannot be inert metadata. |
| `syntax=equals` | X | C | X | Exactly two fields required; one token split at its first `=`; replaces separate-argument syntax. |

Unknown keys, invalid keywords and unknown types are rejected at schema finalization.
An argument must declare exactly one cardinality; ordinary options need not declare a metavar.
The ordinary examples assume unique schema names, unique spellings, distinct valid Bash output variables and conventional `-x` / `--long` names.
Distinct logical IDs retain independent metadata even when a name contains dots; logical IDs and metadata attributes have separate boundaries.
[Concrete identity and metadata-isolation corrections](features/22-schema-identity-validation.md#concrete-schema-and-integrity-corrections) are separate from the remaining [identity policy choices](features/22-schema-identity-validation.md#intended-outcome-and-open-decisions); duplicate spellings/output variables remain accepted with lookup and population precedence. Effective custom `-h`, `--help`, `--usage` and `--__complete` spellings are rejected, as are long spellings containing `=`. Every declaration requires a nonempty logical name; ordinary outputs must be Bash identifiers, independently of the logical name.
Record field names and prefixes follow the stricter [field identity contract](features/15-fixed-arity-options.md#schema-rules), including rejection of generated output collisions.

### Complete pairwise declaration matrix

The axes are `R` required, `O` optional, `V` variadic, `P` passthrough, `M` multi, `T` ordinary type, `C` ordinary choices, `D` default, `I` implicit, `K` metavar attribute, `B` bare metavar, `N` variable override, `H` help, `s` short spelling, `l` long spelling, `F` fields, `U` per-field type, `Q` per-field choices and `E` equals input syntax.
Keys use their `key=value` form; `·` mirrors the corresponding upper cell.
Every cell inherits applicability above; `X2` means no declaration kind accepts both.
Per-field cells additionally inherit the complete field context in C8; a conditional cell does not say its two tokens alone are sufficient.
Diagonals follow repetition rules r1–r5 below.

| + | R | O | V | P | M | T | C | D | I | K | B | N | H | s | l | F | U | Q | E |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| R | r2 | X1 | X1 | X1 | S | S | C2 | C1 | S | S | S | S | S | C3 | C3 | S | C8 | C8 | C10 |
| O | · | r3 | X1 | X1 | X2 | S | C2 | S | X2 | X2 | X2 | S | S | I | I | X2 | X2 | X2 | X2 |
| V | · | · | r3 | X1 | X2 | S | C2 | S | X2 | X2 | X2 | S | S | I | I | X2 | X2 | X2 | X2 |
| P | · | · | · | r3 | X2 | X4 | X4 | X4 | X2 | X2 | X2 | S | S | I | I | X2 | X2 | X2 | X2 |
| M | · | · | · | · | r4 | S | C2 | X3 | S | S | S | S | S | S | S | S | C8 | C8 | C10 |
| T | · | · | · | · | · | r1 | C2 | C4 | C5 | S | S | S | S | C3 | C3 | X5 | X5 | X5 | X5 |
| C | · | · | · | · | · | · | r1 | C2,4 | C2,5 | C2 | C2 | C2 | C2 | C2,3 | C2,3 | X5 | X5 | X5 | X5 |
| D | · | · | · | · | · | · | · | r1 | S | S | S | S | S | C3 | C3 | X5 | X5 | X5 | X5 |
| I | · | · | · | · | · | · | · | · | r1 | S | S | S | S | C6 | S | X5 | X5 | X5 | X5 |
| K | · | · | · | · | · | · | · | · | · | r1 | C7 | S | S | S | S | X5 | X5 | X5 | X5 |
| B | · | · | · | · | · | · | · | · | · | · | r5 | S | S | S | S | X5 | X5 | X5 | X5 |
| N | · | · | · | · | · | · | · | · | · | · | · | r1 | S | C3 | C3 | C9 | C8,9 | C8,9 | C9,10 |
| H | · | · | · | · | · | · | · | · | · | · | · | · | r1 | C3 | C3 | S | C8 | C8 | C10 |
| s | · | · | · | · | · | · | · | · | · | · | · | · | · | r1 | C3 | S | C8 | C8 | C10 |
| l | · | · | · | · | · | · | · | · | · | · | · | · | · | · | r1 | S | C8 | C8 | C10 |
| F | · | · | · | · | · | · | · | · | · | · | · | · | · | · | · | r1 | C8 | C8 | C10 |
| U | · | · | · | · | · | · | · | · | · | · | · | · | · | · | · | · | r1,C8 | C8 | C8,10 |
| Q | · | · | · | · | · | · | · | · | · | · | · | · | · | · | · | · | · | r1,C8 | C8,10 |
| E | · | · | · | · | · | · | · | · | · | · | · | · | · | · | · | · | · | · | r1,C10 |

1. **X1:** two cardinalities on one argument are rejected, including a repeated identical cardinality.
   **X2:** one token is invalid for each possible kind.
   **X3:** `multi` + `default=` is always rejected, including with `required` or `implicit=`.
   **X4:** passthrough rejects explicit type, choices and default attributes by presence.
   **X5:** record fields cannot combine with ordinary metavar, type, choices, default or implicit attributes.
2. **C1:** `required default=D` is accepted on an ordinary option, but omission fails requiredness before defaults, so the fallback is unreachable.
   On an argument it is rejected; [declaration policy](features/19-inert-declaration-policy.md#intended-outcome-and-open-decisions) owns the unresolved ordinary-option policy.
3. **C2:** ordinary `choices=` is inert without `type=choice`; passthrough rejects both attributes.
   Missing/empty ordinary choices are schema-accepted, but no option value matches them.
   Completion and annotations use ordinary choices only for `type=choice`; [declaration policy](features/19-inert-declaration-policy.md#intended-outcome-and-open-decisions) owns these ordinary metadata cases.
4. **C3:** spellings operate on flags/options; on arguments they are accepted metadata with no parsing, help or completion effect.
5. **C4:** ordinary defaults bypass all type/choice validation.
   Optional positional defaults also replace an explicitly empty scalar; variadic defaults are comma-split arrays.
   Defaults retain internal and trailing newlines, including within each variadic member.
6. **C5:** a retained scalar implicit value is checked during validation, so a later scalar occurrence can overwrite it before validation.
   Every `multi` occurrence is checked; an unused invalid implicit value is not checked.
   Implicit literals retain their full bytes and validate like the corresponding explicit value.
   See the [retained scalar validation contract](features/21-retained-scalar-validation-contract.md#intended-outcome-and-acceptance).
7. **C6:** a short implicit spelling always substitutes the implicit value.
   A short-only implicit option has no way to accept an explicit value; a following word belongs to positionals.
8. **C7:** `METAVAR metavar=NAME` is accepted and NAME wins; `metavar=NAME METAVAR` is rejected as a second placeholder.
9. **C8:** a field attribute requires `fields=` naming that field.
   A choice field requires both `<field>.type=choice` and nonempty `<field>.choices=`; other field types reject field choices.
   Thus `F` + choice-valued `U` also needs `Q`, `F` + `Q` also needs choice-valued `U`, and `U` + `Q` also needs `F`.
   The matrix's per-field context is a complete declared choice field; ordinary scalar-only attributes remain rejected in that context.
   These dependencies are global schema rules, not consequences of pairwise acceptance alone.
   Per-field metadata remains independent from ordinary declarations whose logical IDs contain dots; field lists/types and prefixes are checked without removing trailing newlines.
10. **C9:** a record's `var=` prefix must be a shell identifier outside `_bo`/`_bo_*`.
    Generated `<prefix>_<field>` variables must not collide with any other declared output, including another record field under a different prefix.
    The unused base prefix is not itself an output; ordinary outputs require shell identifiers, while broader output-state policy remains under [schema identity validation](features/22-schema-identity-validation.md#intended-outcome-and-open-decisions).

11. **C10:** `syntax=equals` requires exactly two fields and rejects every other value, including empty text.
    Final recognized attributes win, so repeated syntax/field declarations must satisfy this dependency in their final state.
    The option consumes one token per occurrence while retaining two logical fields.

### Repeated declaration tokens

| Rule | Repeated declaration token | Result |
| --- | --- | --- |
| r1 | Same recognized key, short spelling or long spelling | Last value wins; additional spellings do not become aliases; repeated types select one final type; values retain their full bytes before validation/use. |
| r2 | `required` | Idempotent on option; rejected on argument as a second cardinality; invalid on flag. |
| r3 | `optional`, `variadic`, `passthrough` | Rejected as a second cardinality on argument; invalid on other kinds. |
| r4 | `multi` | Idempotent on option; invalid on other kinds. |
| r5 | Bare metavar | A second bare placeholder is rejected. |

Final record metadata must still satisfy C8/C9/C10 after repeated `fields=` or per-field attributes.
A final field list that removes a field with declared attributes is rejected, as is a final non-choice field type with retained field choices.
An earlier unknown key/bareword remains a schema error; a later recognized attribute does not repair it.
These rules concern tokens within one declaration; repeated argv occurrences follow the runtime rules below.

### Positional ordering across declarations

`S` means the two declarations can occur consecutively, subject to the global sequence `required* optional* (variadic | passthrough)?`.

| Earlier \ later | required | optional | variadic | passthrough |
| --- | --- | --- | --- | --- |
| required | S | S | S | S |
| optional | X: required after optional | S | S | S |
| variadic | X: must be last | X: must be last | X: only one collect-rest | X: only one collect-rest |
| passthrough | X: must be last | X: must be last | X: only one collect-rest | X: only one collect-rest |

Flags/options, including records of different arities, have no declaration-order restriction relative to arguments.
Only leftover tokens occupy positional slots; fields consumed by a record do not.
An earlier optional slot claims the first leftover token even with a trailing passthrough, so retained `--` and unknown flags can fill that earlier slot.
[Passthrough boundary policy](features/16-passthrough-boundary-contract.md#intended-outcome-and-open-decisions) owns the unresolved bare-token and earlier-slot contract.

### Types across other dimensions

All supported types apply to ordinary scalar/multi options, required/optional/variadic arguments, and scalar/multi record fields.
Passthrough accepts no explicit type or choices attributes and does not validate its tail.
Ordinary option/optional argument/variadic defaults are trusted; records reject defaults and implicit values.
Per-field type and choice attributes operate on logical fields (separate argv tokens unless `syntax=equals` is selected), while an ordinary type/choices declaration constrains the ordinary value.

| Type | Value check | Ordinary `choices=` | Ordinary `default=` | Ordinary `implicit=` / `multi` | Passthrough | Record field | Value completion |
| --- | --- | --- | --- | --- | --- | --- | --- |
| omitted / `string` | None | I | Trusted | No type constraint | Omitted S; explicit `string` X | No validation; field choices X | None |
| `integer` | `^-?[0-9]+$` | I | Trusted | Final scalar / every multi value | X | Final scalar / every multi field; field choices X | None |
| `float` | `^-?[0-9]+(\.[0-9]+)?$` | I | Trusted | Final scalar / every multi value | X | Final scalar / every multi field; field choices X | None |
| `file` | Existing regular file | I | Trusted | Final scalar / every multi value | X | Final scalar / every multi field; field choices X | Filesystem paths, including directories |
| `directory` | Existing directory | I | Trusted | Final scalar / every multi value | X | Final scalar / every multi field; field choices X | Directories |
| `choice` | Member of comma-separated choices | Active | Trusted | Final scalar / every multi value | X | Nonempty field choices required; final scalar / every multi field | Listed choices in declared order |
| `git-commitish` | `git rev-parse --verify --quiet "${value}^{commit}"` succeeds | I | Trusted | Final scalar / every multi value | X | Final scalar / every multi field; field choices X | None |
| `git-range` | `git rev-list --count "$value"` succeeds | I | Trusted | Final scalar / every multi value | X | Final scalar / every multi field; field choices X | None |

Git types require Git and a working tree when a value is actually checked, including provided fields; omitted optional records do not trigger that check.
They preserve input text rather than resolving populated values to SHAs; ranges resolving to no commits are allowed.
An empty required scalar positional is missing, and an empty optional scalar positional bypasses typing and may receive its default.
An explicit empty ordinary option, implicit option value, record field or typed array element is supplied and type-checked.
Empty string fields pass the string validator; constraining field types apply their ordinary validator to empty text.
[Empty positional presence](features/20-empty-positional-presence.md#intended-outcome-and-open-decisions) owns the unresolved scalar positional policy.
`file` completion includes directories although validation rejects them; [filesystem candidate policy](features/18-attached-value-completion.md#intended-outcome-and-open-decisions) remains unresolved.

### Runtime, presentation and completion interactions

| Interaction | Current behavior / condition |
| --- | --- |
| Short/long names × ordinary option | `-x VALUE`, `--long VALUE`, `--long=VALUE`; mandatory values may be declared flags, negative numbers or literal `--`. |
| Short/long names × record | Without `syntax=equals`: `-x A B`, `--long A B`, `--long=A B` for two fields; attachment supplies the first field only; each field preserves one argv token verbatim. With `syntax=equals`: `-x A=B`, `--long A=B`, `--long=A=B`; one pair token supplies both fields. |
| Equals syntax × validation/output | First literal `=` splits two logical fields; empty fields follow their validators, extra `=` stays in the second; missing separators fail parsing even if a later scalar occurrence would overwrite them; repeated keys remain ordered occurrences, with no `+=` interpretation. |
| Bundles/short attachments × parser | `-vf`, `-xVALUE`, `-x=VALUE` are unknown with conventional declarations; there is no splitting into switches; literally declared unusual spellings have unresolved [identity policy](features/22-schema-identity-validation.md#intended-outcome-and-open-decisions). |
| Bare `-` / negative positional × parser | `-` is positional; other dash tokens require recognition, passthrough or a preceding real `--`. |
| Repetition × validation/population | Flags stay true; ordinary options and scalar records keep and validate only their final occurrence; `multi` retains and validates every ordinary value or record occurrence, including duplicates. |
| Required × empty/implicit/default | Option requiredness needs an occurrence; empty string fields and ordinary string implicit values can satisfy it; a required scalar positional needs nonempty text; a default never satisfies a required ordinary option. |
| Records × ordinary required/default/implicit/multi | Different declarations coexist; ordinary defaults remain trusted; ordinary implicit options consume no following value; each declaration retains its own arity and repetition behavior. |
| Record fields × scalar-only attributes | Ordinary metavar/type/choices/default/implicit are rejected on a record; field default/implicit/metavar are unsupported. |
| Positionals × ordinary options/records | Known options and records are recognized between bare positional words before a real parsing boundary; scalar slots fill before the remaining tail. |
| `--` × mandatory ordinary values/record fields | A marker consumed as a value or field does not end parser recognition; recognition resumes after all required value slots. |
| `--` × ordinary arguments/variadic | A real marker ends recognition and is dropped from the positional stream; following tokens are positional. |
| Passthrough × unknown/known/bare tokens | Unknown dash tokens, including unknown attached options and invalid attached flags, start capture; known ordinary/record options before the boundary parse; bare tokens do not start capture; [boundary policy](features/16-passthrough-boundary-contract.md#intended-outcome-and-open-decisions) remains open. |
| Passthrough × marker/earlier scalar slots | Marker retained in the shared positional stream and may fill an earlier scalar slot; tail is unvalidated and has no value completion. |
| Schema error × built-ins | Finalization failure takes precedence over help, usage and completion, including missing/empty names, malformed outputs, reserved/unreachable aliases, passthrough attributes and malformed field schemas. |
| Help/usage × values/errors/requiredness/passthrough | Raw prescan until first literal `--`; a detected `-h`/`--help`/`--usage` succeeds only as the sole argv token, bypassing requirements. Any additional argument, including another built-in or marker, causes stderr error and exit 1 before business logic, even in a value, field or passthrough tail. General [prescan boundary policy](features/23-builtin-prescan-policy.md#intended-outcome-and-open-decisions) remains unresolved. |
| Consumed marker × built-in prescan | Raw `--` stops prescan even when the parser consumes it as an ordinary value/field; later known options can still parse; attached `--option=--` contains no raw marker. |
| `--__complete` × other arguments | Dispatch only as first argv word after help/usage prescan; protocol `--` protects completion words from that prescan. An unprotected help/usage token rejects the mixed invocation before completion dispatch. |
| Summary/description × help/usage | Summary in both; description only in help; neither changes value handling. |
| Declaration metadata × synopsis/help | Synopsis follows declaration order, long-name preference, requiredness, metavar/uppercase field names, multi and implicit syntax; help adds literal prose and annotations, preserving internal/trailing newlines through metavar and label composition; `var=` changes no labels. |
| Defaults/implicit/choices × help | Ordinary declared defaults/implicit values printed verbatim; choice comma lists formatted; field choices qualified by uppercase field name in field order; passthrough rejects choices attributes. |
| Completion × required/default/var | Completion does not validate requiredness, apply defaults or populate outputs; `var=` does not rename CLI candidates. |
| Completion × types/positionals/multi | Type supplies candidates; positional words advance slots; selected repeatable choices remain available; fields select their own type/choices. |
| Completion × implicit | Bare long/short ordinary implicit occurrences consume no following completion word. |
| Completion × completed attachments | Known ordinary attachment fills its value; a record attachment supplies its first field (the whole pair with `syntax=equals`) and remaining words fill any later token slots; unknown attached options and invalid attached flags respect passthrough boundaries. |
| Completion × current attachments | Current equals-format attachments complete the appropriate field and preserve option/key prefixes; a current `--name=partial` word has no value candidates for ordinary or separate-argument record options; [attached completion](features/18-attached-value-completion.md#intended-outcome-and-open-decisions) remains proposed. |
| Completion × literal `--` | Consumed value/field markers occupy value slots; real markers stop option-name suggestions and leave positional slot selection unchanged; passthrough boundaries stop candidates under the implemented [replay rules](features/17-completion-boundary-replay.md#implemented-replay-rules). |
| Completion × bare `-` / passthrough | A completed bare `-` advances one positional slot and leaves known-option completion available before a real boundary, including with passthrough; a `-` consumed as a mandatory value/field advances no positional slot. See [bare-minus replay](features/17-completion-boundary-replay.md#bare-minus-replay). |
| Completion × built-in names | Offers `-h`/`--help`, omits `--usage`/`--__complete`; replay skips parser errors instead of reporting them. |
| Bash adapter × completion protocol | Reinvokes the command and reads line candidates into `COMPREPLY`; register with `-o nosort` to preserve candidate order. Reassembles adjacent unquoted `=` word breaks; only equals-pair candidates receive prefix removal, shell escaping and first-field space suppression. Already quoted/escaped current pair tokens are not decoded; ordinary [attached-value completion](features/18-attached-value-completion.md#intended-outcome-and-open-decisions) remains unsupported. |
| `var=` × scalar/array output | Flags are booleans; ordinary options/scalar arguments strings; `multi`/variadic/passthrough arrays; scalar records populate `<prefix>_<field>` strings and multi records aligned arrays; assignments are global with no export added. |

### Scope

All dependent schema constraints apply to larger combinations, including `multi` + `default=`, field choice context and positional ordering.
Pairwise acceptance does not remove any of those dependencies or define arbitrary attribute values, preexisting output variables or interactive shell insertion.
Ordinary identity, inert declaration, empty positional, passthrough and built-in prescan policies remain with their linked feature records.
Every new feature must extend the global declaration dimensions, applicable conditions and runtime contracts instead of adding a separate feature-only compatibility reference.
It must also satisfy the [supported Bash version contract](features/24-minimum-bash-compatibility.md#intended-outcome).

## Calling `betteropts_parse "$@"`

This is the only function you call after declaring the CLI, and it must be
called with your script's original `"$@"`. It runs the full lifecycle:

1. Finalizes the schema (catches a broken CLI declaration, e.g. two
   variadic arguments).
2. Scans raw arguments for `-h`/`--help`/`--usage` up to the first literal
   `--`, even when parsing would consume those tokens as values or a
   passthrough tail. Each prints its output and `exit 0`s only when it is
   the sole argv token. Any other argument causes an explanatory stderr
   error and `exit 1`, without running business logic. A raw `--` protects
   later tokens even when parsing consumes that marker as a mandatory
   value; attached `--item=--help` is data. After this scan, `--__complete`
   dispatches only as the first argv word, prints candidates and exits 0;
   its protocol `--` protects completion words from the scan.
3. Parses `$@` against the schema. An unknown option, a missing option
   value, or an unexpected/missing positional argument prints an error to
   stderr and `exit 1`s.
4. Validates required options/arguments are present, then checks declared
   types against the retained values: only the final ordinary scalar option
   value or scalar record occurrence, every `multi` value or record
   occurrence, and positional values under the rules above. Explicit and
   implicit option values follow the same rule; overwritten scalar values
   are not checked. A failure prints to stderr and `exit 1`s.
5. Applies defaults to options that weren't provided.
6. Populates shell variables — ordinary variables in your script's scope,
   never exported.

On success, `betteropts_parse` returns normally and your script continues.
You never need to check its exit status yourself: if it returns at all, the
CLI was valid.

Mixed help/usage invocations previously printed help/usage and exited 0,
which could make a skipped write look successful. They now fail, including
repeated built-ins and `--help --usage` in either order. Invoke help/usage
separately; see [built-in prescan policy](features/23-builtin-prescan-policy.md).

## Error messages

All errors go to stderr and exit with status 1:

```
Unknown option:

--verboes

Use --help for usage.
```

```
Missing value:

--output
```

```
Unexpected argument:

foo
```

```
Missing required argument:

SOURCE
```

```
Missing required option:

--output
```

Type-validation failures look like:

```
Invalid value:

--jobs abc (must be an integer)
```

## Bash completion

Register the library's generic completion function against your command
name(s):

```bash
source /path/to/betteropts.sh
complete -F _bo_bash_completion -o nosort mycommand
```

`_bo_bash_completion` knows nothing about `mycommand`'s schema — it
re-invokes its private `--__complete` interface and feeds the candidates
(one per line) it prints back into `COMPREPLY`. `-o nosort` keeps candidate
order as emitted (e.g. a `choice` list's declared order) instead of
alphabetizing it. `--__complete` is an internal interface: it's reserved,
never shown in `--help`, and not meant to be invoked by end users directly.

## Testing

Tests are written in [BATS](https://github.com/bats-core/bats-core)
(vendored as git submodules under `support/`):

```bash
git submodule update --init --recursive
test/run.sh
```

`test/unit/*.bats` exercise the library's internal functions directly (by
sourcing `betteropts.sh`); `test/integration/*.bats` run the fixture CLIs
under `test/fixtures/` end-to-end as real subprocesses.

Line coverage is measured with [kcov](https://github.com/SimonKagstrom/kcov):

```bash
test/coverage.sh
```

An optional real interactive Bash/Readline check for equals-pair insertion uses
Python 3 and a pseudo-terminal (test tooling only):

```bash
python3 test/interactive_equals.py
```
