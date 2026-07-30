# BetterOpts - Runtime Bash CLI Library Constraints

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

# Error Handling

Errors should be concise and consistent.

Parse errors terminate execution with a non-zero exit status.

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

# Internal Architecture

Although distributed as a single file, the implementation should be organized into logical sections:

```
Public API

Schema

Error Handling

Parser

Validation

Defaults

Variable Population

Usage Generator

Help Generator

Completion
```

These are implementation details only; the exact order and boundaries may
shift as the file grows, so long as each section stays self-contained.

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

---

# Relationship to `features/`

This document is architecture-level constraints only — invariants that hold
regardless of which flags/options/arguments/types a given CLI declares. The
CLI grammar itself (what `flag`/`option`/`argument` accept, what types
exist, what `--help`/`--usage`/completion render) lives entirely in
`features/`, one increment per file: [`00-initial.MD`](features/00-initial.MD)
is the v1 baseline this document used to also describe; the rest are the
increments layered on top of it since.
