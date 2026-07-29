# BetterOpts

BetterOpts is a pure Bash runtime library for declarative command-line
argument parsing. You declare flags, options, and positional arguments up
front; the library parses `$@`, validates it, applies defaults, populates
shell variables, and generates `--help`/`--usage`/Bash completion — all from
that one declaration.

See [DESIGN.MD](DESIGN.MD) for the full specification this library
implements.

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

### `flag <name> [-x] [--xxx] [help="..."]`

A boolean switch. Give a short form (`-x`), a long form (`--xxx`), or both.
Populates `<name>=true` if the flag was passed (any number of times),
`<name>=false` otherwise.

```bash
flag verbose -v --verbose help="Enable verbose logging"
flag quiet --quiet help="Suppress output"   # long-only is fine
```

### `option <name> [-x] [--xxx] METAVAR [required] [type=T] [choices=a,b,c] [default=D] [multi] [var=name] [help="..."]`

A flag that takes a value. `METAVAR` (e.g. `PATH`, `N`) is the placeholder
name shown in `--help`/usage. Accepts:

```
-o value
--output value
--output=value
```

`-o=value` and bundled short flags (`-vf`) are intentionally **not**
supported (per DESIGN.MD, to keep the parser simple).

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

### `argument <name> <required|optional|variadic> [type=T] [choices=a,b,c] [default=D] [var=name] [help="..."]`

A positional argument. Exactly one of `required`, `optional`, or `variadic`
must be given:

- `required` — must be supplied. Cannot declare a `default=` (a required
  argument with a default is a contradiction — checked at startup as a
  schema error, the same way "more than one variadic argument" is).
- `optional` — may be omitted; populates an empty string when it is, or the
  `default=` value if one was declared.
- `variadic` — collects every remaining positional token into a **bash
  array**, zero or more. Only one variadic argument is allowed per CLI, and
  it must be the last one declared (checked at startup; a broken schema is
  a bug in your script, not user input, so it's reported the same way a
  parse error is). If none were given and a `default=` was declared, the
  array is populated by splitting the default on commas (same convention as
  `choices=a,b,c`).

```bash
argument source required type=directory help="Source directory"
argument destination optional type=directory help="Destination directory"
argument files variadic help="Extra files"   # populates files=(...)

argument commit optional default=HEAD help="Commit ref"
argument reviewers variadic default=alice,bob help="Reviewers"
```

As with `option`'s `default=`, an argument's default is trusted as-is and is
never itself type-checked.

### Overriding the populated variable name

By default the populated variable is named after the declared name. Add
`var=name` to any `option` or `argument` to change that:

```bash
option output -o --output PATH var=build_dir
argument source required var=input_dir
```

populates `$build_dir` and `$input_dir` instead of `$output`/`$source`.

### Types

| Type        | Validates                          | Completion behavior  |
| ----------- | ----------------------------------- | -------------------- |
| `string`    | (no validation)                     | none                  |
| `integer`   | matches `^-?[0-9]+$`                 | none                  |
| `float`     | matches `^-?[0-9]+(\.[0-9]+)?$`       | none                  |
| `file`      | path exists and is a regular file    | file completion       |
| `directory` | path exists and is a directory       | directory completion  |
| `choice`    | one of `choices=a,b,c`               | the listed choices    |

Omitting `type=` is the same as `type=string`. A default value (`default=`)
is trusted as-is and is never itself type-checked.

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

Type-validation failures (not covered by DESIGN.MD's worked examples; this
project's own convention) look like:

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
