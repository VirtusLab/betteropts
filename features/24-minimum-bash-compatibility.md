# Feature: Exercise the Supported Bash Versions

## Status

Proposed compatibility improvement.
Not yet implemented.
The minimum-version promise requires runtime verification; an unverified version is not a demonstrated incompatibility.

## Problem

[README Requirements](../README.md#requirements) promises Bash 4.2 or newer.
The `jobs.test` section of [the CI workflow](../.github/workflows/ci.yml) selects the runner's default Bash rather than an explicit minimum/current version pair.
The minimum-version promise therefore needs an explicit execution contract instead of relying on inspection of language features or on the default runner interpreter.

Selecting the parent interpreter alone does not select every interpreter used by the suite.
[`test/run.sh`](../test/run.sh), [`support/bats/bin/bats`](../support/bats/bin/bats), BATS subprocess entry points and the CLI fixtures use `#!/usr/bin/env bash`; tests also invoke `bash -c` explicitly.
Interpreter selection must reach those child processes so a nominal minimum-version job cannot silently execute the runtime with the runner's default Bash.

## Intended outcome

Run the complete unit and integration suite on the minimum supported Bash and a current supported Bash in CI.
Keep the selected interpreter consistent across the launcher, BATS, subprocess tests and real fixture CLIs.
Maintain the dependency-free, single-file Bash runtime required by [DESIGN.MD](../DESIGN.MD#overview); build or installation tooling used by CI does not become a runtime dependency.

If minimum-version execution fails, determine whether the runtime, test harness or interpreter selection causes the failure.
Resolve compatibility failures within the existing promise, or obtain an explicit support-policy decision before changing README's minimum version.
Neither a version increase nor a claim of Bash 4.2 incompatibility follows from the present lack of execution evidence.

## Acceptance and test work

1. Add explicit minimum/current Bash jobs or matrix entries to the test workflow and document how each interpreter is selected.
   Install or build the required interpreter reproducibly without relying on the runner's default version.
2. Ensure `test/run.sh`, vendored BATS entry points, explicit `bash -c` commands and every fixture subprocess use the selected version.
   Assert the effective interpreter version in the launcher and representative child executions, including an integration fixture, rather than reporting only the parent shell's version.
3. Run all unit and integration tests in both version environments.
   Resolve failures and interpreter leakage before treating the minimum-version promise as verified.
   Keep Git/filesystem/completion paths and literal-data cases in the suite rather than substituting a reduced syntax-only check.
4. Preserve the established test coverage and shell checks while introducing the compatibility jobs.
   Keep CI infrastructure dependencies separate from runtime requirements.
5. Keep the supported-version statement and the executable CI selection consistent when the support policy changes.
   A missing interpreter or an unintended fallback must fail the compatibility job visibly.

## Backward compatibility and dependencies

This work changes verification infrastructure, not accepted CLI syntax or value semantics.
No runtime incompatibility has been established, and no higher minimum version is approved.
It can proceed independently of [completion replay](17-completion-boundary-replay.md#intended-outcome-and-acceptance), [inert declaration policy](19-inert-declaration-policy.md#intended-outcome-and-open-decisions) and [schema identity policy](22-schema-identity-validation.md#intended-outcome-and-open-decisions).
Future features must satisfy the same version contract without using narrower field or identity rules to settle those separate policies.
