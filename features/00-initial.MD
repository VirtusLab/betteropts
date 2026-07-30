# Feature: Initial CLI Grammar (v1 Baseline)

## Status

Implemented since the initial commit. Unlike `01`–`08`, this document isn't
a proposal that preceded its own implementation — it's the CLI grammar
`DESIGN.MD` originally specified end-to-end, extracted verbatim (including
reverting the `Help Output` example to its pre-annotation form, since that
addition is `07`'s) when `DESIGN.MD` was split into architecture constraints
and feature-level content. It exists so the full grammar has one entry per
increment, `00` through `08`, instead of half living in `DESIGN.MD` and half
in `features/`. See [`DESIGN.MD`](../DESIGN.MD) for the constraints that
apply across every feature, including this one.

Everything below was already true before `01` (argument `default=`), `02`
(`multi` options), `03` (`passthrough` arguments), `05`/`06` (`git-commitish`/
`git-range` types), and `07` (help-text annotations) extended it.

## Problem

N/A — this is a baseline extraction, not a response to a gap.

## Typical Usage

```bash
#!/usr/bin/env bash

source "$LIB/betteropts.sh"

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

The command author never manually parses `$@`.

## `summary()`

Defines the short command description.

Displayed by:

* `--help`
* `--usage`

Example:

```bash
summary "Build a project"
```

## `description()`

Defines an optional long command description.

Displayed only by:

```
--help
```

Example:

```bash
description "
Build compiles the project and writes the resulting
artifacts to the configured output directory.

Incremental builds are supported.
"
```

## Usage Output

Example:

```
Build a project

Usage:

build [OPTIONS] SOURCE [DESTINATION]
```

Only the summary is shown. The long description is omitted.

## Help Output

Example:

```
Build a project

Build compiles the project and writes the resulting
artifacts to the configured output directory.

Incremental builds are supported.

Usage:

build [OPTIONS] SOURCE [DESTINATION]

Arguments

SOURCE
    Source directory

DESTINATION
    Destination directory

Options

-v, --verbose
    Enable verbose logging

-f, --force
    Overwrite existing output

-o, --output PATH
    Output directory

-j, --jobs N
    Worker count

-h, --help
    Show this help
```

All help text is generated from the CLI schema.

## Flags

Flags are boolean values.

Declaration:

```bash
flag verbose -v --verbose \
    help="Verbose output"
```

Accepted:

```
-v

--verbose
```

Result:

```bash
verbose=true
```

Default:

```bash
verbose=false
```

Repeated flags remain true.

## Options

Options require values.

Declaration:

```bash
option output -o --output PATH \
    help="Output directory"
```

Accepted:

```
-o value

--output value

--output=value
```

Result:

```bash
output="value"
```

## Positional Arguments

Required:

```bash
argument source required
```

Optional:

```bash
argument destination optional
```

Variadic:

```bash
argument files variadic
```

Rules:

* only one variadic argument may exist
* variadic argument must be last

## Variable Population

After successful parsing, BetterOpts creates shell variables.

By default, the variable name is identical to the declared option or
argument name.

Example:

```bash
option output -o --output PATH
option jobs -j --jobs N

argument source required
```

Produces:

```bash
output=...
jobs=...
source=...
```

Variable names can be overridden.

Example:

```bash
option output -o --output PATH \
    var=build_dir

argument source required \
    var=input_dir
```

Produces:

```bash
build_dir=...
input_dir=...
```

Flags become boolean variables:

```bash
flag verbose -v --verbose
```

Produces:

```bash
verbose=true
```

or:

```bash
verbose=false
```

These are ordinary shell variables. They must never be exported.

## Supported Types

Version 1 supports:

```
string

integer

float

file # existing

directory # existing

choice
```

Examples:

```bash
option jobs \
    type=integer

option output \
    type=directory

option config \
    type=file

option mode \
    type=choice \
    choices=fast,slow,auto
```

The type is the single source of truth for:

* validation
* completion behavior

## Defaults

Example:

```bash
option jobs \
    default=4
```

Defaults are applied after parsing and before variables are populated.

## Required Options

Example:

```bash
option output \
    required
```

Failure:

```
Missing required option:

--output
```

## Parsing Rules

Supported syntax:

```
-v

-v -f

-o value

--output value

--output=value

--

positionals
```

Unknown options produce errors.

Unexpected positional arguments produce errors.

Missing option values produce errors.

The following syntax is intentionally not supported:

```
-o=value
```

Bundling (`-vf`) is not supported to reduce complexity but might need to be
added later.

## Bash Completion

Version 1 supports Bash completion only.

The completion interface is internal.

The command is queried through:

```
--__complete
```

The generic Bash completion script uses this interface.

Completion is generated from the CLI schema.

Completion behavior:

| Type      | Completion           |
| --------- | --------------------- |
| file      | file completion      |
| directory | directory completion |
| choice    | available choices    |
| string    | none                  |
| integer   | none                  |
| float     | none                  |

No separate completion definitions exist.

## Error Messages

Errors should be concise and consistent.

Examples:

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

Parse errors terminate execution with a non-zero exit status.

Version 1 does not implement option name suggestions.
