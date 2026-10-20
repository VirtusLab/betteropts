# Feature: Complete Values Attached to Long Options

## Status

Proposed for ordinary and separate-argument record options. Not yet implemented for those options. This is an existing completion gap,
explicitly excluded from [13](13-implicit-value-options.md), not a regression
introduced by implicit options or the compatibility matrix.

## Problem and observed baseline

At `05f8cb5`, `_bo_complete` treats an in-progress dash-prefixed word as an
option name. It does not split a current `--name=partial` for value
completion. Earlier known attached values replay correctly.

C15 in [`compatibility.bats`](../test/unit/compatibility.bats) checks this
synthetic example directly through the internal completion protocol:

```bash
option item --item N multi type=choice choices=one,two
_bo_complete -- --item=o              # no candidates
_bo_complete -- --item=one --item o   # one
```

Actual interactive Bash tokenization/word breaks, quoting and replacement
for attached words have not been verified by this evidence. The generic
`_bo_bash_completion` adapter passes `COMP_WORDS` to the protocol; direct
engine output alone does not prove the resulting interactive insertion.

## Intended outcome and open decisions

1. Complete a known long option's attached value using its declared type,
   including ordinary, implicit and multi options. Preserve short-form
   syntax: [13](13-implicit-value-options.md) does not allow short attachment.
2. Trial real Bash word breaks and quoting, then define whether candidates
   are whole attached words or replacement suffixes at each interface.
   Do not settle this from a constructed `COMP_WORDS` array alone.
3. Keep unknown attached tokens subject to parser boundaries and no value
   completion for opaque passthrough. Do not mistake them for known options.
4. Preserve or explicitly decide filesystem candidate policy. C29 shows
   `type=file` completion includes directories although file validation
   rejects a directory. This is not a proven bug: directory candidates may
   support navigation. No directory-filtering policy has been approved.

## Acceptance and test work

1. Cover choice order/prefixes, file/directory paths, empty suffixes, spaces,
   quotes and literal `=` in values, plus ordinary/implicit/multi options.
2. Check the subprocess protocol and real Bash insertion separately,
   including `COMP_WORDBREAKS`, `-o nosort`, quoting and escaping. Generic
   adapter delegation is already tested in
   [`completion.bats`](../test/unit/completion.bats); interactive sorting
   and replacement are not established by that test.
3. Requiredness, defaults and `var=` must not rename CLI candidates, apply defaults or populate outputs during attached-value completion.
   Add dedicated regressions that invoke completion in the same shell before checking output variables and raw default storage, so a subprocess cannot hide those side effects.

## Backward compatibility and dependencies

Additive candidates can still affect shell replacement, so validate the
adapter before claiming support. [17](17-completion-boundary-replay.md)
owns replay bugs; this current-word path can be developed independently
but must honor its final boundary state. Proposed [12](12-fish-completion.md)
owns Fish registration; coordinate any wire-protocol change with it rather
than duplicating that adapter task. No new shell support is required here.

## Equals-pair completion boundary

[Equals field syntax](25-equals-field-syntax.md#completion-contract) implements
current-word completion only for options explicitly selecting `syntax=equals`.
A real Bash 5.3 pseudo-terminal trial shows that default `COMP_WORDBREAKS` splits
unquoted `key=value` and `--set=key=value` at each `=`, while a current quoted
`"key=partial` remains one raw word including its opening quote.
The pair adapter rejoins adjacent equals fragments and safely escapes inserted
candidates containing whitespace or shell metacharacters. It does not decode
already quoted or escaped current words, or other breaks such as `:`.
The PTY check observes unchanged prefixes for `"ki`, `kind="to`,
`kind=value\ w` and `kind=scheme:va`; this does not imply every quoted
form fails. Completing an ordinary current `--name=partial` still has no
candidates. The broader quoting, cursor-position and ordinary attached-value
contract remains owned by this feature; the pair increment does not settle it.
The reproducible [PTY check](../test/interactive_equals.py) exercises actual
Readline insertion independently from constructed `COMP_WORDS` tests.
