#!/usr/bin/env bash

set -euo pipefail

# Exercise mkltfs against a disposable directory-backed virtual tape.
# This verifies Runtime behavior without a FUSE mount or physical tape device.
prefix=${LTFS_PREFIX:-/usr/local}
format_root=$(mktemp -d /tmp/ltfs-format.XXXXXX)

# Guard the cleanup path so an unexpected variable value cannot remove unrelated data.
cleanup()
{
	case "$format_root" in
		/tmp/ltfs-format.*)
			rm -rf -- "$format_root"
			;;
		*)
			printf 'refusing to remove unexpected format test path: %s\n' "$format_root" >&2
			return 1
			;;
	esac
}
trap cleanup EXIT INT TERM

mkdir "$format_root/tape"
"$prefix/bin/mkltfs" \
	--device="$format_root/tape" \
	--force \
	--tape-serial=SMK001 \
	--volume-name=SMOKETEST >/dev/null

if ! find "$format_root/tape" -mindepth 1 -type f -print -quit | grep -q .; then
	printf 'file backend format test did not create virtual tape files\n' >&2
	exit 1
fi

printf 'LTFS file backend format test passed.\n'
