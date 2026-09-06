#!/usr/bin/env bash

set -euo pipefail

# One dispatcher keeps self-test available when users replace CMD. Overriding
# ENTRYPOINT still bypasses startup self-test by Docker design.
role=${LTFS_IMAGE_ROLE:-runtime}
self_test_command=${LTFS_SELF_TEST_COMMAND:-/usr/local/bin/ltfs-autotools-self-test}
self_test_on_start=${LTFS_SELF_TEST_ON_START:-0}

case "$self_test_on_start" in
	0 | 1)
		;;
	*)
		printf 'LTFS_SELF_TEST_ON_START must be 0 or 1: %s\n' "$self_test_on_start" >&2
		exit 64
		;;
esac

if [[ ${1:-} == self-test ]]; then
	shift
	exec "$self_test_command" "$@"
fi

if [[ "$self_test_on_start" == 1 ]]; then
	"$self_test_command"
fi

case "$role" in
	ci)
		if (($# == 0)); then
			set -- /usr/local/bin/ltfs-autotools-build
		elif [[ $1 == build ]]; then
			shift
			set -- /usr/local/bin/ltfs-autotools-build "$@"
		fi
		;;
	dev)
		if (($# == 0)); then
			set -- /bin/bash
		fi
		;;
	runtime)
		if (($# == 0)); then
			set -- ltfs --help
		elif [[ $1 == -* ]]; then
			set -- ltfs "$@"
		fi
		;;
	*)
		printf 'LTFS_IMAGE_ROLE must be ci, dev, or runtime: %s\n' "$role" >&2
		exit 64
		;;
esac

exec "$@"
