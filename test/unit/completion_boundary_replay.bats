#!/usr/bin/env bats

load '../../support/bats-support/load'
load '../../support/bats-assert/load'

set -euo pipefail

BETTEROPTS="$BATS_TEST_DIRNAME/../../betteropts.sh"

setup() {
  # shellcheck source=../../betteropts.sh
  source "$BETTEROPTS"
}

replay_schema() {
  local tail="$1"
  option item -i --item VALUE multi type=choice choices=value
  option notes -n --notes VALUE multi implicit=default type=choice choices=default,explicit
  flag verbose -v --verbose
  argument first required type=choice choices=first
  argument second optional type=choice choices=second
  if [[ "$tail" != none ]]; then
    argument rest "$tail" type=choice choices=tail
  fi
}

replay_record() {
  option record -r --record multi fields=left,middle,right \
    left.type=choice left.choices=left \
    middle.type=choice middle.choices=middle \
    right.type=choice right.choices=right
}

@test "bare minus advances typed scalar slots and preserves option recognition with every tail" {
  local tail
  for tail in none variadic passthrough; do
    (
      replay_schema "$tail"
      _bo_finalize_schema
      _bo_parse - --item value
      _bo_assign_positionals
      assert_equal "${_bo_raw[first]}" -
      assert_equal "${_bo_multi_values[item.0]}" value
      run _bo_complete -- - --it
      assert_success
      assert_output --item
      run _bo_complete -- - ''
      assert_success
      assert_output second
      _bo_parse - - --item value
      _bo_assign_positionals
      assert_equal "${_bo_raw[second]}" -
      run _bo_complete -- - - ''
      assert_success
      if [[ "$tail" == variadic ]]; then
        assert_output tail
      else
        assert_output ''
      fi
      run _bo_complete -- - - --it
      assert_success
      assert_output --item
    )
  done
}

@test "mandatory ordinary values consume minus and marker in short long and attached forms" {
  local tail value spelling
  local -a prefix
  for tail in none passthrough; do
    for value in - --; do
      for spelling in short long attached; do
        (
          replay_schema "$tail"
          _bo_finalize_schema
          case "$spelling" in
            short) prefix=(-i "$value") ;;
            long) prefix=(--item "$value") ;;
            attached) prefix=("--item=$value") ;;
            *) return 1 ;;
          esac
          _bo_parse "${prefix[@]}"
          _bo_assign_positionals
          assert_equal "${_bo_multi_values[item.0]}" "$value"
          assert_equal "${#_bo_positional_tokens[@]}" 0
          run _bo_complete -- "${prefix[@]}" ''
          assert_success
          assert_output first
          run _bo_complete -- "${prefix[@]}" --it
          assert_success
          assert_output --item
        )
      done
    done
  done
}

@test "each mandatory record field consumes minus and marker using the ordinary replay classifier" {
  local tail value spelling slot
  local -a fields prefix fields_names=(left middle right)
  for tail in none passthrough; do
    for value in - --; do
      for spelling in short long attached; do
        for slot in 0 1 2; do
          (
            replay_schema "$tail"
            replay_record
            _bo_finalize_schema
            fields=(left middle right)
            fields[slot]="$value"
            case "$spelling" in
              short) prefix=(-r "${fields[@]}") ;;
              long) prefix=(--record "${fields[@]}") ;;
              attached) prefix=("--record=${fields[0]}" "${fields[@]:1}") ;;
              *) return 1 ;;
            esac
            _bo_parse "${prefix[@]}" --item --
            _bo_assign_positionals
            assert_equal "${#_bo_positional_tokens[@]}" 0
            assert_equal "${_bo_field_values[record.0.${fields_names[$slot]}]-}" "$value"
            run _bo_complete -- "${prefix[@]}" --item -- ''
            assert_success
            assert_output first
            run _bo_complete -- "${prefix[@]}" --item - --it
            assert_success
            assert_output --item
          )
        done
      done
    done
  done
}

@test "record completion selects each pending field after literal dash fields" {
  replay_schema passthrough
  replay_record
  _bo_finalize_schema
  run _bo_complete -- --record ''
  assert_success
  assert_output left
  run _bo_complete -- --record - ''
  assert_success
  assert_output middle
  run _bo_complete -- --record=-- - ''
  assert_success
  assert_output right
  run _bo_complete -- -r -- - right --item ''
  assert_success
  assert_output value
}

@test "implicit options leave following minus positional and consume attached dash values" {
  replay_schema passthrough
  _bo_finalize_schema
  local spelling value
  for spelling in -n --notes; do
    _bo_parse "$spelling" -
    _bo_assign_positionals
    assert_equal "${_bo_raw[first]}" -
    assert_equal "${_bo_multi_values[notes.0]}" default
    run _bo_complete -- "$spelling" - ''
    assert_success
    assert_output second
    run _bo_complete -- "$spelling" - --it
    assert_success
    assert_output --item
  done
  for value in - --; do
    _bo_parse "--notes=$value"
    _bo_assign_positionals
    assert_equal "${#_bo_positional_tokens[@]}" 0
    assert_equal "${_bo_multi_values[notes.0]}" "$value"
    run _bo_complete -- "--notes=$value" ''
    assert_success
    assert_output first
    run _bo_complete -- "--notes=$value" --it
    assert_success
    assert_output --item
  done
}

@test "multi occurrences and bare implicit options keep minus in its actual slot" {
  replay_schema passthrough
  replay_record
  _bo_finalize_schema
  local -a prefix=(--item - -i -- --record - -- right -r left - -- --notes -n --notes=explicit)
  _bo_parse "${prefix[@]}" -
  _bo_assign_positionals
  assert_equal "${_bo_multi_count[item]}" 2
  assert_equal "${_bo_multi_count[record]}" 2
  assert_equal "${_bo_multi_count[notes]}" 3
  assert_equal "${_bo_raw[first]}" -
  run _bo_complete -- "${prefix[@]}" ''
  assert_success
  assert_output first
  run _bo_complete -- "${prefix[@]}" - ''
  assert_success
  assert_output second
  run _bo_complete -- "${prefix[@]}" - --it
  assert_success
  assert_output --item
}

@test "real markers preserve required optional and variadic positional selection" {
  replay_schema variadic
  replay_record
  _bo_finalize_schema
  local -a prefix=(--item -- --record - -- right)
  _bo_parse "${prefix[@]}" -- first second tail
  _bo_assign_positionals
  assert_equal "${_bo_raw[first]}" first
  assert_equal "${_bo_raw[second]}" second
  assert_equal "${_bo_variadic_values[*]}" tail
  local count
  local -a positionals=()
  for count in 0 1 2 3; do
    run _bo_complete -- "${prefix[@]}" -- "${positionals[@]}" --it
    assert_success
    assert_output ''
    run _bo_complete -- "${prefix[@]}" -- "${positionals[@]}" ''
    assert_success
    case "$count" in
      0) assert_output first ;;
      1) assert_output second ;;
      *) assert_output tail ;;
    esac
    positionals+=(literal)
  done
}

@test "genuine unknown options attachments flags and markers still end passthrough completion" {
  replay_schema passthrough
  replay_record
  _bo_finalize_schema
  local token
  for token in -x --unknown --unknown=value --verbose=true --; do
    _bo_parse "$token" --item value
    _bo_assign_positionals
    assert_equal "${_bo_raw[first]}" "$token"
    assert_equal "${_bo_raw[second]}" --item
    assert_equal "${_bo_passthrough_values[*]}" value
    run _bo_complete -- "$token" --it
    assert_success
    assert_output ''
    run _bo_complete -- "$token" ''
    assert_success
    assert_output ''
    _bo_parse - "$token" --item value
    _bo_assign_positionals
    assert_equal "${_bo_raw[first]}" -
    assert_equal "${_bo_raw[second]}" "$token"
    assert_equal "${_bo_passthrough_values[*]}" '--item value'
    run _bo_complete -- - "$token" --it
    assert_success
    assert_output ''
  done
}

@test "boundary-shaped ordinary values and record fields remain literal before actual boundaries" {
  replay_schema passthrough
  replay_record
  _bo_finalize_schema
  local token
  for token in -x --unknown --unknown=value --verbose=true; do
    run _bo_complete -- --item "$token" ''
    assert_success
    assert_output first
    run _bo_complete -- --record "$token" "$token" "$token" ''
    assert_success
    assert_output first
    run _bo_complete -- --record="$token" "$token" "$token" --it
    assert_success
    assert_output --item
    run _bo_complete -- --item "$token" --record left middle right "$token" --it
    assert_success
    assert_output ''
  done
}
