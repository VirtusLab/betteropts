#!/usr/bin/env bats

load '../../support/bats-support/load'
load '../../support/bats-assert/load'

@test "bats harness works" {
  run echo "hello"
  assert_success
  assert_output "hello"
}
