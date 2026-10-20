# Feature: Equals Input Syntax for Two Fields

## Status

Implemented. The [global compatibility matrices](../README.md#compatibility-matrices)
include the declaration dependency and runtime interactions.

## Declaration and parsing contract

```bash
option set -s --set fields=key,value syntax=equals multi
# --set kind=topic -s kind=test --set=axis=true
# set_key=(kind kind axis)
# set_value=(topic test true)
```

1. `syntax=equals` is an option-only attribute requiring exactly two declared
   fields. It is the only supported syntax value; empty and unknown values are
   schema errors. Recognized repeated attributes retain their final values.
   Omitting `syntax=` preserves the original separate-argument format.
2. The selected format consumes exactly one argv token per occurrence. Accepted
   forms are `--set KEY=VALUE`, `-s KEY=VALUE` and `--set=KEY=VALUE`.
   Spaced `--set KEY VALUE` is not accepted. Short attachment/bundling remains
   unsupported.
3. Split at the first literal `=` only, preserving all other bytes. The first
   field cannot contain `=`; the second may contain any number of them. There is
   no escape grammar. Empty fields use existing validators, so `=` is a complete
   pair of empty string fields. Missing tokens report `Missing value`; a supplied
   token without `=` reports `Invalid value` with the expected joined metavars.
   A malformed occurrence fails parsing even if a later scalar occurrence exists.
4. Logical arity stays two: existing field validation and population handle both
   fields. Scalar records retain only the last complete occurrence; `multi`
   records retain every occurrence in order, including duplicate keys. `var=`,
   requiredness, field choices/types and omission semantics are unchanged.
   There is no per-key type selection, mapping conversion or `+=` operation:
   `k+=v` simply supplies first field `k+`, second field `v`.
5. Tokens consumed as pair input are classified before ordinary option parsing,
   then option/positional recognition resumes after one token. Real markers and
   passthrough boundaries retain their existing semantics. Raw help/usage
   detection still leaves `key=--help` as data. A separate `--help` token before
   the first literal `--` must be the sole argv token; `--set --help` now fails
   with an explanatory stderr error and exit 1 before business logic, replacing
   its previous successful help exit. See [built-in prescan policy](23-builtin-prescan-policy.md).
6. Help and usage render uppercased field names joined with `=`, e.g.
   `[--set KEY=VALUE]...`; existing field-qualified annotations remain unchanged.
   No public declaration function or runtime dependency is added.

## Completion contract

1. Replay consumes one pair token for any supported spelling and then resumes
   ordinary options/positionals, preserving existing marker/passthrough rules.
   First-field completion returns candidates ending in `=`; second-field
   completion preserves the first field and separator. Attached long completion
   also preserves its option prefix. Choices retain declared order and previously
   used keys/values remain available. First-field candidates containing the
   reserved `=` separator are omitted because those keys cannot be represented.
   Types constrain fields uniformly, not by key.
2. Direct `--__complete -- <words...>` returns whole raw pair tokens, including
   the long option prefix for a current attached form. Ordinary direct-protocol
   output is unchanged. The Bash adapter uses private `--bash` mode, whose first
   line identifies `pair` or `plain` context before any candidate lines; a context
   may have no candidates, and a boundary may produce no lines at all.
   This scopes insertion handling to schema-selected pairs rather than guessing
   from candidate text or duplicating schema metadata in the adapter.
   Adapter and target must both understand this private mode; mixing this adapter
   with an older separately vendored target library has no cross-version
   negotiation or fallback.
3. Bash's default `COMP_WORDBREAKS` splits unquoted `=` into separate words.
   The adapter rejoins only adjacent equals fragments, checking `COMP_LINE` so
   whitespace-separated tokens stay separate. For pair candidates it removes
   the prefix Readline leaves before its last equals word break, shell-escapes
   the replacement, and suppresses the automatic space after a unique first-field
   candidate so the value stays in the same argv token.
4. A real interactive Bash/Readline PTY check in
   [`test/interactive_equals.py`](../test/interactive_equals.py) verifies first-field
   insertion followed by value completion, long/short/attached forms, extra literal
   `=`, whitespace and shell-metacharacter candidates, and removal of `=` from
   `COMP_WORDBREAKS`. It executes the resulting command and checks the populated
   value rather than inferring insertion from protocol candidates.
5. The supported current pair token is unquoted and unescaped. Already quoted or
   escaped current-word decoding, other word breaks such as `:`, quoted command
   names and arbitrary cursor positions are not established by this bounded
   adapter. The PTY check observes no completion for quoted first-field `"ki`, quoted
   value prefix `kind="to`, escaped `kind=value\ w`, and `kind=scheme:va`
   with default word breaks. Some quoted pair forms can happen to complete,
   but that does not establish a general quoting contract. A safely escaped inserted
   candidate can be executed, but further completion after manually editing an
   escaped token is outside this contract. The broader interactive contract and
   ordinary current attached-value completion remain with
   [attached-value completion](18-attached-value-completion.md).

## Verification scope

Unit/integration tests cover schema rejection and repeated metadata, every
spelling, missing separators/tokens, empty and literal fields, scalar retention,
multi validation/alignment, unchanged ordinary arity, requiredness, boundaries,
help/usage, completion replay and adapter context negotiation.
The PTY script requires Python 3 as test tooling only. Runtime remains single-file
Bash with no new dependency. Bash 4.2 runtime execution remains pending under
[minimum-version compatibility](24-minimum-bash-compatibility.md); current-version
success does not establish the unexecuted minimum-version result.
