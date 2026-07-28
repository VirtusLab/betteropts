#!/usr/bin/env bats

load '../../support/bats-support/load'
load '../../support/bats-assert/load'

TYPES_FIXTURE="$BATS_TEST_DIRNAME/../fixtures/types"
BUILD_FIXTURE="$BATS_TEST_DIRNAME/../fixtures/build"

@test "--__complete lists all choices for an empty choice-option prefix" {
  run "$TYPES_FIXTURE" --__complete -- --mode ""
  assert_success
  assert_line "fast"
  assert_line "slow"
  assert_line "auto"
}

@test "--__complete filters choices by prefix" {
  run "$TYPES_FIXTURE" --__complete -- --mode "s"
  assert_success
  assert_output "slow"
}

@test "--__complete offers no candidates for type=string" {
  run "$TYPES_FIXTURE" --__complete -- --count "1" ""
  assert_success
  refute_output --partial "alpha"
}

@test "--__complete offers no candidates for type=integer" {
  run "$TYPES_FIXTURE" --__complete -- --count ""
  assert_success
  assert_output ""
}

@test "--__complete offers no candidates for type=float" {
  run "$TYPES_FIXTURE" --__complete -- --ratio ""
  assert_success
  assert_output ""
}

@test "--__complete completes option names by prefix" {
  run "$TYPES_FIXTURE" --__complete -- "--mo"
  assert_success
  assert_output --partial "--mode"
}

@test "--__complete does not suggest --__complete itself" {
  run "$TYPES_FIXTURE" --__complete -- "--"
  refute_output --partial "--__complete"
}

@test "--__complete does not suggest --usage" {
  run "$TYPES_FIXTURE" --__complete -- "--"
  refute_output --partial "--usage"
}

@test "--__complete performs directory completion for type=directory" {
  cd "$BATS_TEST_TMPDIR"
  mkdir -p alpha-dir beta-dir
  : > not-a-dir.txt
  run "$BUILD_FIXTURE" --__complete -- --output ""
  assert_success
  assert_line "alpha-dir"
  assert_line "beta-dir"
  refute_output --partial "not-a-dir.txt"
}

@test "--__complete performs file completion for type=file" {
  cd "$BATS_TEST_TMPDIR"
  : > config.toml
  mkdir -p somedir
  run "$TYPES_FIXTURE" --__complete -- --config ""
  assert_success
  assert_line "config.toml"
}
