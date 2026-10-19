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
exactly as it would to a value the user typed — unlike `default=`, which
stays trusted-as-is and is never validated. `implicit=` combined with
`multi` and `default=` together remains a schema error, same as `multi` +
`default=` without `implicit=` — that rule is about "the default list"
having no single sensible meaning for zero-vs-many occurrences, which
`implicit=` doesn't resolve.

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
  be indistinguishable from the caller never having typed it. No
  `type=`/`choices=` validation applies to passthrough tokens, and no
  `default=` is supported.

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

Omitting `type=` is the same as `type=string`. A default value (`default=`)
is trusted as-is and is never itself type-checked.

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

This is the global compatibility reference, audited against `master`
at `05f8cb5`. Update it and its evidence when adding or changing any CLI
feature. It covers all current declaration dimensions, not just the most
recent feature. Proposed exclusive groups, Git SHA normalization and Fish
completion are not implemented and are excluded.

Read the applicability table first, then the pairwise table, then the
runtime rules. A pair being schema-accepted does **not** prove every
value, larger combination, help rendering or completion path works.
`S` means supported within the stated applicability; `X` means rejected;
`C` means conditional (see its numbered rule); `I` means accepted but
ignored in the indicated context. The tables describe current behavior;
follow-up work belongs to the linked records under [`features/`](features/).

Evidence uses stable test IDs in
[`test/unit/compatibility.bats`](test/unit/compatibility.bats) (`C01`–`C23`,
`C28`–`C29`) and
[`test/integration/compatibility.bats`](test/integration/compatibility.bats)
(`C24`–`C27`). `C01` checks each dimension on each declaration kind;
`C02`–`C04` check every ordered pair, including repetitions, with explicit
acceptance or relevant rejection messages. These are **automated schema
checks**. Runtime evidence is identified separately below; general suite
success is not evidence that every runtime combination was exercised.

### Declaration applicability

Every recognized key, modifier and spelling has a row. Cardinality rows
select an argument's cardinality once; they do not add a second one.
`S`/`C` cells here have schema evidence in `C01`; `I` behavior is checked
by `C07`, `C10` and `C11`.

| Declaration token | `flag` | `option` | `argument` | Restriction or meaning |
| --- | --- | --- | --- | --- |
| `-x` | S | S | I | Exact short spelling; positional spellings are unused (`C11`). |
| `--long` | S | S | I | Exact long spelling; positional spellings are unused (`C11`). |
| Bare `METAVAR` | X | S | X | One bare placeholder; absent/empty falls back to `VALUE` in synopsis only. |
| `metavar=NAME` | X | S | X | Same metadata as bare placeholder; ordering matters when both occur (`C18`). |
| `required` | X | S | S | Option occurrence versus nonempty required positional (`C06`, `C16`). |
| `optional` | X | X | S | Scalar positional, possibly empty or defaulted. |
| `variadic` | X | X | C | At most one collect-rest positional, last (`C05`). |
| `passthrough` | X | X | C | Same placement rule; raw tail with [boundary conditions](features/16-passthrough-boundary-contract.md) (`C10`–`C14`, `C28`). |
| `multi` | X | S | X | Ordered array of option occurrences; no `default=` (`C06`, `C09`). |
| `type=T` | X | S | C/I | Recognized names only; ignored on passthrough; empty scalar exception (`C09`, `C10`, `C19`, `C23`). |
| `choices=a,b` | X | C/I | C/I | Active only with `type=choice`, except passthrough never validates (`C07`, `C10`). |
| `default=D` | X | C | C | Rejected with `multi`, required positional or passthrough; unreachable on required option (`C01`–`C06`). |
| `implicit=V` | X | S | X | Bare occurrence substitutes V; explicit attachment requires long `=` (`C06`, `C09`). |
| `var=name` | S | S | S | Changes the populated variable, not the CLI spelling or label (`C09`, `C11`). |
| `help=text` | S | S | S | Literal detailed-help prose; does not change parsing. |

Unknown keys and invalid keywords/types are rejected at schema
finalization (`C21`, existing [`schema.bats`](test/unit/schema.bats)).
An argument must declare exactly one cardinality; options need not declare
a metavar. The ordinary examples assume unique schema names, unique
spellings, distinct valid Bash output variables and conventional `-x` /
`--long` names. Other identities are outside the matrix's certified inputs;
[identity policy](features/22-schema-identity-validation.md) owns that scope.
`C22` characterizes duplicate spellings/output variables, and `C27`
reserved-name shadowing.

### Complete pairwise declaration matrix

The axes are `R` required, `O` optional, `V` variadic, `P` passthrough,
`M` multi, `T` type, `C` choices, `D` default, `I` implicit,
`K` metavar attribute, `B` bare metavar, `N` variable override,
`H` help, `s` short spelling and `l` long spelling.
Keys use their `key=value` form. `·` mirrors the corresponding upper cell.
Every cell inherits applicability above; `X2` means no declaration kind
accepts both. Each cell's schema evidence is `C02`–`C04`, including both
orders. Diagonals use the repetition rules `r1`–`r5` below.

| + | R | O | V | P | M | T | C | D | I | K | B | N | H | s | l |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| R | r2 | X1 | X1 | X1 | S | S | C2 | C1 | S | S | S | S | S | C3 | C3 |
| O | · | r3 | X1 | X1 | X2 | S | C2 | S | X2 | X2 | X2 | S | S | I | I |
| V | · | · | r3 | X1 | X2 | S | C2 | S | X2 | X2 | X2 | S | S | I | I |
| P | · | · | · | r3 | X2 | I | I | X4 | X2 | X2 | X2 | S | S | I | I |
| M | · | · | · | · | r4 | S | C2 | X3 | S | S | S | S | S | S | S |
| T | · | · | · | · | · | r1 | C2 | C4 | C5 | S | S | S | S | C3 | C3 |
| C | · | · | · | · | · | · | r1 | C2,4 | C2,5 | C2 | C2 | C2 | C2 | C2,3 | C2,3 |
| D | · | · | · | · | · | · | · | r1 | S | S | S | S | S | C3 | C3 |
| I | · | · | · | · | · | · | · | · | r1 | S | S | S | S | C6 | S |
| K | · | · | · | · | · | · | · | · | · | r1 | C7 | S | S | S | S |
| B | · | · | · | · | · | · | · | · | · | · | r5 | S | S | S | S |
| N | · | · | · | · | · | · | · | · | · | · | · | r1 | S | C3 | C3 |
| H | · | · | · | · | · | · | · | · | · | · | · | · | r1 | C3 | C3 |
| s | · | · | · | · | · | · | · | · | · | · | · | · | · | r1 | C3 |
| l | · | · | · | · | · | · | · | · | · | · | · | · | · | · | r1 |

1. **X1:** two cardinalities on one argument are rejected, including a
   repeated identical cardinality. **X2:** one token is invalid for each
   possible kind. **X3:** `multi` + `default=` is always rejected, including
   with `required` or `implicit=` (`C03`, `C06`). **X4:** passthrough has no
   defaults (`C04`).
2. **C1:** `required default=D` is accepted on an option, but omission
   fails requiredness before defaults; the fallback is unreachable.
   On an argument it is rejected (`C06`;
   [declaration policy](features/19-inert-declaration-policy.md)).
3. **C2:** `choices=` is inert without `type=choice`; passthrough ignores
   validation even with it. Missing/empty choices are schema-accepted, but
   no option value matches. Completion and annotations use choices only
   for `type=choice` (`C07`, `C08`, `C10`;
   [declaration policy](features/19-inert-declaration-policy.md)).
4. **C3:** spellings operate on flags/options; on arguments they are
   accepted metadata with no parsing, help or completion effect (`C11`).
5. **C4:** defaults bypass all type/choice validation. Optional positional
   defaults also replace an explicitly empty scalar; variadic defaults
   are comma-split arrays (`C09`, `C16`, `C23`).
6. **C5:** a retained scalar implicit value is checked during validation,
   not schema finalization; a later scalar occurrence can overwrite it
   before validation. Every `multi` occurrence is checked (`C09`, `C19`,
   `C20`). An unused invalid implicit value is not checked
   ([validation contract](features/21-retained-scalar-validation-contract.md)).
7. **C6:** a short implicit spelling always substitutes the implicit
   value. A short-only implicit option has no way to accept an explicit
   value; a following word belongs to positionals (`parser_implicit.bats`).
8. **C7:** `METAVAR metavar=NAME` is accepted and NAME wins;
   `metavar=NAME METAVAR` is rejected as a second placeholder (`C18`).

Repetition rules (schema `C02`–`C04`; stored results `C18`):

| Rule | Repeated declaration token | Result |
| --- | --- | --- |
| r1 | Same recognized key, short spelling or long spelling | Last value wins; additional spellings do not become aliases. A repeated `type=` selects one final type, not combined validators. |
| r2 | `required` | Idempotent on option; rejected on argument as a second cardinality; invalid on flag. |
| r3 | `optional`, `variadic`, `passthrough` | Rejected as a second cardinality on argument; invalid on other kinds. |
| r4 | `multi` | Idempotent on option; invalid on other kinds. |
| r5 | Bare metavar | A second bare placeholder is rejected. |

These rules concern tokens within one declaration. Repeated argv
occurrences have different semantics (`C20` and the runtime table).
An earlier unknown key/bareword is still a schema error; repeating a
recognized attribute does not repair an unrecognized token.

### Positional ordering across declarations

Every ordered pair below is automated in `C05`. `S` means the two
declarations can occur consecutively, subject to the global sequence
`required* optional* (variadic | passthrough)?`.

| Earlier \ later | required | optional | variadic | passthrough |
| --- | --- | --- | --- | --- |
| required | S | S | S | S |
| optional | X: required after optional | S | S | S |
| variadic | X: must be last | X: must be last | X: only one collect-rest | X: only one collect-rest |
| passthrough | X: must be last | X: must be last | X: only one collect-rest | X: only one collect-rest |

Flags/options have no declaration-order restriction relative to argument
declarations. Tokens are assigned to positionals greedily in their own
declaration order. An earlier optional slot claims the first leftover
token even when a trailing passthrough exists; retained `--` and unknown
flags can therefore fill that earlier slot (`C28`,
[`population.bats`](test/unit/population.bats)).

### Types across other dimensions

All eight types are schema-accepted on ordinary options, `multi` options
and every argument cardinality. `C09` checks valid values and unchanged
population for **each type** as a required scalar option, required multi
option, bare required implicit option, required/optional/variadic argument,
and passthrough. It also checks unvalidated defaults for each type on an
option, optional argument and variadic argument. `C19` checks invalid
values for every constraining type on each validated path, plus the
passthrough exemption. Those are automated runtime checks; they do not
cover every spelling, empty value or arbitrary larger combination.

| `type=` | Value check | `choices=` | `default=` | `implicit=` / `multi` | Passthrough | Value completion |
| --- | --- | --- | --- | --- | --- | --- |
| omitted / `string` | None | I | Trusted | No type constraint | I | None |
| `integer` | `^-?[0-9]+$` | I | Trusted | Final scalar / every multi value | I | None |
| `float` | `^-?[0-9]+(\.[0-9]+)?$` | I | Trusted | Final scalar / every multi value | I | None |
| `file` | Existing regular file | I | Trusted | Final scalar / every multi value | I | Filesystem paths, including directories (`C29`; [candidate policy](features/18-attached-value-completion.md)) |
| `directory` | Existing directory | I | Trusted | Final scalar / every multi value | I | Directories |
| `choice` | Member of comma-separated choices | Active | Trusted | Final scalar / every multi value | I; choices still advertised | Listed choices in declared order |
| `git-commitish` | `git rev-parse --verify --quiet "${value}^{commit}"` succeeds | I | Trusted | Final scalar / every multi value | I | None |
| `git-range` | `git rev-list --count "$value"` succeeds | I | Trusted | Final scalar / every multi value | I | None |

Git types require Git and a working tree when a value is actually checked;
they preserve the input text and do not resolve populated values to SHAs.
An empty valid range is allowed. Existing validation and completion
evidence is in [`validation.bats`](test/unit/validation.bats),
[`completion.bats`](test/unit/completion.bats) and
[`integration/types.bats`](test/integration/types.bats).
Scalar positional `''` bypasses type validation and is missing when
required; an option's explicit empty value is provided and checked, as is
an empty element in a typed array (`C16`, `C23`;
[presence policy](features/20-empty-positional-presence.md)).

### Runtime, presentation and completion interactions

The evidence column identifies **automated runtime checks** for the
stated cases. Other combinations are not implied by these rows. Test file
links without C IDs refer to existing tests; C IDs refer to the new
compatibility checks linked above.

| Interaction | Actual baseline behavior / condition | Evidence |
| --- | --- | --- |
| Short/long names × ordinary option | `-x VALUE`, `--long VALUE`, `--long=VALUE`; quoted argv boundaries preserved. Mandatory next value may be a declared flag, negative number or literal `--`. | `C09`, `C17`, [`parser.bats`](test/unit/parser.bats) |
| Bundles/short attachments × parser | `-vf`, `-xVALUE`, `-x=VALUE` are unknown unless literally declared as an exact spelling; no splitting into switches. | Conventional spellings `C17`; arbitrary malformed declarations inspected only, outside certified inputs. |
| Bare `-` / negative positional × parser | `-` is positional; other dash tokens require recognition, passthrough or a preceding `--`. | Parser source inspected; negative typed values after `--` in `C09`; [boundary coverage](features/16-passthrough-boundary-contract.md). |
| Repetition × validation/population | Flags stay true; ordinary option keeps and validates only its final value; `multi` keeps and checks every occurrence, in order, including duplicates. | `C09`, `C20`, [`parser_multi.bats`](test/unit/parser_multi.bats), [`parser.bats`](test/unit/parser.bats) |
| Required × empty/implicit/default | Option requires an occurrence, so empty string implicit can satisfy `required type=string`; required scalar positional needs nonempty text; a default never satisfies a required option. | `C06`, `C16`, `C23` |
| Positionals × flags/options | Known options are recognized between positional words before an actual parsing boundary; scalar positional slots fill before the remaining tail. | `C12`, [`population.bats`](test/unit/population.bats) |
| `--` × ordinary arguments/variadic | Ends recognition; dropped from positional stream; following values are positional. A `--` consumed as mandatory option value does not end recognition. | `C14`, `C17`, [`parser.bats`](test/unit/parser.bats) |
| Passthrough × unknown/known/bare tokens | Unknown dash tokens start capture; known options before boundary still parse. Bare tokens do not start capture. Unknown `--flag=value` also starts capture. | `C12`, `C13`, [`parser_passthrough.bats`](test/unit/parser_passthrough.bats); [boundary contract](features/16-passthrough-boundary-contract.md) |
| Passthrough × `--` / earlier scalar slots | Marker retained in shared positional stream; it can fill an earlier scalar slot before the passthrough array. No validation or value completion for tail. | `C10`, `C28`, [`parser_passthrough.bats`](test/unit/parser_passthrough.bats), [`completion_passthrough.bats`](test/unit/completion_passthrough.bats) |
| Schema error × built-ins | Finalization failure wins over help, usage and completion. | `C25` |
| Help/usage × errors/requiredness/passthrough | Raw prescan until first literal `--`; first `-h`/`--help`/`--usage` wins, even if parser would have consumed it as a value or captured it as a tail token. | `C24`, `C26`; [prescan policy](features/23-builtin-prescan-policy.md) |
| `--__complete` × other arguments | Dispatch only when first argv word, after help/usage prescan; protocol `--` protects completion words from that prescan. | `C26`, [`integration/completion.bats`](test/integration/completion.bats) |
| `summary` / `description` × help/usage | Summary in both; description only in help; independent of value processing. | [`help_usage.bats`](test/unit/help_usage.bats), [`integration/help_usage.bats`](test/integration/help_usage.bats) |
| Declaration metadata × synopsis/help | Synopsis uses declaration order, long-name preference, requiredness, metavar, multi and implicit syntax; help adds literal prose and annotations; `var=` changes no labels. | `C11`, `C18`, [`help_usage.bats`](test/unit/help_usage.bats) |
| Defaults/implicit/choices × help | Annotations show declared values verbatim; comma lists formatted for choices only; defaults not validated. Passthrough choices appear in help without being enforced. | `C07`, `C10`, [`help_usage.bats`](test/unit/help_usage.bats); [declaration policy](features/19-inert-declaration-policy.md) |
| Completion × required/default/var | Completion replays words without validating requiredness or applying defaults/populating outputs. `var=` does not rename candidates. | `C09` schema/runtime evidence; completion architecture inspected; [completion coverage](features/18-attached-value-completion.md). |
| Completion × types/positionals/multi | Type supplies candidates, positional words advance slots, repeatable choices remain available after selection. | [`completion.bats`](test/unit/completion.bats), [`completion_passthrough.bats`](test/unit/completion_passthrough.bats) |
| Completion × implicit | Bare long/short implicit occurrence does not consume the next completion word. | [`completion.bats`](test/unit/completion.bats) |
| Completion × attached values | Earlier `--known=value` skipped; current `--known=partial` gets no value candidates. Unknown attached passthrough tokens are skipped too. | `C13`, `C15`; [boundary replay](features/17-completion-boundary-replay.md), [attached completion](features/18-attached-value-completion.md) |
| Completion × literal `--` | Without passthrough, replay advances a positional slot and still offers option names afterward. | `C14`; slot advancement inspected in `_bo_complete`; [boundary replay](features/17-completion-boundary-replay.md). |
| Completion × built-in names | Offers `-h`/`--help`, omits `--usage`/`--__complete`; completion skips parser errors through its own replay. | [`completion.bats`](test/unit/completion.bats), `C26` |
| Bash adapter × completion protocol | Adapter reinvokes command, reads line candidates into `COMPREPLY`; `-o nosort` registration preserves candidate order. | Adapter delegation [`completion.bats`](test/unit/completion.bats); [interactive verification](features/18-attached-value-completion.md). |
| `var=` × scalar/array output | Flags are booleans, ordinary options/scalar arguments strings, `multi`/variadic/passthrough arrays; global variables, with no export added. | `C09`, `C11`, existing [`population.bats`](test/unit/population.bats) |

### Verification limits

Declaration pairs/repetitions are automated; meaningful type paths and
listed runtime cases have separate evidence. Arbitrary attribute values,
all larger combinations, all presentation cross-products, preexisting
output variables and interactive completion behavior are not exhaustively
tested. No live-probe-only result is represented as automated coverage.
Pairwise checks do not replace the global ordering rule or the unchanged
`multi` + `default=` exclusion in larger combinations.

For a future feature, extend the dimension inventory and all applicable
tables, add schema pair/repetition expectations, and exercise affected
runtime boundaries, validation, output, help and completion paths. Record
actionable follow-up work and its evidence/dependencies under `features/`;
keep the matrix's coverage limits explicit before calling it compatible.

## Calling `betteropts_parse "$@"`

This is the only function you call after declaring the CLI, and it must be
called with your script's original `"$@"`. It runs the full lifecycle:

1. Finalizes the schema (catches a broken CLI declaration, e.g. two
   variadic arguments).
2. Handles `-h`/`--help`, `--usage`, and `--__complete` — checked against
   the raw arguments (so `--help` wins even next to other invalid options),
   and only up to a literal `--` (so a positional argument that happens to
   be the string `--help` after `--` is not treated as the flag). These
   print their output and `exit 0`.
3. Parses `$@` against the schema. An unknown option, a missing option
   value, or an unexpected/missing positional argument prints an error to
   stderr and `exit 1`s.
4. Validates required options/arguments are present and every provided
   value matches its declared type. A failure prints to stderr and
   `exit 1`s.
5. Applies defaults to options that weren't provided.
6. Populates shell variables — ordinary variables in your script's scope,
   never exported.

On success, `betteropts_parse` returns normally and your script continues.
You never need to check its exit status yourself: if it returns at all, the
CLI was valid.

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
re-invokes `mycommand --__complete -- <words...>` and feeds the candidates
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
