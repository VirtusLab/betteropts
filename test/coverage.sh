#!/usr/bin/env bash
# Measures line coverage of betteropts.sh over the BATS suite using kcov.
#
# kcov's bash engine defaults to /bin/bash, which on macOS is bash 3.2 and
# can't run betteropts.sh (it uses bash 4+ features like `declare -g`). We
# point it at a modern bash via --bash-parser instead. That in turn runs
# into https://github.com/SimonKagstrom/kcov/issues/293: kcov's bash engine
# fails ("Failed to exchange stderr for pipe") when the process's open-file
# limit is much larger than kcov expects, which is the default on macOS
# (ulimit -n == 1048576). Lowering it for the kcov subshell avoids the bug.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

if ! command -v kcov >/dev/null 2>&1
then
  echo "$0: kcov is required" >&2
  exit 1
fi

bash=$(command -v bash)
# shellcheck disable=SC2016
major=$("$bash" -c 'echo "${BASH_VERSINFO[0]}"')
if [[ "$major" -lt 4 ]]
then
  echo "$0: \`bash\` on PATH ($bash) is version $major, need >= 4" >&2
  exit 1
fi

out_dir="${1:-.coverage}"
rm -rf "$out_dir"

(
  ulimit -n 1024
  # hide stderr: https://github.com/SimonKagstrom/kcov/issues/464
  kcov \
    --bash-parser="$bash" \
    --include-path="$(pwd)/betteropts.sh" \
    "$out_dir" \
    test/run.sh 2> /dev/null
)

report_dir="$out_dir/run.sh"
echo
echo "Coverage report: file://$(pwd)/$report_dir/index.html"
jq -r '"Total: \(.percent_covered)% (\(.covered_lines)/\(.total_lines) lines)"' \
  "$report_dir/coverage.json"