#!/usr/bin/env bats

load '../../support/bats-support/load'
load '../../support/bats-assert/load'

bats_require_minimum_version 1.5.0

set -euo pipefail

FIXTURE="$BATS_TEST_DIRNAME/../fixtures/build"
PASSTHROUGH_FIXTURE="$BATS_TEST_DIRNAME/../fixtures/passthrough"
ANNOTATIONS_FIXTURE="$BATS_TEST_DIRNAME/../fixtures/annotations"
IMPLICIT_OPTION_FIXTURE="$BATS_TEST_DIRNAME/../fixtures/implicit_option"
BETTEROPTS="$BATS_TEST_DIRNAME/../../betteropts.sh"

# Synthetic consumer CLI with a real file write after the public parser call.
help_write_cli() {
  bash -c '
  add_tag_main() {
    case "$2" in
      plain) ;;
      errexit) set -e ;;
      nounset) set -u ;;
      strict) set -eu ;;
    esac
    source "$1"
    shift 2
    summary "Write corpus frontmatter"
    option slug --slug SLUG required
    option judged_at --judged-at REF required
    option question --question multi fields=label,value,passage \
      value.type=choice value.choices=high,medium,low
    option item --item VALUE
    option mode --mode implicit=on
    option topic --topic VALUE multi
    option pair --pair fields=key,value syntax=equals
    argument file required type=file
    argument extra passthrough
    betteropts_parse "$@"
    printf "passage=%s\n" "${question_passage[0]:-}" >> "$file"
    printf "WRITE LOGIC REACHED\n"
  }
  add_tag_main "$@"
  ' add-tag "$BETTEROPTS" "$@"
}

@test "consumer mixed-help invocation exits 1 on stderr and preserves the file in every caller mode" {
  local mode corpus="$BATS_TEST_TMPDIR/corpus"
  printf 'original frontmatter\n' > "$corpus"
  for mode in plain errexit nounset strict; do
    run --separate-stderr help_write_cli "$mode" "$corpus" --slug RetryPolicies --judged-at HEAD \
      --question Q-backoff medium --help
    assert_failure 1
    assert_output ''
    # BATS run --separate-stderr populates stderr.
    # shellcheck disable=SC2154
    assert_equal "$stderr" $'Invalid invocation:\n\n\'--help\' must be used alone; it cannot be combined with other arguments.'
    assert_equal "$(cat "$corpus")" 'original frontmatter'

    # Literal passage data reaches and exercises the same file write.
    run help_write_cli "$mode" "$corpus" --slug RetryPolicies --judged-at HEAD \
      --question Q-backoff medium 'passage --help'
    assert_success
    assert_output 'WRITE LOGIC REACHED'
    assert_equal "$(cat "$corpus")" $'original frontmatter\npassage=passage --help'
    printf 'original frontmatter\n' > "$corpus"
  done
}

@test "standalone help aliases and usage exit successfully before writing in every caller mode" {
  local mode builtin
  for mode in plain errexit nounset strict; do
    for builtin in -h --help --usage; do
      run help_write_cli "$mode" "$builtin"
      assert_success
      assert_output --partial 'Usage:'
      refute_output --partial 'WRITE LOGIC REACHED'
    done
  done
}

@test "mixed builtins reject positional option implicit multi fields equals and passthrough inputs" {
  local mode builtin form corpus="$BATS_TEST_TMPDIR/corpus"
  local -a words
  printf 'original frontmatter\n' > "$corpus"
  for mode in plain errexit nounset strict; do
    for builtin in -h --help --usage; do
      for form in positional ordinary unknown implicit multi fields equals passthrough; do
        case "$form" in
          positional) words=("$corpus") ;;
          ordinary) words=(--item value) ;;
          unknown) words=(--unknown) ;;
          implicit) words=(--mode) ;;
          multi) words=(--topic one --topic two) ;;
          fields) words=(--question Q-backoff medium) ;;
          equals) words=(--pair key=value) ;;
          passthrough) words=("$corpus" --unknown tail) ;;
          *) return 2 ;;
        esac
        run help_write_cli "$mode" "${words[@]}" "$builtin"
        assert_failure 1
        assert_output --partial "'$builtin' must be used alone"
        run help_write_cli "$mode" "$builtin" "${words[@]}"
        assert_failure 1
        assert_output --partial "'$builtin' must be used alone"
      done
    done
    assert_equal "$(cat "$corpus")" 'original frontmatter'
  done
}

@test "duplicates builtin combinations and help before a marker reject instead of reporting success" {
  local first second
  for first in -h --help --usage; do
    for second in -h --help --usage --; do
      run help_write_cli plain "$first" "$second"
      assert_failure 1
      assert_output --partial "'$first' must be used alone"
    done
  done
}

@test "--usage prints summary and usage line only" {
  run "$FIXTURE" --usage
  assert_success
  expected="Build a project

Usage:

build [--verbose] [--force] --output PATH [--jobs N] SOURCE [DESTINATION]"
  assert_output "$expected"
}

@test "-h prints the same as --help" {
  run "$FIXTURE" -h
  assert_success
  local help_output="$output"
  run "$FIXTURE" --help
  assert_success
  assert_output "$help_output"
}

@test "--help prints full help text matching the CLI schema" {
  run "$FIXTURE" --help
  assert_success
  expected="Build a project

Compile a project and write the resulting artifacts.

Supports incremental and parallel builds.

Usage:

build [--verbose] [--force] --output PATH [--jobs N] SOURCE [DESTINATION]

Arguments

SOURCE (required)
    Source directory

DESTINATION
    Destination directory

Options

-v, --verbose
    Enable verbose logging

-f, --force
    Overwrite existing output

-o, --output PATH (required)
    Output directory

-j, --jobs N (default: 4)
    Worker count

-h, --help
    Show this help"
  assert_output "$expected"
}

@test "--help does not mention --usage or --__complete" {
  run "$FIXTURE" --help
  refute_output --partial "--usage"
  refute_output --partial "--__complete"
}

@test "--help and --usage exit 0" {
  run "$FIXTURE" --help
  assert_equal "$status" 0
  run "$FIXTURE" --usage
  assert_equal "$status" 0
}

@test "--help rejects an otherwise-invalid command line instead of succeeding" {
  run "$FIXTURE" --this-is-not-a-real-option --help
  assert_failure 1
  assert_output $'Invalid invocation:\n\n\'--help\' must be used alone; it cannot be combined with other arguments.'
}

@test "-- suppresses built-in command detection for tokens after it" {
  run "$FIXTURE" --output /tmp -- --help
  assert_failure
  refute_output --partial "Usage:"
}

@test "--usage renders a passthrough argument with an ellipsis" {
  run "$PASSTHROUGH_FIXTURE" --usage
  assert_success
  assert_output --partial "[GIT_ARGS...]"
}

@test "--help renders a passthrough argument like any other argument, without fake type info" {
  run "$PASSTHROUGH_FIXTURE" --help
  assert_success
  assert_line "GIT_ARGS"
  assert_line "    Extra options forwarded to git log"
}

@test "--help annotates required, repeatable, default, and choices" {
  run "$ANNOTATIONS_FIXTURE" --help
  assert_success
  expected="Annotation sample

Usage:

annotations --output PATH [--jobs N] [--topic VALUE]... SOURCE [REVIEWERS...]

Arguments

SOURCE (required)
    Source directory

REVIEWERS (repeatable, default: alice,bob)
    Reviewers

Options

-o, --output PATH (required)
    Output directory

-j, --jobs N (default: 4)
    Worker count

-t, --topic VALUE (repeatable, choices: fast, slow, auto)
    Note topic to show

-h, --help
    Show this help"
  assert_output "$expected"
}

@test "--usage shows implicit optional values without descriptions or annotations" {
  run "$IMPLICIT_OPTION_FIXTURE" --usage
  assert_success
  expected="Implicit-value option sample

Usage:

implicit_option [--notes[=REF]]... [--mode[=VALUE]]"
  assert_output "$expected"
}

@test "--help uses the same implicit synopsis and retains detailed annotations" {
  run "$IMPLICIT_OPTION_FIXTURE" --help
  assert_success
  assert_line "implicit_option [--notes[=REF]]... [--mode[=VALUE]]"
  assert_line "--notes REF (repeatable, implicit: refs/notes/commits)"
  assert_line "--mode VALUE (default: off, implicit: on)"
}
