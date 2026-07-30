# Feature: Fish Shell Completion

## Status

Proposed. Not yet implemented.

## Problem

Completion today only ships a Bash-side integration:

```bash
source /path/to/betteropts.sh
complete -F _bo_bash_completion -o nosort mycommand
```

`_bo_bash_completion` (`betteropts.sh:1054`) is a thin, Bash-specific shim:
it reads `COMP_WORDS`/`COMP_CWORD`, re-invokes `mycommand --__complete --
<words...>`, and feeds the resulting candidates (one per line) into
`COMPREPLY`. The actual schema-aware logic — `_bo_complete`,
`_bo_complete_value`, `_bo_complete_choice`, `_bo_complete_option_names`
(`betteropts.sh:939-1048`) — already speaks a shell-agnostic wire protocol:

```
<command> --__complete -- word1 word2 ... wordN
```

(`wordN`, possibly empty, is the in-progress partial word; candidates print
one per line to stdout; see the "Wire protocol" comment at
`betteropts.sh:926-937`.) Nothing about that protocol is Bash-specific —
`<command>` is invoked as an ordinary subprocess and only needs to print
lines. But there is no Fish-side glue that speaks it, and no documented way
for a CLI author to register completion under Fish. A user of a
`betteropts`-based CLI who happens to use Fish (not Bash) as their
interactive shell gets no completion at all today, even though the
underlying program is a perfectly ordinary subprocess Fish could invoke
just as easily as Bash can.

Fish's completion system isn't structured like Bash's `complete -F`
(register a shell function that inspects global completion state and fills
an array). Fish's `complete -c <cmd> -a '<expression>'` instead expects
`<expression>` to be a command substitution that prints candidates, one per
line — which happens to be exactly the shape `--__complete` already
produces. So this is purely a glue gap, not a gap in the completion engine
itself.

## Proposed API

A new reserved, hidden flag — `--__complete-fish` — that prints a
ready-to-use Fish completion script for the current command to stdout.
Registration is a one-time step, run manually or from an install script,
mirroring how the Bash `complete -F ...` line is something the CLI
author/user adds once, not something betteropts wires up automatically:

```fish
mycommand --__complete-fish > ~/.config/fish/completions/mycommand.fish
```

Fish auto-loads any file matching `<command-name>.fish` from that directory
for every new shell, so no `source`/rc-file edit is needed after that.

## Behavior

- Add a new function, e.g. `_bo_fish_completion_script`, alongside the
  existing completion code, that `printf`s a small Fish script:

  ```fish
  function __<cmd>_bo_complete
      set -l tokens (commandline -opc)
      set -l cur (commandline -t)
      <cmd> --__complete -- $tokens[2..-1] $cur
  end
  complete -c <cmd> -f -k -a '(__<cmd>_bo_complete)'
  ```

  with `<cmd>` substituted for `_bo_command_name` (already computed via
  `basename "$0"` at `betteropts.sh:21`, the same value `--help`/`--usage`
  use) and `__<cmd>_bo_complete` derived from it, so two different
  `betteropts`-based commands installed on the same machine don't collide
  on function name.
- `commandline -opc` returns Fish's own tokenized command line up to the
  cursor, **including** the command name as its first element;
  `$tokens[2..-1]` drops it, mirroring `_bo_bash_completion`'s own
  `${COMP_WORDS[@]:1:COMP_CWORD}` slice (`betteropts.sh:1056`), which drops
  `COMP_WORDS[0]` the same way. `commandline -t` supplies the in-progress
  partial word, exactly matching `--__complete`'s `wordN`. Together these
  reproduce the identical word list `_bo_bash_completion` builds today —
  only how the tokens are captured differs, not their shape.
  `<cmd> --__complete -- $tokens[2..-1] $cur` is then just an ordinary
  subprocess invocation from Fish's point of view; it runs under
  `mycommand`'s own `#!/usr/bin/env bash` shebang regardless of which shell
  is doing the completing, so `_bo_complete_value`'s existing `compgen -f`/
  `compgen -d` calls for `file`/`directory` types keep working unchanged —
  they execute inside that Bash subprocess, never inside Fish itself.
- `-f` on the `complete -c` line disables Fish's default fallback file
  completion, matching Bash's registration not falling back to filename
  completion beyond what `_bo_complete_value` explicitly offers. `-k`
  (`--keep-order`, added in Fish 2.7.0 per Fish's own documentation for
  `complete`) preserves the candidates in the order `--__complete` emits
  them, the Fish equivalent of the existing Bash registration's `-o
  nosort` — needed for the same reason: a `type=choice` list's declared
  order (`betteropts.sh:939-948`) would otherwise be silently
  alphabetized. **Not independently verified against a live Fish install
  in this proposal** (no `fish` binary was available while writing it) —
  confirm `-k`'s exact behavior/availability against the target minimum
  Fish version during implementation, before relying on it.
- No changes to `_bo_complete`, `_bo_complete_value`, `_bo_complete_choice`,
  `_bo_complete_option_names`, or the `--__complete` wire protocol itself —
  the entire schema-aware completion engine is already shell-agnostic.
  This feature only adds a second, Fish-specific *producer* of a
  registration snippet, alongside the existing Bash one.
- `--__complete-fish`, like `--__complete`, is reserved: it must never
  appear in `--help`/`--usage` output, and it's a generator meant to be run
  deliberately once (by a person or an install script) — unlike
  `--__complete`, which is invoked automatically, per-keystroke, by the
  shell's completion machinery itself.

## Non-Goals (v1)

- Doesn't add Zsh support. Zsh has its own completion system
  (`compdef`/`_arguments` or `compadd`), different enough from both Bash's
  and Fish's that it deserves its own separate proposal if wanted.
- Doesn't auto-install the generated script into
  `~/.config/fish/completions/` — generating the file's *content* is
  betteropts' job; writing it to the right place is the CLI
  author's/packaging step's job, exactly like the Bash `complete -F ...`
  line today.
- Doesn't change candidate content, filtering, or ordering logic in any
  way — `-k` only preserves whatever order `--__complete` already emits;
  it doesn't introduce new ordering behavior.
- Doesn't attempt Fish completion for the `--__complete`/`--__complete-fish`
  flags themselves; both stay excluded from `--help`/`--usage`, and
  therefore from the option-name candidates `_bo_complete_option_names`
  offers, exactly like `--__complete` is today.

## Backward Compatibility

Fully additive — a new reserved flag and a new function that prints a
Fish script; the existing `--__complete` wire protocol, `_bo_bash_completion`,
and every other completion function are untouched.

## Suggested Test Coverage

- `test/unit/completion.bats` (or a new `test/unit/fish_completion.bats`):
  `--__complete-fish`'s output contains the expected `complete -c <name> -f
  -k -a '(...)'` line and a `function __<name>_bo_complete` definition,
  with `<name>` matching the fixture's `_bo_command_name`; confirm two
  fixtures with different names produce non-colliding function names.
- A reserved-flag test mirroring the existing one for `--__complete`:
  `--__complete-fish` never appears in `--help`/`--usage` output.
- `test/integration/*.bats`: an end-to-end case, guarded on
  `command -v fish` (skip if Fish isn't installed, the same pattern
  `type=git-commitish`'s tests use for git availability) that sources the
  generated script into a real Fish subprocess and asks Fish to compute
  completions for a partial word against a fixture CLI, asserting the
  expected candidates come back — proving the generated script is not just
  well-formed but actually functions inside real Fish.
