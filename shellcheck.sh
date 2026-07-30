#!/bin/sh

set -eu
{
	find . -maxdepth 1 \
		-type f \
		\( -name '*.bash' -o -name '*.sh' -o -name '*.bats' \) \
		-print0
	find test \
		-type f \
		\( -name '*.bash' -o -name '*.sh' -o -name '*.bats' \) \
		-print0
} |
{
	if [ "${1-}" = "--list" ]
	then
		xargs -0r printf '%s\n'
	else
		xargs -0r shellcheck
	fi
}