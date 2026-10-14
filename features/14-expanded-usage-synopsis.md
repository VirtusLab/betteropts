# Feature: Expanded Usage Synopsis

## Status

Implemented.

## Problem

The shared usage line for `--usage` and `--help` contains the literal
`[OPTIONS]`, hiding the flags, required options, and value placeholders
already present in the schema. Detailed help lists those declarations,
but `--usage` needs to convey their syntax in one compact line.

## Behavior

The quick-start build CLI now renders:

```text
build [--verbose] [--force] --output PATH [--jobs N] SOURCE [DESTINATION]
```

1. Include each declared flag and option in declaration order, before the
   positional arguments. Prefer its long name; use its short name when
   no long name exists. These names and all rendering facts come through
   the internal metadata API.
2. Bracket optional entries. Required options and required positional
   arguments are bare. Options include their declared metavar, falling
   back to `VALUE` when it is absent or empty: those accepted declarations
   still consume a value, so rendering them bare would suggest a flag. A
   schema without declarations shows just the command name, with no
   placeholder or trailing whitespace.
3. An `implicit=` option with a long name renders as `--name[=METAVAR]`,
   inside optional-entry brackets when applicable. The attached `=` is
   necessary because a following token is never consumed as its value.
   A short-only implicit option renders bare (`-n` or `[-n]`): only the
   implicit value is available through the short form. The `VALUE`
   fallback also applies to long implicit options; it is confined to the
   synopsis, leaving existing detailed-help labels unchanged.
4. Optional `multi` options render as `[--name METAVAR]...`; required ones
   render as `--name METAVAR [--name METAVAR]...`. This distinguishes zero
   or more from one or more occurrences. The ellipsis repeats the whole
   option/value pair, since `multi` takes one value per occurrence.
   Combine this syntax with implicit values when both apply, for example
   `[--notes[=REF]]...` or `--notes[=REF] [--notes[=REF]]...`.
5. Positional syntax is unchanged: `NAME`, `[NAME]`, or `[NAME...]` for
   required, optional, and variadic/passthrough arguments respectively.
6. The synopsis contains no descriptions, defaults, choices, or other
   detailed-help annotations. Built-in commands remain outside it,
   matching the build example; `-h, --help` remains in detailed help.

`--usage` still prints only the summary and usage block. `--help` shares
that same synopsis and retains its description, detailed argument/option
entries, aliases, and annotations unchanged.

## Compatibility

The rendered synopsis changes for existing CLIs; declarations and parsing
are unaffected. This increment supersedes the `[OPTIONS]` rendering in
the historical baseline [`00-initial.MD`](00-initial.MD), whose original
examples remain as the v1 record. It does not change the detailed-help
annotation rules in [`07`](07-help-text-schema-annotations.md) or
[`13`](13-implicit-value-options.md).

## Validation

Unit tests cover declaration order, long-name preference and short-name
fallback, required/optional entries, value placeholders, multi/implicit
combinations, absent/empty metavar fallbacks, and unchanged positional
cardinalities.
Integration tests exercise both built-ins through the existing build,
annotations, and implicit-option fixture CLIs, preserving exact detailed
help output while replacing only the shared synopsis.
