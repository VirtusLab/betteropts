# BetterOpts - Runtime Bash CLI Library Specification

## Overview

BetterOpts is a pure Bash runtime library for declarative command-line argument parsing.

The library must:

* require only Bash
* have no external dependencies
* require no code generation
* be distributed as a single file
* expose a minimal public API

The implementation should make writing a CLI command declarative rather than imperative.

---

# Goals

BetterOpts should provide:

* declarative CLI definitions
* automatic parsing
* automatic validation
* automatic help generation
* automatic usage generation
* automatic Bash completion
* automatic variable population
* consistent error reporting

Every feature should derive from a single CLI definition.

---

# Public API

The public API consists of:

```
summary
description

flag
option
argument

betteropts_parse
```

Everything else is private.

---

# Typical Usage

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

---

# Execution Lifecycle

Calling:

```bash
betteropts_parse "$@"
```

performs:

1. Finalize CLI schema.
2. Handle built-in commands.
3. Parse command-line arguments.
4. Validate values.
5. Apply defaults.
6. Populate shell variables.
7. Return to caller.

On successful parsing, `betteropts_parse` returns normally.

For:

* `--help`
* `--usage`
* `--__complete`
* parse errors

the library handles output and exits internally.

The command author does not need error handling.

---

# Built-in Commands

The library reserves:

```
-h
--help

--usage

--__complete
```

`--__complete` is an internal interface.

It must not appear in help output.

---

# summary()

Defines the short command description.

Displayed by:

* `--help`
* `--usage`

Example:

```bash
summary "Build a project"
```

---

# description()

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

---

# Usage Output

Example:

```
Build a project

Usage:

build [OPTIONS] SOURCE [DESTINATION]
```

Only the summary is shown.

The long description is omitted.

---

# Help Output

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

---

# Flags

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

---

# Options

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

---

# Positional Arguments

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

---

# Variable Population

After successful parsing, BetterOpts creates shell variables.

By default, the variable name is identical to the declared option or argument name.

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

These are ordinary shell variables.

They must never be exported.

---

# Supported Types

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

---

# Defaults

Example:

```bash
option jobs \
    default=4
```

Defaults are applied after parsing and before variables are populated.

---

# Required Options

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

---

# Parsing Rules

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

Bundling (`-vf`) is not supported to reduce complexity but might need to be added later.

---

# Bash Completion

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
| --------- | -------------------- |
| file      | file completion      |
| directory | directory completion |
| choice    | available choices    |
| string    | none                 |
| integer   | none                 |
| float     | none                 |

No separate completion definitions exist.

---

# Error Messages

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

---

# Internal Architecture

Although distributed as a single file, the implementation should be organized into logical sections:

```
Public API

Schema

Parser

Validation

Variable Population

Help Generator

Usage Generator

Completion

Error Handling

Utilities
```

These are implementation details only.

---

# CLI Schema

The declaration API builds an internal CLI schema.

The schema is the single source of truth.

The parser consumes the schema.

The validator consumes the schema.

The help generator consumes the schema.

The completion engine consumes the schema.

No subsystem owns duplicate metadata.

---

# Metadata Encapsulation

The internal storage format is an implementation detail.

Parser, validator, help generator, and completion generator must not directly depend on storage structures.

All access should go through an internal metadata API.

The implementation may use arrays, associative arrays, records, or another representation.

Changing storage should not require changes outside the metadata layer.

---

# Coding Guidelines

Prefer:

* small focused functions
* readable Bash
* explicit naming
* low coupling
* minimal hidden state

Avoid:

* duplicated metadata
* parser logic in help generation
* help logic in parser
* unnecessary complexity

---

# Success Criteria

A command author should only need:

```bash
source betteropts.sh

summary ...

description ...

flag ...

option ...

argument ...

betteropts_parse "$@"
```

The library automatically provides:

* argument parsing
* validation
* defaults
* shell variable population
* `--help`
* `--usage`
* Bash completion
* consistent errors

The command author should never manually:

* parse `$@`
* validate arguments
* generate help
* generate usage
* implement completion
* populate variables

The command consists only of CLI declaration followed by business logic.